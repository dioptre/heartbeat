#!/bin/bash
# verify_setup.sh - Verify Raspberry Pi 4/5 setup for Heartbeat LED Controller

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Track issues
ISSUES_FOUND=0
WARNINGS_FOUND=0

# =============================================================================
# 1. DETECT RASPBERRY PI MODEL
# =============================================================================
print_header "1. Raspberry Pi Model Detection"

if [ -f /proc/device-tree/model ]; then
    PI_MODEL=$(cat /proc/device-tree/model)
    echo -e "Model: ${GREEN}${PI_MODEL}${NC}"

    if [[ "$PI_MODEL" == *"Raspberry Pi 5"* ]]; then
        PI_VERSION=5
        PWM_ALT="a3"
        PWM_DESC="alt3 (PWM0_CHAN2/PWM1_CHAN2)"
        print_success "Raspberry Pi 5 detected"
    elif [[ "$PI_MODEL" == *"Raspberry Pi 4"* ]]; then
        PI_VERSION=4
        PWM_ALT="a0"
        PWM_DESC="alt0 (PWM0/PWM1)"
        print_success "Raspberry Pi 4 detected"
    elif [[ "$PI_MODEL" == *"Raspberry Pi 3"* ]]; then
        PI_VERSION=4  # Treat Pi 3 like Pi 4 for PWM
        PWM_ALT="a0"
        PWM_DESC="alt0 (PWM0/PWM1)"
        print_success "Raspberry Pi 3 detected (using Pi 4 PWM mode)"
    else
        PI_VERSION=0
        print_error "Unknown Raspberry Pi model: $PI_MODEL"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    print_error "Cannot detect Raspberry Pi model"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    PI_VERSION=0
fi

# =============================================================================
# 2. CHECK PWM CONFIGURATION
# =============================================================================
print_header "2. PWM Configuration"

# Check config.txt for PWM overlay
CONFIG_FILE=""
if [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    CONFIG_FILE="/boot/config.txt"
fi

if [ -n "$CONFIG_FILE" ]; then
    if grep -q "dtoverlay=pwm" "$CONFIG_FILE"; then
        PWM_OVERLAY=$(grep "dtoverlay=pwm" "$CONFIG_FILE" | head -1)
        print_success "PWM overlay found: $PWM_OVERLAY"
    else
        print_error "PWM overlay NOT found in $CONFIG_FILE"
        print_info "Run: make setup-pi5 (or sudo bash setup_pi5.sh)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    print_error "Cannot find config.txt"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# =============================================================================
# 3. CHECK GPIO PWM MODE
# =============================================================================
print_header "3. GPIO PWM Mode Verification"

if command -v pinctrl &> /dev/null; then
    # Check GPIO 18
    GPIO18_STATUS=$(pinctrl get 18 2>/dev/null || echo "error")
    if [[ "$GPIO18_STATUS" == *"$PWM_ALT"* ]] && [[ "$GPIO18_STATUS" == *"PWM"* ]]; then
        print_success "GPIO 18: PWM mode active ($PWM_DESC)"
        echo "         $GPIO18_STATUS"
    else
        print_error "GPIO 18: NOT in PWM mode"
        echo "         Current: $GPIO18_STATUS"
        echo "         Expected: $PWM_ALT ($PWM_DESC)"
        print_info "A reboot may be required: sudo reboot"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check GPIO 19
    GPIO19_STATUS=$(pinctrl get 19 2>/dev/null || echo "error")
    if [[ "$GPIO19_STATUS" == *"$PWM_ALT"* ]] && [[ "$GPIO19_STATUS" == *"PWM"* ]]; then
        print_success "GPIO 19: PWM mode active ($PWM_DESC)"
        echo "         $GPIO19_STATUS"
    else
        print_error "GPIO 19: NOT in PWM mode"
        echo "         Current: $GPIO19_STATUS"
        echo "         Expected: $PWM_ALT ($PWM_DESC)"
        print_info "A reboot may be required: sudo reboot"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    print_warning "pinctrl command not found, skipping GPIO mode check"
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

# =============================================================================
# 4. CHECK GPIO PERMISSIONS
# =============================================================================
print_header "4. GPIO Permissions"

# Check if user is in gpio group
if groups | grep -q gpio; then
    print_success "User $USER is in gpio group"
else
    print_error "User $USER is NOT in gpio group"
    print_info "Run: make setup-gpio"
    print_info "Then logout/login or run: newgrp gpio"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check udev rules
if [ -f /etc/udev/rules.d/99-gpio.rules ]; then
    print_success "GPIO udev rules exist"
else
    print_warning "GPIO udev rules not found"
    print_info "Run: make setup-gpio"
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

# =============================================================================
# 5. CHECK AUDIO CONFIGURATION
# =============================================================================
print_header "5. Audio Configuration"

# Check if pactl is available
if command -v pactl &> /dev/null; then
    # Get default sink
    DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null || echo "none")

    if [ "$DEFAULT_SINK" != "none" ]; then
        print_success "Default audio sink: $DEFAULT_SINK"

        # Get sink details
        SINK_INFO=$(pactl list sinks | grep -A 20 "$DEFAULT_SINK")

        # Check volume
        VOLUME=$(echo "$SINK_INFO" | grep "Volume:" | head -1 | grep -oP '\d+%' | head -1)
        VOLUME_NUM=$(echo "$VOLUME" | tr -d '%')

        if [ -n "$VOLUME" ]; then
            echo "         Volume: $VOLUME"

            # Check if volume is too high (can cause distortion on AUX)
            if [ "$VOLUME_NUM" -gt 80 ]; then
                print_warning "Volume is high ($VOLUME) - may cause distortion on AUX output"
                print_info "Recommended: 60-75% for AUX/headphone jack"
                print_info "Adjust with: pactl set-sink-volume $DEFAULT_SINK 70%"
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            elif [ "$VOLUME_NUM" -lt 50 ]; then
                print_warning "Volume is low ($VOLUME) - audio may be too quiet"
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            else
                print_success "Volume level is good ($VOLUME)"
            fi
        fi

        # Check if muted
        MUTE_STATUS=$(echo "$SINK_INFO" | grep "Mute:" | awk '{print $2}')
        if [ "$MUTE_STATUS" = "yes" ]; then
            print_error "Audio is MUTED"
            print_info "Unmute with: pactl set-sink-mute $DEFAULT_SINK 0"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            print_success "Audio is not muted"
        fi

        # Show sink description
        SINK_DESC=$(echo "$SINK_INFO" | grep "Description:" | cut -d: -f2- | xargs)
        if [ -n "$SINK_DESC" ]; then
            echo "         Output: $SINK_DESC"
        fi
    else
        print_error "No default audio sink configured"
        print_info "Run: make setup-audio-aux (for 3.5mm AUX jack)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    print_warning "pactl not found, checking ALSA..."

    # Fall back to amixer
    if command -v amixer &> /dev/null; then
        ALSA_OUTPUT=$(amixer cget numid=3 2>/dev/null | grep ": values=" | cut -d= -f2)
        case "$ALSA_OUTPUT" in
            0) print_info "ALSA output: Auto" ;;
            1) print_success "ALSA output: 3.5mm headphone jack" ;;
            2) print_info "ALSA output: HDMI" ;;
            *) print_warning "ALSA output: Unknown ($ALSA_OUTPUT)" ;;
        esac
    else
        print_warning "No audio control tools found"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
fi

# =============================================================================
# 6. CHECK PYTHON ENVIRONMENT
# =============================================================================
print_header "6. Python Environment"

if [ -d .venv ]; then
    print_success "Virtual environment exists (.venv)"

    # Check if Python is working
    if [ -f .venv/bin/python3 ]; then
        PYTHON_VERSION=$(.venv/bin/python3 --version 2>&1)
        print_success "Python: $PYTHON_VERSION"

        # Check key dependencies
        print_info "Checking Python packages..."

        PACKAGES=("numpy" "pydub" "pyaudio" "RPi.GPIO")
        for pkg in "${PACKAGES[@]}"; do
            if .venv/bin/python3 -c "import $pkg" 2>/dev/null; then
                print_success "  $pkg installed"
            else
                print_error "  $pkg NOT installed"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        done
    else
        print_error "Python3 not found in virtual environment"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    print_error "Virtual environment not found (.venv)"
    print_info "Run: make install"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# =============================================================================
# 7. CHECK SYSTEM RESOURCES
# =============================================================================
print_header "7. System Resources"

# CPU temperature
if command -v vcgencmd &> /dev/null; then
    TEMP=$(vcgencmd measure_temp | grep -oP '\d+\.\d+')
    TEMP_INT=${TEMP%.*}

    if [ "$TEMP_INT" -lt 70 ]; then
        print_success "CPU Temperature: ${TEMP}°C (good)"
    elif [ "$TEMP_INT" -lt 80 ]; then
        print_warning "CPU Temperature: ${TEMP}°C (warm)"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    else
        print_error "CPU Temperature: ${TEMP}°C (HOT - throttling likely)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check throttling
    THROTTLED=$(vcgencmd get_throttled)
    if [[ "$THROTTLED" == *"0x0"* ]]; then
        print_success "No throttling detected"
    else
        print_warning "Throttling detected: $THROTTLED"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
else
    print_warning "vcgencmd not available"
fi

# Memory
MEM_INFO=$(free -h | grep Mem)
MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
MEM_AVAIL=$(echo "$MEM_INFO" | awk '{print $7}')
print_success "Memory: $MEM_AVAIL available of $MEM_TOTAL total"

# =============================================================================
# 8. CHECK HEARTBEAT FILES
# =============================================================================
print_header "8. Project Files"

if [ -f src/heartbeat.py ]; then
    print_success "Main script found: src/heartbeat.py"
else
    print_error "Main script NOT found: src/heartbeat.py"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ -f heartbeat.mp3 ]; then
    MP3_SIZE=$(du -h heartbeat.mp3 | awk '{print $1}')
    print_success "Audio file found: heartbeat.mp3 ($MP3_SIZE)"
else
    print_warning "Audio file NOT found: heartbeat.mp3"
    print_info "You'll need an MP3 file to run the controller"
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
print_header "Verification Summary"

if [ $ISSUES_FOUND -eq 0 ]; then
    print_success "All critical checks passed!"

    if [ $WARNINGS_FOUND -eq 0 ]; then
        echo -e "\n${GREEN}✓ System is ready to run!${NC}\n"
        echo "Next steps:"
        echo "  make test      - Test LED hardware"
        echo "  make run       - Run with heartbeat.mp3 (once)"
        echo "  make loop      - Run with heartbeat.mp3 (forever)"
    else
        echo -e "\n${YELLOW}⚠ System is functional but has $WARNINGS_FOUND warning(s)${NC}\n"
        echo "You can still run the controller, but consider fixing the warnings above."
    fi
else
    echo -e "\n${RED}✗ Found $ISSUES_FOUND critical issue(s) and $WARNINGS_FOUND warning(s)${NC}\n"
    echo "Please fix the issues above before running the controller."

    # Provide quick fix suggestions
    if groups | grep -qv gpio; then
        echo -e "\n${BLUE}Quick fix for GPIO permissions:${NC}"
        echo "  make setup-gpio && newgrp gpio"
    fi

    if ! [ -d .venv ]; then
        echo -e "\n${BLUE}Quick fix for Python environment:${NC}"
        echo "  make install"
    fi

    echo ""
    exit 1
fi

exit 0
