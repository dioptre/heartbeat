# Heartbeat Audio-Reactive LED Controller

Real-time audio-reactive lighting using Raspberry Pi and high-power COB LEDs. Detects and responds to heartbeat sounds in MP3 files with <25ms latency for instant visual feedback.

## Quick Start

**For Raspberry Pi 5 users (one-time setup):**
```bash
sudo bash setup_pi5.sh
sudo reboot
```

**For all Raspberry Pi versions:**
```bash
python3 src/heartbeat.py heartbeat.mp3
```

---

## Overview

This project uses a Raspberry Pi to control two 70W COB LED panels that pulse and react to audio, specifically designed for heartbeat sounds. The LEDs dim in and out in sync with the audio, flashing bright on detected beats and maintaining a subtle glow during quieter moments.

---

## Hardware Components

### Core Components

| Component | Specs | Quantity | Cost | Link |
|-----------|-------|----------|------|------|
| **COB LED Panels** | Symbuth 70W, 12V DC, 3000K warm white, 8.7"x4.4" | 2 | $25.98 | [Amazon](https://amazon.com) |
| **Power Supply** | Mean Well LRS-350-12, 12V 29A (348W) | 1 | $33.50 | [Amazon](https://amazon.com) |
| **MOSFETs** | IRLZ44N Logic-Level N-Channel (10-pack) | 1 | $9.99 | [Amazon](https://amazon.com) |
| **Wire - Power** | 18 AWG stranded (red/black, 25ft each) | 1 | $6.99 | [Amazon](https://amazon.com) |
| **Wire - Signal** | 24 AWG hookup wire kit (6 colors, 32.8ft each) | 1 | $14.85 | [Amazon](https://amazon.com) |
| **Thermal Paste** | Arctic Silver 5 | 1 | $11.99 | [Amazon](https://amazon.com) |

### Passive Components
- **2x 10kΩ resistors** (1/4W, pull-down for MOSFET gates)
- **2x 220Ω resistors** (1/4W, gate current limiting)

### Optional but Recommended
- **Heatsinks**: 120mm x 120mm aluminum heatsinks (2x @ $12.99 each) if running continuously
- **Note**: For pulsing heartbeat patterns, heatsinks may not be necessary due to natural cooling periods

**Total Cost: ~$103** (without optional heatsinks)

---

## LED Specifications

- **Power**: 35W @ 12V, 70W @ 14V (we use 12V = 35W each)
- **Current draw**: ~3A per COB @ 12V
- **Lumens**: ~3,850 lumens per COB @ 12V (110 lm/W efficiency)
- **Total output**: ~7,700 lumens (2x brighter than reference light)
- **Color temp**: 3000K warm white, CRI >80
- **Beam angle**: 120°
- **Emitting area**: 8" x 3.9"
- **Backing**: Aluminum plate (aids heat dissipation)

---

## Circuit Design

### Wiring Diagram

```
[12V PSU (+)] ───┬──────────────┬──> COB #1 (+)
                 │              │
                 │              └──> MOSFET #1 (Drain)
                 │                      │
                 │                   Source ──> GND
                 │                      │
                 │                   Gate ← 220Ω ← GPIO 18 (Pi)
                 │                      │
                 │                    10kΩ (pull-down)
                 │                      │
                 │                     GND
                 │
                 └──────────────┬──> COB #2 (+)
                                │
                                └──> MOSFET #2 (Drain)
                                        │
                                     Source ──> GND
                                        │
                                     Gate ← 220Ω ← GPIO 19 (Pi)
                                        │
                                      10kΩ (pull-down)
                                        │
                                       GND

[12V PSU (-)] ────────────────────────────────> GND (common ground with Pi)
```

### Per-COB Circuit Detail

```
Raspberry Pi GPIO (18 or 19)
    │
    ├─── 220Ω ───┬──> MOSFET Gate (IRLZ44N)
    │            │
    │          10kΩ (pull-down)
    │            │
    └───────────GND

MOSFET Connections:
  Drain  ──> COB (-)
  Source ──> GND
  Gate   ──> Control circuit above
```

### GPIO Pin Assignment

- **GPIO 18** (Physical pin 12): COB #1 - Hardware PWM0
- **GPIO 19** (Physical pin 35): COB #2 - Hardware PWM1
- **GND**: Common ground between Pi and power supply

### Raspberry Pi 5 Support

This project works on both **Raspberry Pi 4** and **Raspberry Pi 5**!

**For Raspberry Pi 5 users:**
- The code automatically detects your Pi version
- GPIO pins remain the same (GPIO 18 and 19)
- **One-time setup required:**
  ```bash
  sudo bash setup_pi5.sh
  sudo reboot
  ```
- This adds `dtoverlay=pwm-2chan` to your config file

**Technical differences:**
- **Pi 4 and earlier**: Uses PWM channels 0 and 1
- **Pi 5**: Uses PWM channels 2 and 3 (handled automatically by the code)

---

## Why This Design Works

### Power Supply Choice
- **350W is intentionally oversized** (only using ~80W total)
- Benefits: Cooler operation, longer lifespan, clean power, future expansion headroom
- Mean Well LRS series: Industrial quality, low ripple, excellent for LED projects

### MOSFET Control
- **Logic-level MOSFETs** work directly with Raspberry Pi's 3.3V GPIO
- **Low-side switching** (on the ground path) simplifies circuit
- **Hardware PWM** at 10kHz provides flicker-free dimming above audible range
- MOSFETs switch, not dissipate, so they stay cool (no heatsink needed for MOSFETs)

### LED Choice
- **12V operation** keeps circuit simple (no buck converters needed)
- **COB (Chip-On-Board)** design provides uniform, soft light with high lumen output
- **Built-in aluminum backing** provides heat dissipation
- Reviews confirm excellent dimming behavior with PWM

---

## Software Setup

### Prerequisites

```bash
# Update system
sudo apt-get update

# Install system dependencies
sudo apt-get install python3-pip python3-pyaudio ffmpeg

# Install Python packages
pip3 install pydub numpy

# Install GPIO library (Pi 5 compatible)
# For Raspberry Pi 5, use rpi-lgpio (drop-in replacement for RPi.GPIO):
pip3 install rpi-lgpio

# For Raspberry Pi 4 and earlier, you can use either:
pip3 install RPi.GPIO
# OR
pip3 install rpi-lgpio  # Works on all Pi versions
```

**Note:** `rpi-lgpio` is recommended as it works on **all Raspberry Pi versions** (Pi 3, 4, and 5). The original `RPi.GPIO` library does not work on Pi 5 due to hardware changes.

### Configuration Parameters

Edit these in `heartbeat_led.py` to tune performance:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PWM_FREQ` | 10000 Hz | PWM frequency (flicker-free) |
| `CHUNK_SIZE` | 1024 samples | Audio chunk size (~23ms latency) |
| `SMOOTHING_FACTOR` | 0.7 | 0-1, higher = smoother response |
| `BEAT_THRESHOLD` | 1.5 | Multiplier above average for beat detection |
| `BEAT_DECAY` | 0.95 | How fast brightness fades after beat |
| `MIN_BEAT_INTERVAL` | 0.3 sec | Minimum time between beats (max 200 BPM) |

---

## Usage

### Basic Usage

```bash
# Play MP3 with reactive lighting
python3 heartbeat_led.py heartbeat.mp3

# Run hardware test pattern (verify wiring first!)
python3 heartbeat_led.py test
```

### Test Pattern
The test pattern cycles through:
1. Full brightness (both COBs)
2. LED 1 only
3. LED 2 only
4. 50% brightness
5. Slow pulse pattern

Use this to verify your wiring before running the full audio-reactive code.

### Expected Behavior

- ✅ Loads MP3 and synchronizes playback with LED control
- ✅ Both COBs flash to 100% brightness on detected beats
- ✅ Smooth decay between beats
- ✅ Subtle baseline glow (0-30%) tracks continuous audio energy
- ✅ Console prints `💓 BEAT!` when heartbeat detected
- ✅ Press `Ctrl+C` to stop (LEDs fade out gracefully)

---

## Audio Analysis

### How It Works

1. **Loads MP3** file and converts to mono, 44.1kHz
2. **Processes in chunks** of 1024 samples (~23ms) for low latency
3. **Calculates RMS energy** of each chunk
4. **Applies smoothing** to prevent jitter
5. **Detects beats** when energy exceeds 1.5x recent average
6. **Updates LEDs** via hardware PWM in real-time

### Beat Detection Algorithm

- Maintains rolling history of last 50 energy samples
- Beat triggered when current energy > average × threshold
- Enforces minimum interval between beats (prevents false triggers)
- Adaptive threshold automatically adjusts to track dynamics

### Latency Breakdown

| Stage | Time |
|-------|------|
| Audio chunk | ~23ms |
| Analysis | <1ms |
| PWM update | <1ms |
| **Total** | **<25ms** |

This is fast enough to feel instantaneous to human perception.

---

## Tuning Guide

### More Sensitive to Beats
```python
BEAT_THRESHOLD = 1.3      # Lower threshold
MIN_BEAT_INTERVAL = 0.2   # Allow faster beats
```

### Smoother Response
```python
SMOOTHING_FACTOR = 0.85   # More smoothing
BEAT_DECAY = 0.98         # Slower fade
```

### Faster Response
```python
SMOOTHING_FACTOR = 0.5    # Less smoothing
CHUNK_SIZE = 512          # Smaller chunks (~12ms latency)
```

### More Dramatic Effect
```python
BEAT_DECAY = 0.90         # Faster fade after beat
BEAT_THRESHOLD = 1.8      # Only strong beats trigger
```

---

## Safety & Thermal Management

### Power Safety
- ⚠️ **High current**: Each COB draws ~3A at 12V
- ⚠️ **Proper wire gauge**: Use 18 AWG for power (rated for 10A)
- ⚠️ **Fuse recommended**: Add 10A fuse on 12V+ line
- ⚠️ **Secure connections**: Solder or use quality screw terminals
- ⚠️ **Common ground**: Ensure Pi and PSU share common ground

### Heat Management
- COBs generate ~25-30W heat each at 35W electrical input
- Built-in aluminum backing provides passive cooling
- **For continuous operation**: Add 120mm x 120mm heatsinks with thermal paste
- **For pulsing heartbeat**: Natural cooling during off-periods usually sufficient
- **Monitor temperature**: Touch test or IR thermometer, keep <60°C to touch
- **Mounting orientation**: Vertical mounting improves natural convection

### Soldering Tips
- Reviews note aluminum backing is difficult to solder
- Use **high-temperature iron** (400°C+) and **plenty of flux**
- Pre-tin the pads before attaching wires
- Alternative: Use **screw terminals** or **spring-loaded test clips**

---

## Troubleshooting

### LEDs Don't Light Up
- Check power supply is plugged in and switched on
- Verify 12V present at COB terminals with multimeter
- Check MOSFET orientation (Drain, Source, Gate correct)
- Verify common ground between Pi and PSU
- Run test pattern to isolate hardware vs software

### LEDs Flicker or Strobe
- Increase `SMOOTHING_FACTOR` (0.8-0.9)
- Check PWM frequency is 10kHz (above visible flicker range)
- Verify using hardware PWM pins (GPIO 18/19)
- Check for loose connections

### LEDs Stay Dim / Don't Respond to Beats
- Lower `BEAT_THRESHOLD` (try 1.2)
- Check audio file has clear beats
- Verify audio analysis with console output
- Increase volume of audio file if very quiet

### LEDs Stay On Full Brightness
- Check for shorted MOSFET (Drain-Source)
- Verify 10kΩ pull-down resistors installed
- Check GPIO pins not stuck high

### Audio Playback Issues
- Ensure `ffmpeg` installed: `sudo apt-get install ffmpeg`
- Check MP3 file is valid (play with `mpg123` or similar)
- Verify file path is correct

### Overheating
- Reduce continuous brightness (lower `MAX_BRIGHTNESS`)
- Add heatsinks with thermal paste
- Improve ventilation/airflow
- Consider active cooling (fan) if enclosed

---

## Performance Notes

### Why 12V (not 14V)?
- At 12V: 35W per COB, cooler operation, longer LED lifespan
- At 14V: 70W per COB, much hotter, risks overheating without active cooling
- For heartbeat pulsing, 35W provides plenty of brightness

### Why Hardware PWM?
- **Software PWM** can jitter with CPU load, causing visible flicker
- **Hardware PWM** uses dedicated timer, perfectly consistent
- Raspberry Pi has only 2 hardware PWM channels (GPIO 18 & 19) - perfect for 2 COBs

### Latency Considerations
- 23ms latency is below human detection threshold (~50-100ms for audio-visual sync)
- Smaller chunks = lower latency but higher CPU usage
- 1024 samples @ 44.1kHz is optimal balance

---

## Future Enhancements

### Possible Additions
- **Stereo analysis**: Left channel controls COB #1, right controls COB #2
- **Multiple effects**: Switch between patterns (heartbeat, breathing, pulse waves)
- **Web interface**: Control via smartphone
- **Real-time audio input**: Use USB microphone instead of MP3
- **Additional LEDs**: Add accent lighting (still have power supply headroom)
- **DMX control**: Integrate with professional lighting systems

### Hardware Expansion
The 350W power supply has plenty of headroom:
- Current usage: ~80W (23% of capacity)
- Can add: More COBs, LED strips, fans, additional effects
- Keep total below 300W for safe operation

---

## Technical Specifications Summary

| Parameter | Value |
|-----------|-------|
| **Input Voltage** | 12V DC |
| **Total Power** | ~80W (70W LEDs + 10W Pi) |
| **Total Current** | ~6A @ 12V |
| **Light Output** | ~7,700 lumens total |
| **Color Temperature** | 3000K warm white |
| **PWM Frequency** | 10 kHz |
| **Audio Latency** | <25ms |
| **Sample Rate** | 44.1 kHz |
| **Control Resolution** | 10-bit (1024 steps) |

---

## License & Credits

This project is provided as-is for educational and personal use.

### Components Used
- Symbuth COB LED panels
- Mean Well LRS-350-12 power supply
- Raspberry Pi (any model with GPIO 18/19)
- Standard electronic components

### Software Dependencies
- RPi.GPIO - Raspberry Pi GPIO control
- pydub - Audio file processing
- pyaudio - Audio playback
- numpy - Numerical processing

---

## Questions?

Common issues and solutions are in the **Troubleshooting** section above.

For hardware questions, consult:
- COB LED datasheet/reviews on Amazon
- Raspberry Pi GPIO pinout: `pinout.xyz`
- Mean Well PSU manual

**Safety First**: Always double-check wiring before powering on. 12V is relatively safe, but high current can still cause damage or fire risk with poor connections.

---

*Last updated: October 2025*
