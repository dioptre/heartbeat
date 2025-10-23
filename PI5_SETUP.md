# Raspberry Pi 5 Setup Guide

## Quick Start for Pi 5 Users

Your heartbeat LED controller code is **already compatible** with Raspberry Pi 5! The code automatically detects which Pi version you're using and adjusts accordingly.

## Installation (Pi 5 Required)

**Important:** Raspberry Pi 5 requires `rpi-lgpio` instead of the original `RPi.GPIO` library:

```bash
# Install Pi 5 compatible GPIO library
pip3 install rpi-lgpio

# Install other dependencies
pip3 install pydub numpy
sudo apt-get install python3-pyaudio ffmpeg
```

The `rpi-lgpio` library is a drop-in replacement that provides the same API as `RPi.GPIO` but works with Pi 5's new RP1 chip.

## One-Time Setup (Pi 5 Only)

Raspberry Pi 5 requires a one-time configuration to enable hardware PWM:

```bash
# Run the setup script
sudo bash setup_pi5.sh

# Reboot for changes to take effect
sudo reboot
```

That's it! After rebooting, your LED controller will work normally.

## Manual Setup (Alternative)

If you prefer to configure manually:

1. Edit the config file:
   ```bash
   sudo nano /boot/firmware/config.txt
   ```

2. Add this line at the end:
   ```
   dtoverlay=pwm-2chan
   ```

3. Save (Ctrl+X, Y, Enter) and reboot:
   ```bash
   sudo reboot
   ```

## What the Code Does Automatically

Your Python script ([src/heartbeat.py](src/heartbeat.py)) now:

1. ✅ **Detects Pi version** at startup
2. ✅ **Uses rpi-lgpio** which automatically handles PWM channel differences:
   - Pi 4: PWM channels 0 and 1
   - Pi 5: PWM channels 2 and 3
3. ✅ **Verifies Pi 5 config** using `pinctrl` to check GPIO alt functions
4. ✅ **Warns you** if Pi 5 config is missing
5. ✅ **Uses same GPIO pins** (18 and 19) on both versions

## Verification

### Using the Python Script

When you run the program, you'll see:

```
============================================================
  Heartbeat Audio-Reactive LED Controller
  Raspberry Pi 5 + 2x 70W COB LEDs
============================================================
🔍 Detected: Raspberry Pi 5
✓ Pi 5 PWM verified: GPIO 18 and 19 configured for PWM (alt3)
✓ GPIO initialized: LED1=GPIO18, LED2=GPIO19
✓ PWM frequency: 10000Hz
✓ PWM channels: 2 (GPIO18), 3 (GPIO19)
```

### Using pinctrl Command

You can manually verify PWM configuration with:

```bash
pinctrl get 18 19
```

**Expected output:**
```
18: a3    pd | hi // GPIO18 = PWM0_CHAN2
19: a3    pd | hi // GPIO19 = PWM1_CHAN2
```

The `a3` indicates **alt3** (alternate function 3), which is the PWM mode on Pi 5.

**What it means:**
- `18:` - GPIO pin number
- `a3` - Alternate function 3 (PWM on RP1 chip)
- `pd` - Pull-down resistor enabled
- `hi` or `lo` - Current pin state (high/low voltage)
- `PWM0_CHAN2` - PWM channel 2 on controller 0

## Technical Details

### Why Pi 5 is Different

Raspberry Pi 5 uses a new RP1 I/O chip with different PWM architecture:

| Feature | Pi 4 & Earlier | Pi 5 |
|---------|---------------|------|
| **I/O Chip** | BCM2711 | RP1 |
| **GPIO 18 PWM** | Alt5 (PWM0) | Alt3 (PWM0_CHAN2) |
| **GPIO 19 PWM** | Alt5 (PWM1) | Alt3 (PWM1_CHAN2) |
| **PWM channel (GPIO 18)** | 0 | 2 |
| **PWM channel (GPIO 19)** | 1 | 3 |
| **Config required** | No | Yes (`dtoverlay=pwm-2chan`) |
| **Config location** | `/boot/config.txt` | `/boot/firmware/config.txt` |

**Key difference:** The RP1 chip on Pi 5 moved PWM from **alt5** to **alt3**. This is why `pinctrl get 18` shows `a3` (alt3) instead of `a5`.

**Function mapping on GPIO 18:**
```bash
# Pi 4 (BCM2711):
pinctrl -c bcm2711 funcs 18
18, GPIO18, PCM_CLK, SD10, DPI_D14, SPI6_CE0_N, SPI1_CE0_N, PWM0_0
                                                              ^^^^^^ alt5

# Pi 5 (RP1):
pinctrl funcs 18
18, GPIO18, SPI1_CE0, DPI_D14, I2S0_SCLK, PWM0_CHAN2, I2S1_SCLK, ...
                                           ^^^^^^^^^^ alt3
```

**Compatibility translation:** The `pwm-2chan` overlay uses `brcm,function=2` which the RP1 driver translates to alt3 for backward compatibility with older Pi overlays. This is why you don't need a Pi 5-specific overlay.

### GPIO Library: rpi-lgpio vs RPi.GPIO

**Why rpi-lgpio?**

The original `RPi.GPIO` library does not work on Raspberry Pi 5 because:
- Pi 5 uses a new RP1 I/O chip (not BCM2711)
- Memory-mapped GPIO access changed completely
- Direct register access no longer works

**rpi-lgpio solution:**
- Drop-in replacement with same API as RPi.GPIO
- Uses `lgpio` library underneath
- Works with RP1 chip on Pi 5
- Also works on Pi 4, 3, Zero, etc.
- No code changes needed - just install it instead

**Installation:**
```bash
# Remove old library (if present)
sudo apt remove python3-rpi.gpio

# Install Pi 5 compatible version
pip3 install rpi-lgpio
```

Your code uses `import RPi.GPIO as GPIO` which works with `rpi-lgpio` installed!

### Alternative GPIO Pins (Optional)

If you need to use different pins, Pi 5 also supports:
- GPIO 12 and 13 (using PWM channels 0 and 1)
- Requires different overlay: `dtoverlay=pwm-2chan,pin=12,func=4,pin2=13,func2=4`

But the default GPIO 18/19 setup works great and matches the circuit schematic!

## Troubleshooting

### LEDs don't work on Pi 5

1. Check if PWM is configured:
   ```bash
   grep pwm /boot/firmware/config.txt
   ```
   Should show: `dtoverlay=pwm-2chan`

2. Verify you rebooted after adding the overlay

3. Check the Python output for warnings

### "PWM not configured" warning

If you see this warning, run:
```bash
sudo bash setup_pi5.sh
sudo reboot
```

### Still not working?

Check the main [README.md](README.md) troubleshooting section for hardware issues (wiring, MOSFETs, power supply, etc.)

## Summary

- ✅ **Hardware**: Same circuit, same GPIO pins (18, 19)
- ✅ **Software**: Automatically adapts to Pi 4 or Pi 5
- ✅ **Setup**: Run `setup_pi5.sh` once on Pi 5
- ✅ **Usage**: Identical on both Pi versions

Your code is now future-proof for both Raspberry Pi 4 and 5! 🎉
