#!/bin/bash
# Setup script for Raspberry Pi 5 PWM configuration
# Run with: sudo bash setup_pi5.sh

echo "======================================"
echo "  Raspberry Pi 5 PWM Setup"
echo "======================================"
echo ""

# Check if running on Pi 5
if ! grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
    echo "⚠️  This script is for Raspberry Pi 5 only"
    echo "   Your Pi version does not require this setup"
    exit 0
fi

echo "✓ Raspberry Pi 5 detected"
echo ""

# Check if config already has PWM enabled
if grep -q "dtoverlay=pwm" /boot/firmware/config.txt 2>/dev/null; then
    echo "✓ PWM already configured in /boot/firmware/config.txt"
    echo ""
    exit 0
fi

# Backup config file
echo "📋 Backing up config.txt..."
cp /boot/firmware/config.txt /boot/firmware/config.txt.backup
echo "✓ Backup saved to /boot/firmware/config.txt.backup"
echo ""

# Add PWM overlay
echo "🔧 Adding PWM configuration..."
echo "" >> /boot/firmware/config.txt
echo "# Hardware PWM for heartbeat LED controller" >> /boot/firmware/config.txt
echo "dtoverlay=pwm-2chan" >> /boot/firmware/config.txt
echo "✓ Configuration added"
echo ""

echo "======================================"
echo "  Setup Complete!"
echo "======================================"
echo ""
echo "⚠️  IMPORTANT: Install Python dependencies"
echo ""
echo "Install Pi 5 compatible GPIO library:"
echo "  pip3 install rpi-lgpio"
echo ""
echo "Install audio libraries:"
echo "  pip3 install pydub numpy"
echo "  sudo apt-get install python3-pyaudio ffmpeg"
echo ""
echo "⚠️  REBOOT REQUIRED"
echo ""
echo "Please reboot your Raspberry Pi for PWM changes to take effect:"
echo "  sudo reboot"
echo ""
echo "After rebooting, run your heartbeat LED controller:"
echo "  python3 src/heartbeat.py heartbeat.mp3"
echo ""
