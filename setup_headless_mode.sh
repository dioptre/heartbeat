#!/bin/bash
# setup_headless_mode.sh - Configure Pi to boot to console (no desktop) for better audio performance
# This saves ~10-15% CPU by disabling the graphical desktop environment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Headless Mode Configuration${NC}"
echo -e "${BLUE}========================================${NC}\n"

CURRENT_TARGET=$(systemctl get-default)

echo "Current boot target: $CURRENT_TARGET"
echo ""

if [ "$CURRENT_TARGET" = "multi-user.target" ]; then
    echo -e "${GREEN}✓ Already in headless mode (multi-user.target)${NC}"
    echo ""
    echo "Desktop processes disabled:"
    echo "  - Window manager (labwc)"
    echo "  - Panel (wf-panel-pi)"
    echo "  - File manager (pcmanfm)"
    echo "  - Terminal emulator"
    echo ""
    echo "CPU savings: ~10-15%"
    echo "Memory savings: ~200-300MB"
    echo ""
    echo "To re-enable desktop: make enable-desktop"
    echo ""
    exit 0
fi

echo -e "${YELLOW}This will disable the graphical desktop and boot to console mode.${NC}"
echo ""
echo "Benefits:"
echo "  • ~10-15% CPU reduction (no window manager, panel, file manager)"
echo "  • ~200-300MB memory savings"
echo "  • Smoother audio performance"
echo "  • Faster boot time"
echo ""
echo "You can still:"
echo "  • SSH into the Pi"
echo "  • Use the console (TTY)"
echo "  • Run the heartbeat service"
echo "  • Re-enable the desktop anytime"
echo ""

read -p "Continue? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Configuring headless mode..."

# Set default boot target to multi-user (console)
sudo systemctl set-default multi-user.target
echo -e "${GREEN}✓${NC} Set boot target to multi-user.target (console mode)"

# Stop desktop services now (optional)
echo ""
read -p "Stop desktop services now without rebooting? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Stopping desktop services..."

    # Stop the display manager/desktop session gracefully
    if systemctl is-active --quiet graphical.target; then
        sudo systemctl isolate multi-user.target
        echo -e "${GREEN}✓${NC} Switched to console mode"
    fi

    echo ""
    echo -e "${GREEN}✓ Headless mode active!${NC}"
    echo ""
    echo "Desktop has been disabled. You are now in console mode."
    echo "To restart the desktop temporarily: sudo systemctl isolate graphical.target"
else
    echo ""
    echo -e "${GREEN}✓ Headless mode configured!${NC}"
    echo ""
    echo -e "${YELLOW}⚠ Reboot required to apply changes${NC}"
    echo "Run: sudo reboot"
fi

echo ""
echo "To re-enable desktop permanently:"
echo "  make enable-desktop"
echo ""
