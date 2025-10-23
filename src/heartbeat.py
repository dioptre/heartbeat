#!/usr/bin/env python3
"""
Heartbeat Audio-Reactive LED Controller for Raspberry Pi
Controls 2x 70W COB LEDs via PWM based on MP3 audio analysis
Compatible with Raspberry Pi 4 and Raspberry Pi 5
"""

import numpy as np
import time
import threading
import subprocess
from pathlib import Path
import os
import re

# GPIO library - Use RPi.GPIO-compatible library that works on Pi 5
try:
    import RPi.GPIO as GPIO
except ImportError:
    print("⚠️  RPi.GPIO not found. Installing rpi-lgpio (Pi 5 compatible)...")
    print("Run: pip3 install rpi-lgpio")
    exit(1)

# Audio libraries
try:
    from pydub import AudioSegment
    from pydub.playback import play
    import pyaudio
except ImportError:
    print("⚠️  Audio libraries not found.")
    print("Run: sudo apt-get install python3-pyaudio ffmpeg")
    print("Run: pip3 install pydub numpy")
    exit(1)

# ============================================================================
# RASPBERRY PI VERSION DETECTION
# ============================================================================

def detect_pi_version():
    """
    Detect Raspberry Pi version (4 or 5)
    Returns: int (4 or 5) or None if cannot detect
    """
    try:
        with open('/proc/device-tree/model', 'r') as f:
            model = f.read()
            if 'Raspberry Pi 5' in model:
                return 5
            elif 'Raspberry Pi 4' in model or 'Raspberry Pi 3' in model:
                return 4
            else:
                # Default to Pi 4 behavior for older models
                return 4
    except:
        print("⚠️  Warning: Could not detect Pi version, assuming Pi 4")
        return 4

PI_VERSION = detect_pi_version()

# ============================================================================
# HARDWARE CONFIGURATION
# ============================================================================

# GPIO pins (hardware PWM capable)
LED_1_PIN = 18  # GPIO 18 - Left/Primary COB - PWM0_CHAN2 on Pi 5, PWM0 on Pi 4
LED_2_PIN = 19  # GPIO 19 - Right/Secondary COB - PWM1_CHAN2 on Pi 5, PWM1 on Pi 4

# Note: rpi-lgpio library automatically handles the PWM channel differences
# between Pi 4 (channels 0/1) and Pi 5 (channels 2/3) when using GPIO.PWM()

# PWM settings
PWM_FREQ = 10000  # 10kHz - flicker-free, above audible range
MAX_BRIGHTNESS = 83  # 0-100% duty cycle (83% = ~10V from 12V supply)
MIN_BRIGHTNESS = 0

# Audio analysis settings
SAMPLE_RATE = 44100
CHUNK_SIZE = 1024  # Smaller = lower latency (~23ms)
SMOOTHING_FACTOR = 0.7  # 0-1, higher = smoother but slower response

# Heartbeat detection
BEAT_THRESHOLD = 1.5  # Multiplier above average for beat detection
BEAT_DECAY = 0.95  # How fast brightness decays after beat
MIN_BEAT_INTERVAL = 0.3  # Minimum seconds between beats (max 200 BPM)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def check_pi5_config():
    """
    Check if Raspberry Pi 5 has the required PWM configuration
    Returns: (bool, str) - (is_configured, status_message)
    """
    if PI_VERSION != 5:
        return True, "Not Pi 5"  # Not Pi 5, no check needed

    # Check config.txt for overlay
    has_overlay = False
    try:
        with open('/boot/firmware/config.txt', 'r') as f:
            config = f.read()
            if 'dtoverlay=pwm-2chan' in config or 'dtoverlay=pwm' in config:
                has_overlay = True
    except:
        pass

    if not has_overlay:
        return False, "Missing dtoverlay=pwm-2chan in /boot/firmware/config.txt"

    # Verify GPIO pins are actually configured for PWM using pinctrl
    # On Pi 5: GPIO 18 should be alt3 (PWM0_CHAN2), GPIO 19 should be alt3 (PWM1_CHAN2)
    try:
        # Check GPIO 18
        result_18 = subprocess.run(['pinctrl', 'get', '18'],
                                  capture_output=True, text=True, timeout=2)
        # Check GPIO 19
        result_19 = subprocess.run(['pinctrl', 'get', '19'],
                                  capture_output=True, text=True, timeout=2)

        # Look for "a3" which indicates alt3 (PWM function)
        # Format: "18: a3 pd | hi // GPIO18 = PWM0_CHAN2"
        gpio18_ok = 'a3' in result_18.stdout and 'PWM' in result_18.stdout
        gpio19_ok = 'a3' in result_19.stdout and 'PWM' in result_19.stdout

        if gpio18_ok and gpio19_ok:
            return True, "GPIO 18 and 19 configured for PWM (alt3)"
        elif not gpio18_ok and not gpio19_ok:
            return False, "GPIOs not in PWM mode - reboot may be required"
        else:
            failed = []
            if not gpio18_ok:
                failed.append("GPIO 18")
            if not gpio19_ok:
                failed.append("GPIO 19")
            return False, f"{', '.join(failed)} not in PWM mode"

    except (subprocess.TimeoutExpired, FileNotFoundError):
        # pinctrl not available or timeout - fall back to config check only
        return True, "Config file OK (pinctrl verification skipped)"
    except Exception:
        # Any other error - assume it's OK if config file is correct
        return True, "Config file OK (pinctrl verification failed)"

# ============================================================================
# GLOBAL STATE
# ============================================================================

class AudioReactiveController:
    def __init__(self):
        self.running = False
        self.brightness_1 = 0.0
        self.brightness_2 = 0.0
        self.last_beat_time = 0
        self.energy_history = []
        self.smoothed_energy = 0.0

        # Display Pi version
        print(f"🔍 Detected: Raspberry Pi {PI_VERSION}")

        # Check Pi 5 configuration
        if PI_VERSION == 5:
            is_configured, status_msg = check_pi5_config()
            if not is_configured:
                print("\n⚠️  WARNING: Raspberry Pi 5 PWM configuration issue!")
                print(f"   Status: {status_msg}")
                print("\n   To fix:")
                print("   1. Run: sudo bash setup_pi5.sh")
                print("   2. Reboot: sudo reboot")
                print("   3. Verify with: pinctrl get 18 19\n")
            else:
                print(f"✓ Pi 5 PWM verified: {status_msg}")

        # Setup GPIO
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(LED_1_PIN, GPIO.OUT)
        GPIO.setup(LED_2_PIN, GPIO.OUT)

        # Setup PWM with appropriate channels for Pi version
        self.pwm1 = GPIO.PWM(LED_1_PIN, PWM_FREQ)
        self.pwm2 = GPIO.PWM(LED_2_PIN, PWM_FREQ)
        self.pwm1.start(0)
        self.pwm2.start(0)

        print(f"✓ GPIO initialized: LED1=GPIO{LED_1_PIN}, LED2=GPIO{LED_2_PIN}")
        print(f"✓ PWM frequency: {PWM_FREQ}Hz")
    
    def analyze_audio_chunk(self, audio_data):
        """
        Analyze audio chunk and return energy level (0-1)
        """
        # Convert to numpy array
        audio_array = np.frombuffer(audio_data, dtype=np.int16)
        
        # Calculate RMS energy
        rms = np.sqrt(np.mean(audio_array**2))
        
        # Normalize (typical 16-bit audio range)
        normalized_energy = min(rms / 5000.0, 1.0)
        
        # Apply smoothing
        self.smoothed_energy = (SMOOTHING_FACTOR * self.smoothed_energy + 
                                (1 - SMOOTHING_FACTOR) * normalized_energy)
        
        return self.smoothed_energy
    
    def detect_beat(self, energy):
        """
        Detect if current energy represents a beat/heartbeat
        """
        current_time = time.time()
        
        # Update energy history (keep last 50 samples)
        self.energy_history.append(energy)
        if len(self.energy_history) > 50:
            self.energy_history.pop(0)
        
        # Calculate average energy
        avg_energy = np.mean(self.energy_history) if self.energy_history else 0
        
        # Beat detected if:
        # 1. Energy exceeds threshold
        # 2. Enough time passed since last beat
        is_beat = (energy > avg_energy * BEAT_THRESHOLD and 
                   current_time - self.last_beat_time > MIN_BEAT_INTERVAL)
        
        if is_beat:
            self.last_beat_time = current_time
            
        return is_beat
    
    def update_leds(self, energy, is_beat):
        """
        Update LED brightness based on energy and beat detection
        """
        if is_beat:
            # Beat detected - flash both LEDs
            self.brightness_1 = 100.0
            self.brightness_2 = 100.0
        else:
            # Decay brightness and add baseline energy response
            self.brightness_1 *= BEAT_DECAY
            self.brightness_2 *= BEAT_DECAY
            
            # Add continuous energy-reactive component
            baseline = energy * 30  # 0-30% based on continuous audio
            self.brightness_1 = max(self.brightness_1, baseline)
            self.brightness_2 = max(self.brightness_2, baseline)
        
        # Clamp values
        self.brightness_1 = max(MIN_BRIGHTNESS, min(MAX_BRIGHTNESS, self.brightness_1))
        self.brightness_2 = max(MIN_BRIGHTNESS, min(MAX_BRIGHTNESS, self.brightness_2))
        
        # Update PWM
        self.pwm1.ChangeDutyCycle(self.brightness_1)
        self.pwm2.ChangeDutyCycle(self.brightness_2)
    
    def process_mp3_file(self, mp3_path, loop=False):
        """
        Load and process MP3 file for audio-reactive control
        Args:
            mp3_path: Path to MP3 file
            loop: If True, repeat audio forever
        """
        print(f"\n🎵 Loading: {mp3_path}")

        # Load MP3
        audio = AudioSegment.from_mp3(mp3_path)

        # Convert to mono, 44.1kHz
        audio = audio.set_channels(1).set_frame_rate(SAMPLE_RATE)

        # Get raw audio data
        raw_data = audio.raw_data

        print(f"✓ Duration: {len(audio)/1000:.1f}s")
        print(f"✓ Sample rate: {audio.frame_rate}Hz")
        print(f"✓ Starting audio-reactive control...")
        print(f"  - Chunk size: {CHUNK_SIZE} samples (~{CHUNK_SIZE/SAMPLE_RATE*1000:.1f}ms latency)")
        print(f"  - Beat threshold: {BEAT_THRESHOLD}x average")
        if loop:
            print(f"  - Loop mode: ENABLED (will repeat forever)")
        print("\nPress Ctrl+C to stop\n")

        # Process audio in chunks
        self.running = True
        bytes_per_chunk = CHUNK_SIZE * 2  # 16-bit = 2 bytes per sample

        try:
            loop_count = 0
            while True:
                # Start playback in separate thread for this loop iteration
                playback_thread = threading.Thread(target=lambda: play(audio))
                playback_thread.daemon = True
                playback_thread.start()

                if loop:
                    loop_count += 1
                    if loop_count > 1:
                        print(f"\n🔄 Loop #{loop_count} starting...")

                for i in range(0, len(raw_data), bytes_per_chunk):
                    if not self.running:
                        break

                    chunk = raw_data[i:i+bytes_per_chunk]

                    if len(chunk) < bytes_per_chunk:
                        break

                    # Analyze audio
                    energy = self.analyze_audio_chunk(chunk)
                    is_beat = self.detect_beat(energy)

                    # Update LEDs
                    self.update_leds(energy, is_beat)

                    # Debug output
                    if is_beat:
                        print(f"💓 BEAT! Energy: {energy:.2f} | LED1: {self.brightness_1:.0f}% LED2: {self.brightness_2:.0f}%")

                    # Timing sync (simulate real-time playback)
                    time.sleep(CHUNK_SIZE / SAMPLE_RATE)

                # Wait for playback to finish
                playback_thread.join()

                # If not looping, break after one playthrough
                if not loop or not self.running:
                    break

        except KeyboardInterrupt:
            print("\n\n⏹  Stopped by user")
        
        finally:
            # Fade out
            print("Fading out...")
            for brightness in range(int(max(self.brightness_1, self.brightness_2)), -1, -5):
                self.pwm1.ChangeDutyCycle(brightness)
                self.pwm2.ChangeDutyCycle(brightness)
                time.sleep(0.02)
    
    def test_pattern(self):
        """
        Run a test pattern to verify hardware
        """
        print("\n🔧 Running hardware test pattern...\n")
        
        patterns = [
            ("Full brightness (both)", 100, 100, 2),
            ("LED 1 only", 100, 0, 1),
            ("LED 2 only", 0, 100, 1),
            ("50% brightness", 50, 50, 1),
            ("Slow pulse", None, None, 5),
        ]
        
        for name, b1, b2, duration in patterns:
            print(f"  {name}...")
            
            if b1 is None:  # Pulse pattern
                for i in range(50):
                    brightness = (np.sin(i * 0.2) + 1) * 50
                    self.pwm1.ChangeDutyCycle(brightness)
                    self.pwm2.ChangeDutyCycle(brightness)
                    time.sleep(0.1)
            else:
                self.pwm1.ChangeDutyCycle(b1)
                self.pwm2.ChangeDutyCycle(b2)
                time.sleep(duration)
        
        # Turn off
        self.pwm1.ChangeDutyCycle(0)
        self.pwm2.ChangeDutyCycle(0)
        print("\n✓ Test complete\n")
    
    def cleanup(self):
        """
        Clean up GPIO
        """
        self.running = False
        self.pwm1.stop()
        self.pwm2.stop()
        GPIO.cleanup()
        print("\n✓ GPIO cleaned up")


# ============================================================================
# MAIN PROGRAM
# ============================================================================

def main():
    print("=" * 60)
    print("  Heartbeat Audio-Reactive LED Controller")
    print(f"  Raspberry Pi {PI_VERSION} + 2x 70W COB LEDs")
    print("=" * 60)
    
    controller = AudioReactiveController()
    
    try:
        # Check for MP3 file argument
        import sys
        
        if len(sys.argv) > 1:
            arg = sys.argv[1]

            # Check if test pattern requested
            if arg.lower() == 'test':
                controller.test_pattern()
                return

            # Check for loop flag
            loop_mode = '--loop' in sys.argv or '-l' in sys.argv

            # Otherwise treat as MP3 file path
            mp3_path = arg
            if not Path(mp3_path).exists():
                print(f"❌ Error: File not found: {mp3_path}")
                return

            controller.process_mp3_file(mp3_path, loop=loop_mode)
        else:
            print("\nUsage:")
            print("  python3 heartbeat_led.py <mp3_file> [--loop]")
            print("\nOptions:")
            print("  --loop, -l    Repeat audio forever")
            print("\nOr run test pattern:")
            print("  python3 heartbeat_led.py test")
            print()
            
            # Offer test pattern
            choice = input("Run test pattern? (y/n): ").lower()
            if choice == 'y':
                controller.test_pattern()
    
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        controller.cleanup()


if __name__ == "__main__":
    main()
