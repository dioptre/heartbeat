#!/bin/bash
# enable_desktop_mode.sh - Re-enable graphical desktop environment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Enable Desktop Mode${NC}"
echo -e "${BLUE}========================================${NC}\n"

CURRENT_TARGET=$(systemctl get-default)

echo "Current boot target: $CURRENT_TARGET"
echo ""

if [ "$CURRENT_TARGET" = "graphical.target" ]; then
    echo -e "${GREEN}✓ Desktop mode already enabled${NC}"

    if ! systemctl is-active --quiet graphical.target; then
        echo ""
        echo "Desktop is enabled but not currently running."
        read -p "Start desktop now? (y/n): " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl isolate graphical.target
            echo -e "${GREEN}✓${NC} Desktop started"
        fi
    else
        echo "Desktop is currently running."
    fi

    echo ""
    exit 0
fi

echo "Enabling desktop mode..."

# Set default boot target to graphical
sudo systemctl set-default graphical.target
echo -e "${GREEN}✓${NC} Set boot target to graphical.target (desktop mode)"

echo ""
read -p "Start desktop now without rebooting? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting desktop..."
    sudo systemctl isolate graphical.target
    echo -e "${GREEN}✓${NC} Desktop started"
else
    echo ""
    echo -e "${YELLOW}⚠ Reboot required to start desktop${NC}"
    echo "Run: sudo reboot"
fi

echo ""
echo -e "${GREEN}✓ Desktop mode enabled!${NC}"
echo ""
