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
MAX_BRIGHTNESS = 97.5  # 0-100% duty cycle (97.5% = ~11.7V from 12V supply)
MIN_BRIGHTNESS = 0

# Audio analysis settings
SAMPLE_RATE = 44100
CHUNK_SIZE = 1024  # Smaller = lower latency (~23ms)
SMOOTHING_FACTOR = 0.75  # 0-1, higher = smoother but slower response

# Heartbeat detection
BEAT_THRESHOLD = 1.10  # Multiplier above average for beat detection (very sensitive)
BEAT_DECAY = 0.88  # How fast brightness decays after beat (faster for more visible beats)
MIN_BEAT_INTERVAL = 0.25  # Minimum seconds between beats (max 240 BPM)

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

        if len(audio_array) == 0:
            return 0.0

        # Calculate RMS energy with safety checks
        audio_float = audio_array.astype(np.float64)  # Convert to float to avoid overflow
        mean_square = np.mean(audio_float ** 2)

        if mean_square < 0 or np.isnan(mean_square):
            return self.smoothed_energy

        rms = np.sqrt(mean_square)

        # Normalize (typical 16-bit audio range is ±32768, so RMS max is ~23170)
        normalized_energy = min(rms / 10000.0, 1.0)
        normalized_energy = max(0.0, normalized_energy)  # Ensure non-negative

        # Apply smoothing
        self.smoothed_energy = (SMOOTHING_FACTOR * self.smoothed_energy +
                                (1 - SMOOTHING_FACTOR) * normalized_energy)

        return self.smoothed_energy
    
    def detect_beat(self, energy, current_timestamp=None):
        """
        Detect if current energy represents a beat/heartbeat
        Uses adaptive threshold based on recent energy history
        Args:
            energy: Current energy level (0-1)
            current_timestamp: Optional timestamp in seconds (for preprocessing)
                              If None, uses actual wall clock time
        """
        if current_timestamp is None:
            current_time = time.time()
        else:
            current_time = current_timestamp

        # Update energy history (keep last 30 samples ~0.69s for faster tempo adaptation)
        self.energy_history.append(energy)
        if len(self.energy_history) > 30:
            self.energy_history.pop(0)

        # Use median instead of mean for more robust detection
        if len(self.energy_history) > 10:
            median_energy = np.median(self.energy_history)

            # Beat detected if:
            # 1. Energy significantly exceeds recent median
            # 2. Enough time passed since last beat
            # 3. Energy is above 50% of the known maximum (if analyzed)
            threshold_met = energy > median_energy * BEAT_THRESHOLD

            if hasattr(self, 'audio_max_energy'):
                # Also require energy to be in upper range
                threshold_met = threshold_met and (energy > self.audio_max_energy * 0.5)

            is_beat = (threshold_met and
                      current_time - self.last_beat_time > MIN_BEAT_INTERVAL)
        else:
            is_beat = False

        if is_beat:
            self.last_beat_time = current_time

        return is_beat
    
    def update_leds(self, energy, is_beat):
        """
        Update LED brightness based on energy and beat detection
        Maps actual audio energy range to LED brightness range (40-97%)
        """
        HEARTBEAT_MIN = 40  # Minimum brightness during heartbeat (avoids flicker)
        HEARTBEAT_MAX = 97  # Maximum brightness during heartbeat (97% = 11.64V)

        # Map the audio energy from its actual range to our LED brightness range
        if hasattr(self, 'audio_min_energy') and hasattr(self, 'audio_max_energy'):
            # Normalize energy to 0-1 based on actual audio range
            audio_range = self.audio_max_energy - self.audio_min_energy
            if audio_range > 0:
                normalized = (energy - self.audio_min_energy) / audio_range
                normalized = max(0, min(1, normalized))  # Clamp to 0-1
            else:
                normalized = 0.5

            # Map to LED brightness range
            mapped_brightness = HEARTBEAT_MIN + normalized * (HEARTBEAT_MAX - HEARTBEAT_MIN)
        else:
            # Fallback if audio hasn't been analyzed yet
            mapped_brightness = HEARTBEAT_MIN + energy * (HEARTBEAT_MAX - HEARTBEAT_MIN)

        if is_beat:
            # Beat detected - flash both LEDs to maximum
            self.brightness_1 = HEARTBEAT_MAX
            self.brightness_2 = HEARTBEAT_MAX
        else:
            # Decay brightness
            self.brightness_1 *= BEAT_DECAY
            self.brightness_2 *= BEAT_DECAY

            # Use the mapped brightness as baseline
            self.brightness_1 = max(self.brightness_1, mapped_brightness)
            self.brightness_2 = max(self.brightness_2, mapped_brightness)

        # Clamp values to our safe range
        self.brightness_1 = max(HEARTBEAT_MIN, min(HEARTBEAT_MAX, self.brightness_1))
        self.brightness_2 = max(HEARTBEAT_MIN, min(HEARTBEAT_MAX, self.brightness_2))

        # Update PWM
        self.pwm1.ChangeDutyCycle(self.brightness_1)
        self.pwm2.ChangeDutyCycle(self.brightness_2)
    
    def preprocess_audio(self, raw_data):
        """
        Pre-analyze entire audio file to create timeline of LED states
        Returns: list of (timestamp, energy, is_beat) tuples
        """
        print(f"🔍 Pre-analyzing audio to create LED timeline...")

        bytes_per_chunk = CHUNK_SIZE * 2  # 16-bit = 2 bytes per sample
        timeline = []
        energies = []

        # Reset state for analysis
        self.energy_history = []
        self.smoothed_energy = 0.0
        self.last_beat_time = 0

        # First pass: collect all energies to find min/max
        print(f"   Pass 1/2: Analyzing energy levels...")
        for i in range(0, len(raw_data), bytes_per_chunk):
            chunk = raw_data[i:i+bytes_per_chunk]
            if len(chunk) < bytes_per_chunk:
                break

            energy = self.analyze_audio_chunk(chunk)
            energies.append(energy)

        # Find peak and minimum energy (using percentiles to avoid outliers)
        self.audio_min_energy = np.percentile(energies, 5)   # 5th percentile
        self.audio_max_energy = np.percentile(energies, 95)  # 95th percentile

        print(f"   ✓ Audio range: {self.audio_min_energy:.3f} to {self.audio_max_energy:.3f}")

        # Second pass: detect beats and create timeline
        print(f"   Pass 2/2: Detecting beats and building timeline...")
        self.energy_history = []
        self.smoothed_energy = 0.0
        self.last_beat_time = 0

        chunk_index = 0
        for i in range(0, len(raw_data), bytes_per_chunk):
            chunk = raw_data[i:i+bytes_per_chunk]
            if len(chunk) < bytes_per_chunk:
                break

            # Calculate timestamp for this chunk
            timestamp = chunk_index * CHUNK_SIZE / SAMPLE_RATE

            # Get pre-computed energy from first pass
            raw_energy = energies[chunk_index]

            # Apply smoothing (same as real-time processing)
            self.smoothed_energy = (SMOOTHING_FACTOR * self.smoothed_energy +
                                   (1 - SMOOTHING_FACTOR) * raw_energy)

            # Detect beat using timestamp (not wall clock time)
            is_beat = self.detect_beat(self.smoothed_energy, current_timestamp=timestamp)

            # Store in timeline (use smoothed energy for consistency)
            timeline.append((timestamp, self.smoothed_energy, is_beat))

            chunk_index += 1

        print(f"   ✓ Timeline created: {len(timeline)} frames over {timeline[-1][0]:.1f}s")
        beat_count = sum(1 for _, _, is_beat in timeline if is_beat)
        print(f"   ✓ Detected {beat_count} beats (~{beat_count / (timeline[-1][0] / 60):.0f} BPM)")

        return timeline

    def wait_until_safe(self, target_time):
        """
        Wait until target time without starving audio thread.
        Uses adaptive sleep + minimal busy-wait for precision without audio clipping.
        """
        while True:
            remaining = target_time - time.perf_counter()

            if remaining <= 0:
                break
            elif remaining > 0.010:
                # Sleep for bulk of time (releases CPU to audio thread)
                time.sleep(remaining - 0.005)
            elif remaining > 0.001:
                # Small sleep to yield to other threads
                time.sleep(0.0001)  # 100μs
            else:
                # Final sub-millisecond - quick pass (not a busy loop)
                pass

    def process_mp3_file(self, mp3_path, loop=False, latency_offset=0.0):
        """
        Load and process MP3 file for audio-reactive control with drift-free timing.
        Args:
            mp3_path: Path to MP3 file
            loop: If True, repeat audio forever
            latency_offset: Manual latency compensation in seconds (positive = LEDs earlier)
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

        # Pre-process entire audio to create LED timeline
        timeline = self.preprocess_audio(raw_data)

        print(f"✓ Will map to LED range: 40% to 97%")
        print(f"✓ Starting drift-free synchronized playback...")
        print(f"  - Update rate: ~{CHUNK_SIZE/SAMPLE_RATE*1000:.1f}ms per frame")
        print(f"  - Beat threshold: {BEAT_THRESHOLD}x average")
        if latency_offset != 0:
            print(f"  - Latency offset: {latency_offset*1000:.1f}ms")
        if loop:
            print(f"  - Loop mode: ENABLED (will repeat forever)")
        print("\nPress Ctrl+C to stop\n")

        # Process audio in chunks
        self.running = True

        try:
            loop_count = 0
            while True:
                loop_count += 1
                if loop and loop_count > 1:
                    print(f"\n🔄 Loop #{loop_count} starting...")

                # Start playback in separate thread for this loop iteration
                playback_thread = threading.Thread(target=lambda: play(audio))
                playback_thread.daemon = True

                # Capture absolute start time BEFORE starting playback
                start_time = time.perf_counter()
                playback_thread.start()

                # Apply latency offset to start time
                adjusted_start_time = start_time - latency_offset

                # Play through pre-computed timeline with absolute timing
                for frame_index, (timestamp, energy, is_beat) in enumerate(timeline):
                    if not self.running:
                        break

                    # Calculate absolute target time (no accumulation!)
                    target_time = adjusted_start_time + timestamp

                    # Wait until exact timestamp (drift-free)
                    self.wait_until_safe(target_time)

                    # Update LEDs based on pre-computed values
                    self.update_leds(energy, is_beat)

                    # Debug output - show every 50th frame or if beat detected
                    if is_beat:
                        print(f"💓 BEAT! Time: {timestamp:.2f}s | Energy: {energy:.3f} | Brightness: {self.brightness_1:.0f}%")
                    elif frame_index % 50 == 0:
                        # Show status every ~1 second
                        median = np.median(self.energy_history) if len(self.energy_history) > 0 else 0
                        threshold = median * BEAT_THRESHOLD
                        print(f"   Time: {timestamp:.1f}s | Energy: {energy:.3f} | Threshold: {threshold:.3f} | Brightness: {self.brightness_1:.0f}%")

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

        # Try to set higher process priority for smoother animation
        try:
            os.nice(-10)  # Increase priority (requires sudo or proper permissions)
        except:
            pass  # Silently fail if we don't have permission
        
        patterns = [
            ("Full brightness (both)", MAX_BRIGHTNESS, MAX_BRIGHTNESS, 2),
            ("LED 1 only", MAX_BRIGHTNESS, 0, 1),
            ("LED 2 only", 0, MAX_BRIGHTNESS, 1),
            ("50% brightness", MAX_BRIGHTNESS/2, MAX_BRIGHTNESS/2, 1),
            ("Slow pulse", None, None, 5),
        ]
        
        for name, b1, b2, duration in patterns:
            print(f"  {name}...")
            
            if b1 is None:  # Pulse pattern
                # Smooth pulse: more steps, shorter delay, respects MAX_BRIGHTNESS
                # Use raised sine wave to avoid going too dim
                import gc

                steps = 500  # More steps for smoother animation
                min_pulse_brightness = 40  # 40% minimum brightness to avoid flicker
                max_pulse_brightness = MAX_BRIGHTNESS  # 97.5% maximum

                # Pre-calculate ALL brightness values to avoid computation in loop
                brightnesses = []
                for i in range(steps):
                    sine_value = (np.sin(i * 2 * np.pi / steps) + 1) / 2
                    brightness = min_pulse_brightness + sine_value * (max_pulse_brightness - min_pulse_brightness)
                    brightness = max(MIN_BRIGHTNESS, min(MAX_BRIGHTNESS, brightness))
                    brightnesses.append(brightness)

                # Disable garbage collection during animation to prevent stutters
                gc.disable()

                try:
                    start_time = time.time()
                    step_duration = duration / steps

                    for i, brightness in enumerate(brightnesses):
                        # Update PWM
                        self.pwm1.ChangeDutyCycle(brightness)
                        self.pwm2.ChangeDutyCycle(brightness)

                        # Precise timing: calculate how long to sleep based on actual elapsed time
                        target_time = start_time + (i + 1) * step_duration
                        sleep_time = target_time - time.time()
                        if sleep_time > 0:
                            time.sleep(sleep_time)
                finally:
                    # Re-enable garbage collection
                    gc.enable()
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
        try:
            self.pwm1.stop()
        except:
            pass
        try:
            self.pwm2.stop()
        except:
            pass
        try:
            GPIO.cleanup()
        except:
            pass
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

            # Check for latency offset flag
            latency_offset = 0.0
            for i, arg_item in enumerate(sys.argv):
                if arg_item == '--offset' and i + 1 < len(sys.argv):
                    try:
                        latency_offset = float(sys.argv[i + 1])
                    except ValueError:
                        print(f"⚠️  Warning: Invalid offset value '{sys.argv[i + 1]}', using 0")
                        latency_offset = 0.0
                    break

            # Otherwise treat as MP3 file path
            mp3_path = arg
            if not Path(mp3_path).exists():
                print(f"❌ Error: File not found: {mp3_path}")
                return

            controller.process_mp3_file(mp3_path, loop=loop_mode, latency_offset=latency_offset)
        else:
            print("\nUsage:")
            print("  python3 heartbeat_led.py <mp3_file> [options]")
            print("\nOptions:")
            print("  --loop, -l           Repeat audio forever")
            print("  --offset <seconds>   Latency compensation in seconds (can be negative)")
            print("                       Examples:")
            print("                         --offset 0.02   (LEDs 20ms earlier)")
            print("                         --offset -0.03  (LEDs 30ms later)")
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
