# Dependencies Documentation

This document lists all dependencies required for the Heartbeat Audio-Reactive LED Controller project.

## Quick Setup

```bash
make install        # Install everything
make setup-pi5      # If using Raspberry Pi 5
sudo reboot         # Required after Pi 5 setup
make test          # Test hardware
```

---

## System Dependencies

### Build Tools
These are required to compile Python packages and native extensions:

| Package | Purpose | Required By |
|---------|---------|-------------|
| `make` | Build automation | Project setup |
| `build-essential` | GCC compiler and tools | Native Python packages |
| `swig` | Interface generator | lgpio |
| `libssl-dev` | SSL/TLS library | Python builds |
| `libffi-dev` | Foreign function interface | Python packages |

### Python Build Dependencies
Required for building Python from source (if using pyenv):

| Package | Purpose |
|---------|---------|
| `zlib1g-dev` | Compression library |
| `libbz2-dev` | BZ2 compression |
| `libreadline-dev` | Terminal input handling |
| `libsqlite3-dev` | SQLite database |
| `libncursesw5-dev` | Terminal UI library |
| `tk-dev` | Tkinter GUI support |
| `libxml2-dev` | XML parsing |
| `libxmlsec1-dev` | XML security |
| `liblzma-dev` | LZMA compression |
| `llvm` | LLVM compiler infrastructure |
| `xz-utils` | XZ compression |
| `wget` | File download utility |
| `curl` | HTTP client |

### Audio Libraries
Required for audio processing and playback:

| Package | Purpose | Used By |
|---------|---------|---------|
| `python3-pyaudio` | System Python audio bindings | PyAudio |
| `ffmpeg` | Audio/video processing | pydub |
| `portaudio19-dev` | Cross-platform audio I/O | PyAudio |
| `libasound2-dev` | ALSA sound library | PyAudio |
| `libjack-jackd2-dev` | JACK audio system | PyAudio |

### GPIO Libraries
Required for Raspberry Pi GPIO control:

| Package | Purpose | Used By |
|---------|---------|---------|
| `liblgpio-dev` | Linux GPIO library | rpi-lgpio |

---

## Python Dependencies

All Python dependencies are managed in `pyproject.toml` and installed automatically.

### Core Dependencies

#### numpy >= 1.24.0
- **Purpose**: Numerical processing for audio analysis
- **Used For**:
  - RMS energy calculation
  - Audio signal processing
  - Beat detection algorithms

#### pydub >= 0.25.1
- **Purpose**: Audio file processing
- **Used For**:
  - Loading MP3 files
  - Audio format conversion
  - Sample rate conversion to 44.1kHz
  - Mono conversion
- **Requires**: `ffmpeg` system package

#### pyaudio >= 0.2.13
- **Purpose**: Audio playback
- **Used For**:
  - Real-time audio streaming
  - Synchronized playback with LED control
- **Requires**: `python3-pyaudio`, `portaudio19-dev` system packages

#### rpi-lgpio >= 0.4
- **Purpose**: Raspberry Pi GPIO control
- **Used For**:
  - Hardware PWM generation
  - GPIO pin configuration
  - LED control via MOSFETs
- **Compatibility**: Works on Pi 3, Pi 4, and Pi 5
- **Requires**: `liblgpio-dev` system package
- **Note**: Drop-in replacement for deprecated RPi.GPIO

### Development Dependencies (Optional)

#### pytest >= 7.0.0
- **Purpose**: Unit testing framework
- **Install**: `uv pip install -e .[dev]`

#### black >= 23.0.0
- **Purpose**: Code formatting
- **Install**: `uv pip install -e .[dev]`

#### ruff >= 0.1.0
- **Purpose**: Fast Python linter
- **Install**: `uv pip install -e .[dev]`

---

## Hardware Dependencies

### Required Hardware
- **Raspberry Pi**: Model 3, 4, or 5
- **Power Supply**: Mean Well LRS-350-12 (12V 29A)
- **LEDs**: 2x Symbuth 70W COB LED panels (12V)
- **MOSFETs**: 2x IRLZ44N logic-level N-channel
- **Resistors**:
  - 2x 10kΩ (pull-down)
  - 2x 220Ω (gate current limiting)
- **Wire**: 18 AWG for power, 24 AWG for signals

### GPIO Pins Used
- **GPIO 18** (Physical pin 12): LED #1 - Hardware PWM0
- **GPIO 19** (Physical pin 35): LED #2 - Hardware PWM1

---

## Raspberry Pi 5 Specific Requirements

### PWM Configuration
Pi 5 requires a device tree overlay for PWM functionality:

1. **Configuration File**: `/boot/firmware/config.txt`
2. **Required Line**: `dtoverlay=pwm-2chan`
3. **Setup Script**: `sudo bash setup_pi5.sh`
4. **Reboot Required**: Yes

### PWM Channel Differences
- **Pi 4 and earlier**: Uses PWM channels 0 and 1
- **Pi 5**: Uses PWM channels 2 and 3
- **Note**: The `rpi-lgpio` library handles this automatically

### Verification
After setup and reboot, verify with:
```bash
pinctrl get 18 19
```

Expected output:
```
18: a3 pd | hi // GPIO18 = PWM0_CHAN2
19: a3 pd | hi // GPIO19 = PWM1_CHAN2
```

---

## Installation Order

The correct installation order is:

1. **System Dependencies** (Makefile: `install-system`)
   - Build tools first
   - Python build dependencies
   - Audio libraries
   - GPIO libraries

2. **Python Environment** (Automatically handled)
   - Virtual environment creation
   - Python package installation

3. **Python Dependencies** (Makefile: `install-python`)
   - Install from pyproject.toml
   - Uses uv for fast installation

4. **Pi 5 Setup** (If applicable - Makefile: `setup-pi5`)
   - Configure PWM overlay
   - Reboot system

---

## Troubleshooting Dependencies

### PyAudio Build Fails
**Error**: `fatal error: portaudio.h: No such file or directory`

**Solution**:
```bash
sudo apt-get install portaudio19-dev python3-pyaudio
```

### lgpio Build Fails
**Error**: `cannot find -llgpio`

**Solution**:
```bash
sudo apt-get install liblgpio-dev swig
```

### FFmpeg Not Found
**Error**: `FileNotFoundError: [Errno 2] No such file or directory: 'ffprobe'`

**Solution**:
```bash
sudo apt-get install ffmpeg
```

### GPIO Permissions
**Error**: `PermissionError: [Errno 13] Permission denied`

**Solution**: Run as root or add user to gpio group:
```bash
sudo usermod -a -G gpio $USER
sudo reboot
```

### Pi 5 PWM Not Working
**Error**: LEDs not responding or GPIO errors

**Solution**:
```bash
# Check if overlay is loaded
grep pwm /boot/firmware/config.txt

# If missing, run setup script
sudo bash setup_pi5.sh
sudo reboot

# Verify after reboot
pinctrl get 18 19
```

---

## Version Compatibility

### Python Versions
- **Minimum**: Python 3.9
- **Recommended**: Python 3.11 or newer
- **Tested**: Python 3.9, 3.11, 3.13

### Raspberry Pi OS
- **Tested**: Raspberry Pi OS Bookworm (Debian 12)
- **Should work**: Bullseye (Debian 11) or newer

### Raspberry Pi Models
- **Fully Supported**: Pi 3, Pi 4, Pi 5
- **May Work**: Pi 2 (not tested)
- **Not Supported**: Pi 1, Pi Zero (insufficient performance)

---

## Minimal Installation

For a minimal setup on a fresh Raspberry Pi:

```bash
# 1. Update system
sudo apt-get update

# 2. Install uv (fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# 3. Clone and setup
cd /path/to/heartbeat
make install

# 4. If Pi 5:
make setup-pi5
sudo reboot
```

---

## Dependency Size Estimates

### Disk Space Required
- System dependencies: ~600 MB
- Python dependencies: ~200 MB
- Project files: ~15 MB
- **Total**: ~815 MB

### Build Time (Raspberry Pi 5)
- System dependencies: ~3-5 minutes
- Python dependencies: ~2-3 minutes
- **Total**: ~5-8 minutes

---

## Notes

1. **System packages** are installed globally with `apt-get`
2. **Python packages** are installed in a virtual environment (`.venv`)
3. **uv** is used instead of pip for faster installation
4. **All Python dependencies** are declared in `pyproject.toml`
5. **System dependencies** are documented in the `Makefile`

---

*Last updated: October 2025*
