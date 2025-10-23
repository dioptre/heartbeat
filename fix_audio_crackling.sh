#!/bin/bash
# fix_audio_crackling.sh - Fix audio crackling/distortion on Raspberry Pi
# Increases PipeWire audio buffer to reduce CPU-related distortion
# Based on: https://www.ifixit.com/Guide/Ubuntu+Linux+Fixing+Crackling-Glitching+Audio/187324

set -e

CONFIG_FILE="/usr/share/pipewire/pipewire-pulse.conf"
BACKUP_FILE="${CONFIG_FILE}.backup"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PipeWire Audio Crackling Fix${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}✗ Do not run as root/sudo${NC}"
    echo "This script will use sudo only when needed"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ PipeWire config not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Parse quantum value argument (default 256, can use 512 for more severe issues)
QUANTUM=${1:-256}

if [[ ! "$QUANTUM" =~ ^(128|256|512|1024)$ ]]; then
    echo -e "${RED}✗ Invalid quantum value: $QUANTUM${NC}"
    echo "Valid values: 128 (default), 256 (recommended), 512, 1024"
    exit 1
fi

echo -e "${YELLOW}Target buffer size:${NC} $QUANTUM/48000 (~$(awk "BEGIN {printf \"%.1f\", $QUANTUM/48000*1000}")ms latency)"
echo ""

# Backup original config if not already backed up
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Creating backup..."
    sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓${NC} Backup created: $BACKUP_FILE"
else
    echo -e "${GREEN}✓${NC} Backup already exists: $BACKUP_FILE"
fi

# Check current configuration
CURRENT_LINE=$(grep -n "^\s*#\?pulse\.min\.quantum" "$CONFIG_FILE" | head -1)

if [ -z "$CURRENT_LINE" ]; then
    echo -e "${RED}✗ Could not find pulse.min.quantum setting${NC}"
    exit 1
fi

LINE_NUM=$(echo "$CURRENT_LINE" | cut -d: -f1)
LINE_TEXT=$(echo "$CURRENT_LINE" | cut -d: -f2-)

echo "Current setting (line $LINE_NUM):"
echo "  $LINE_TEXT"
echo ""

# Modify the configuration
echo "Applying fix..."
sudo sed -i "${LINE_NUM}s|.*pulse\.min\.quantum.*|    pulse.min.quantum      = $QUANTUM/48000     # $(awk "BEGIN {printf \"%.1f\", $QUANTUM/48000*1000}")ms|" "$CONFIG_FILE"

# Verify the change
NEW_LINE=$(sed -n "${LINE_NUM}p" "$CONFIG_FILE")
echo "New setting:"
echo "  $NEW_LINE"
echo ""

# Restart PipeWire services
echo "Restarting PipeWire services..."
systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
sleep 1

# Check if services are running
if systemctl --user is-active --quiet pipewire && systemctl --user is-active --quiet pipewire-pulse; then
    echo -e "${GREEN}✓${NC} PipeWire services restarted successfully"
else
    echo -e "${YELLOW}⚠${NC} PipeWire services may need manual restart"
    echo "Try: systemctl --user restart pipewire pipewire-pulse wireplumber"
fi

echo ""
echo -e "${GREEN}✓ Audio fix applied!${NC}"
echo ""
echo "Test your audio now. If crackling persists:"
echo "  - Try a larger buffer: ./fix_audio_crackling.sh 512"
echo "  - Or even larger: ./fix_audio_crackling.sh 1024"
echo ""
echo "To restore original settings:"
echo "  sudo cp $BACKUP_FILE $CONFIG_FILE"
echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
echo ""
