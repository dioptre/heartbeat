#!/usr/bin/env python3
"""
Heartbeat Audio-Reactive LED Controller for Raspberry Pi
Controls 2x 70W COB LEDs via PWM based on MP3 audio analysis
"""

import RPi.GPIO as GPIO
import numpy as np
import time
import threading
from pathlib import Path

# Audio libraries
try:
    from pydub import AudioSegment
    from pydub.playback import play
    import pyaudio
except ImportError:
    print("Installing required packages...")
    print("Run: sudo apt-get install python3-pyaudio ffmpeg")
    print("Run: pip3 install pydub numpy")
    exit(1)

# ============================================================================
# HARDWARE CONFIGURATION
# ============================================================================

# GPIO pins (hardware PWM capable)
LED_1_PIN = 18  # GPIO 18 (PWM0) - Left/Primary COB
LED_2_PIN = 19  # GPIO 19 (PWM1) - Right/Secondary COB

# PWM settings
PWM_FREQ = 10000  # 10kHz - flicker-free, above audible range
MAX_BRIGHTNESS = 100  # 0-100%
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
        
        # Setup GPIO
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(LED_1_PIN, GPIO.OUT)
        GPIO.setup(LED_2_PIN, GPIO.OUT)
        
        # Setup PWM
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
    
    def process_mp3_file(self, mp3_path):
        """
        Load and process MP3 file for audio-reactive control
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
        print("\nPress Ctrl+C to stop\n")
        
        # Start playback in separate thread
        playback_thread = threading.Thread(target=lambda: play(audio))
        playback_thread.daemon = True
        playback_thread.start()
        
        # Process audio in chunks
        self.running = True
        bytes_per_chunk = CHUNK_SIZE * 2  # 16-bit = 2 bytes per sample
        
        try:
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
    print("  Raspberry Pi + 2x 70W COB LEDs")
    print("=" * 60)
    
    controller = AudioReactiveController()
    
    try:
        # Check for MP3 file argument
        import sys
        
        if len(sys.argv) > 1:
            mp3_path = sys.argv[1]
            
            if not Path(mp3_path).exists():
                print(f"❌ Error: File not found: {mp3_path}")
                return
            
            controller.process_mp3_file(mp3_path)
        else:
            print("\nUsage:")
            print("  python3 heartbeat_led.py <mp3_file>")
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
