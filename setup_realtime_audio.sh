#!/bin/bash
# setup_realtime_audio.sh - Configure realtime priority for audio processing
# Allows the heartbeat controller to run with higher priority for smooth audio/LED sync

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Realtime Audio Priority Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# 1. Add user to realtime group
echo "1. Setting up realtime audio limits..."

LIMITS_FILE="/etc/security/limits.d/99-realtime-audio.conf"

sudo tee "$LIMITS_FILE" > /dev/null << 'EOF'
# Realtime priority for audio processing
# Allows audio applications to run with low latency

@audio   -  rtprio     95
@audio   -  memlock    512000
@audio   -  nice       -15
EOF

echo -e "${GREEN}✓${NC} Created: $LIMITS_FILE"

# 2. Add user to audio group if not already
if ! groups $USER | grep -q audio; then
    echo "2. Adding $USER to audio group..."
    sudo usermod -a -G audio $USER
    echo -e "${GREEN}✓${NC} Added $USER to audio group"
    NEEDS_RELOGIN=true
else
    echo -e "${GREEN}✓${NC} User $USER already in audio group"
    NEEDS_RELOGIN=false
fi

# 3. Configure CPU governor for performance
echo "3. Setting CPU governor to performance mode..."

CPU_GOVERNOR_FILE="/etc/default/cpufrequtils"

if [ ! -f "$CPU_GOVERNOR_FILE" ]; then
    sudo tee "$CPU_GOVERNOR_FILE" > /dev/null << 'EOF'
# CPU governor setting for better audio performance
GOVERNOR="performance"
EOF
    echo -e "${GREEN}✓${NC} Created: $CPU_GOVERNOR_FILE"

    # Install cpufrequtils if not present
    if ! command -v cpufreq-set &> /dev/null; then
        echo "   Installing cpufrequtils..."
        sudo apt-get install -y cpufrequtils 2>&1 | grep -v "^Reading" || true
    fi
else
    echo -e "${GREEN}✓${NC} CPU governor config already exists"
fi

# Set governor now (temporary until reboot)
if command -v cpufreq-set &> /dev/null; then
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        cpu_num=$(basename $cpu | sed 's/cpu//')
        sudo cpufreq-set -c $cpu_num -g performance 2>/dev/null || true
    done
    echo -e "${GREEN}✓${NC} Set CPU governor to performance (active now)"
else
    echo -e "${YELLOW}⚠${NC} cpufrequtils not available, CPU governor not changed"
fi

# 4. Increase PipeWire/PulseAudio priority
echo "4. Optimizing PipeWire configuration..."

# Check if we already applied the audio crackling fix
PIPEWIRE_CONF="/usr/share/pipewire/pipewire-pulse.conf"
if grep -q "pulse.min.quantum      = 512" "$PIPEWIRE_CONF"; then
    echo -e "${GREEN}✓${NC} PipeWire buffer already optimized (512/48000)"
elif grep -q "pulse.min.quantum      = 256" "$PIPEWIRE_CONF"; then
    echo -e "${GREEN}✓${NC} PipeWire buffer already optimized (256/48000)"
else
    echo -e "${YELLOW}⚠${NC} PipeWire not optimized yet"
    echo "   Run: make setup-audio-fix"
fi

# 5. Reload systemd if service file was updated
if systemctl list-unit-files | grep -q heartbeat.service; then
    echo "5. Reloading systemd daemon..."
    sudo systemctl daemon-reload
    echo -e "${GREEN}✓${NC} Systemd daemon reloaded"
fi

# Summary
echo ""
echo -e "${GREEN}✓ Realtime audio setup complete!${NC}"
echo ""

if [ "$NEEDS_RELOGIN" = true ]; then
    echo -e "${YELLOW}⚠ You need to logout and login for group changes to take effect${NC}"
    echo "   Or run: newgrp audio"
    echo ""
fi

echo "Realtime priority settings:"
echo "  • Nice level: -15 (higher priority than default)"
echo "  • CPU scheduling: FIFO (realtime)"
echo "  • RT priority: 50 (moderate realtime)"
echo "  • IO scheduling: realtime"
echo "  • Memory lock: 512MB"
echo ""
echo "To apply to running processes:"
echo "  • Service: make service-restart"
echo "  • Manual: renice -n -15 -p \$(pgrep -f heartbeat.py)"
echo ""
