.PHONY: help install install-system install-python setup-pi5 setup-gpio setup-audio-aux setup-audio-fix setup-realtime setup-cpu-performance setup-headless enable-desktop verify test run loop clean stop service-install service-start service-stop service-status service-enable service-disable service-logs service-uninstall

# Use bash as the shell
SHELL := /bin/bash

# Default target
help:
	@echo "Heartbeat Audio-Reactive LED Controller - Setup Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  make install         - Install all dependencies (system + Python)"
	@echo "  make install-system  - Install system dependencies only"
	@echo "  make install-python  - Install Python dependencies only"
	@echo "  make setup-pi5       - Setup Raspberry Pi 5 PWM configuration"
	@echo "  make setup-gpio      - Setup GPIO permissions (run without sudo)"
	@echo "  make setup-audio-aux - Set audio output to 3.5mm AUX jack (Pi 4)"
	@echo "  make setup-audio-fix - Fix audio crackling/distortion (PipeWire)"
	@echo "  make setup-realtime  - Setup realtime priority for smooth audio"
	@echo "  make setup-cpu-performance - Set CPU to performance mode"
	@echo "  make setup-headless  - Disable desktop (saves ~10-15% CPU)"
	@echo "  make enable-desktop  - Re-enable graphical desktop"
	@echo "  make verify          - Verify system configuration (Pi 4/Pi 5)"
	@echo "  make test           - Run hardware test pattern"
	@echo "  make run            - Run with heartbeat.mp3 (plays once)"
	@echo "  make loop           - Run with heartbeat.mp3 (repeats forever)"
	@echo "  make stop           - Stop running heartbeat"
	@echo "  make clean          - Clean up Python cache and build files"
	@echo ""
	@echo "Systemd Service Commands:"
	@echo "  make service-install - Install systemd service"
	@echo "  make service-enable  - Enable service to start on boot"
	@echo "  make service-start   - Start the service now"
	@echo "  make service-stop    - Stop the service"
	@echo "  make service-status  - Check service status"
	@echo "  make service-logs    - View service logs"
	@echo "  make service-disable - Disable auto-start on boot"
	@echo "  make service-uninstall - Uninstall the service"
	@echo ""

# =============================================================================
# SYSTEM DEPENDENCIES
# =============================================================================
# These are the system packages required for the project to work
# - Build tools: make, build-essential, swig
# - Python build deps: libssl-dev, zlib1g-dev, libbz2-dev, etc.
# - Audio libraries: python3-pyaudio, ffmpeg, portaudio19-dev
# - GPIO library: liblgpio-dev (for Raspberry Pi GPIO access)
# =============================================================================

install-system:
	@echo "Installing system dependencies..."
	sudo apt-get update
	sudo apt-get install -y \
		make \
		build-essential \
		swig \
		libssl-dev \
		zlib1g-dev \
		libbz2-dev \
		libreadline-dev \
		libsqlite3-dev \
		wget \
		curl \
		llvm \
		libncursesw5-dev \
		xz-utils \
		tk-dev \
		libxml2-dev \
		libxmlsec1-dev \
		libffi-dev \
		liblzma-dev \
		python3-pyaudio \
		ffmpeg \
		portaudio19-dev \
		libasound2-dev \
		libjack-jackd2-dev \
		liblgpio-dev
	@echo "✓ System dependencies installed"

# =============================================================================
# PYTHON DEPENDENCIES
# =============================================================================
# All Python dependencies are managed in pyproject.toml:
# - numpy: Numerical processing for audio analysis
# - pydub: Audio file processing and MP3 loading
# - pyaudio: Audio playback
# - rpi-lgpio: Raspberry Pi GPIO control (Pi 4 & Pi 5 compatible)
# =============================================================================

install-python:
	@echo "Installing Python dependencies from pyproject.toml..."
	@if [ ! -d ".venv" ]; then \
		echo "Creating virtual environment..."; \
		~/.local/bin/uv venv; \
	fi
	@echo "Installing dependencies with uv..."
	~/.local/bin/uv pip install -e .
	@echo "✓ Python dependencies installed"

# =============================================================================
# FULL INSTALLATION
# =============================================================================

install: install-system install-python
	@echo ""
	@echo "✓ All dependencies installed successfully!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. If on Raspberry Pi 5: make setup-pi5"
	@echo "  2. Activate venv: source .venv/bin/activate"
	@echo "  3. Run test: make test"
	@echo "  4. Run with audio: make run"
	@echo ""

# =============================================================================
# RASPBERRY PI 5 SETUP
# =============================================================================
# Pi 5 requires PWM overlay configuration
# This adds 'dtoverlay=pwm-2chan' to /boot/firmware/config.txt
# =============================================================================

setup-pi5:
	@echo "Setting up Raspberry Pi 5 PWM configuration..."
	sudo bash setup_pi5.sh
	@echo ""
	@echo "⚠️  REBOOT REQUIRED"
	@echo "Run: sudo reboot"
	@echo ""

# =============================================================================
# AUDIO OUTPUT SETUP (Pi 4)
# =============================================================================
# Sets audio output to 3.5mm AUX jack using amixer (ALSA)
# This is the fastest method with no dependencies on PulseAudio/PipeWire
# Values: 0=auto, 1=headphone jack, 2=HDMI
# =============================================================================

setup-audio-aux:
	@echo "Setting audio output to 3.5mm AUX jack..."
	amixer cset numid=3 1
	@echo "✓ Audio output set to headphone jack"
	@echo ""
	@echo "Test with: speaker-test -t sine -f 440 -l 1"
	@echo ""

# =============================================================================
# AUDIO CRACKLING/DISTORTION FIX
# =============================================================================
# Fixes audio crackling by increasing PipeWire buffer size
# Default: 256/48000 (~5.3ms latency)
# For severe issues: make setup-audio-fix-512 (512/48000 = ~10.6ms)
# Based on: https://www.ifixit.com/Guide/Ubuntu+Linux+Fixing+Crackling-Glitching+Audio/187324
# =============================================================================

setup-audio-fix:
	@echo "Fixing audio crackling (buffer: 256/48000)..."
	@bash fix_audio_crackling.sh 256
	@echo ""
	@echo "If crackling persists, try: make setup-audio-fix-512"
	@echo ""

setup-audio-fix-512:
	@echo "Fixing audio crackling (buffer: 512/48000)..."
	@bash fix_audio_crackling.sh 512
	@echo ""

setup-audio-restore:
	@echo "Restoring original PipeWire configuration..."
	@sudo cp /usr/share/pipewire/pipewire-pulse.conf.backup /usr/share/pipewire/pipewire-pulse.conf
	@systemctl --user restart pipewire pipewire-pulse wireplumber
	@echo "✓ Original configuration restored"
	@echo ""

# =============================================================================
# REALTIME PRIORITY SETUP
# =============================================================================
# Configures system for realtime audio processing with low latency
# Sets up: realtime limits, CPU governor, nice priority
# =============================================================================

setup-realtime:
	@echo "Setting up realtime audio priority..."
	@bash setup_realtime_audio.sh
	@echo ""
	@echo "✓ Realtime setup complete"
	@echo "If service is running: make service-restart"
	@echo "Or apply to running process: sudo renice -n -15 -p \$$(pgrep -f heartbeat.py)"
	@echo ""

setup-cpu-performance:
	@echo "Setting CPU governor to performance mode..."
	@bash set_cpu_performance.sh
	@echo "✓ CPU set to performance mode (reduces audio crackling)"
	@echo ""

# =============================================================================
# HEADLESS MODE (NO DESKTOP)
# =============================================================================
# Disables graphical desktop environment to save CPU and memory
# Saves: ~10-15% CPU, ~200-300MB RAM
# You can still SSH in and run the heartbeat service
# =============================================================================

setup-headless:
	@echo "Configuring headless mode (no desktop)..."
	@bash setup_headless_mode.sh

enable-desktop:
	@echo "Re-enabling desktop mode..."
	@bash enable_desktop_mode.sh

# =============================================================================
# GPIO PERMISSIONS SETUP
# =============================================================================
# Allows running GPIO without sudo (fixes Bluetooth audio issues)
# This adds the current user to the gpio group and creates udev rules
# =============================================================================

setup-gpio:
	@echo "Setting up GPIO permissions for user: $(USER)"
	@echo ""
	@echo "1. Adding $(USER) to gpio group..."
	sudo usermod -a -G gpio $(USER)
	@echo ""
	@echo "2. Creating udev rules for GPIO access..."
	@sudo bash -c 'cat > /etc/udev/rules.d/99-gpio.rules << EOF\n\
# Allow gpio group to access GPIO without sudo\n\
SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c '\''chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio; chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio; chown -R root:gpio /sys/devices/platform/soc/*.gpio/gpiochip* && chmod -R 770 /sys/devices/platform/soc/*.gpio/gpiochip*'\''"\n\
SUBSYSTEM=="gpiomem", GROUP="gpio", MODE="0660"\n\
KERNEL=="gpiomem", GROUP="gpio", MODE="0660"\n\
EOF'
	@echo ""
	@echo "3. Reloading udev rules..."
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	@echo ""
	@echo "✓ GPIO permissions configured!"
	@echo ""
	@echo "⚠️  LOGOUT REQUIRED"
	@echo "You need to logout and login again for group changes to take effect"
	@echo "Or run: newgrp gpio"
	@echo ""

# =============================================================================
# VERIFICATION
# =============================================================================
# Comprehensive system check for Pi 4 and Pi 5
# Verifies: Pi model, PWM config, GPIO permissions, audio, Python packages
# =============================================================================

verify:
	@echo "Verifying system configuration..."
	@bash verify_setup.sh

# =============================================================================
# RUNNING THE PROJECT
# =============================================================================

test:
	@echo "Running hardware test pattern..."
	source .venv/bin/activate && python3 src/heartbeat.py test

run:
	@if [ ! -f "heartbeat.mp3" ]; then \
		echo "❌ Error: heartbeat.mp3 not found"; \
		exit 1; \
	fi
	@echo "Applying audio optimizations..."
	@bash set_cpu_performance.sh 2>/dev/null || echo "⚠ CPU performance mode not set (may need sudo)"
	@if pgrep -x "python3" > /dev/null 2>&1; then \
		sudo renice -n -15 -p $$(pgrep -f heartbeat.py) 2>/dev/null || true; \
	fi
	@echo "Starting heartbeat (single play)..."
	source .venv/bin/activate && python3 src/heartbeat.py heartbeat.mp3

loop:
	@if [ ! -f "heartbeat.mp3" ]; then \
		echo "❌ Error: heartbeat.mp3 not found"; \
		exit 1; \
	fi
	@echo "Applying audio optimizations..."
	@bash set_cpu_performance.sh 2>/dev/null || echo "⚠ CPU performance mode not set (may need sudo)"
	@echo ""
	@echo "Starting heartbeat in loop mode (repeats forever)..."
	@echo "Press Ctrl+C to stop, or run 'make stop' from another terminal"
	@echo ""
	@(source .venv/bin/activate && python3 src/heartbeat.py heartbeat.mp3 --loop) & \
	sleep 2 && \
	if pgrep -f "heartbeat.py" > /dev/null; then \
		sudo renice -n -15 -p $$(pgrep -f heartbeat.py) 2>/dev/null && echo "✓ Applied nice priority -15" || echo "⚠ Could not set nice priority (may need sudo)"; \
	fi; \
	wait

stop:
	@echo "Stopping heartbeat..."
	@pkill -f "heartbeat.py" && echo "✓ Stopped" || echo "No heartbeat process found"

# =============================================================================
# CLEANUP
# =============================================================================

clean:
	@echo "Cleaning up..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "build" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Cleaned up"

# =============================================================================
# SYSTEMD SERVICE MANAGEMENT
# =============================================================================

service-install:
	@echo "Installing heartbeat systemd service..."
	sudo cp heartbeat.service /etc/systemd/system/
	sudo systemctl daemon-reload
	@echo "✓ Service installed"
	@echo ""
	@echo "Next steps:"
	@echo "  make service-enable  - Enable auto-start on boot"
	@echo "  make service-start   - Start the service now"
	@echo ""

service-enable:
	@echo "Enabling heartbeat service to start on boot..."
	sudo systemctl enable heartbeat.service
	@echo "✓ Service enabled"
	@echo "Heartbeat will start automatically on next boot"

service-disable:
	@echo "Disabling heartbeat service auto-start..."
	sudo systemctl disable heartbeat.service
	@echo "✓ Service disabled"

service-start:
	@echo "Starting heartbeat service..."
	sudo systemctl start heartbeat.service
	@echo "✓ Service started"
	@echo "Check status with: make service-status"
	@echo "View logs with: make service-logs"

service-stop:
	@echo "Stopping heartbeat service..."
	sudo systemctl stop heartbeat.service
	@echo "✓ Service stopped"

service-restart:
	@echo "Restarting heartbeat service..."
	sudo systemctl restart heartbeat.service
	@echo "✓ Service restarted"

service-status:
	@sudo systemctl status heartbeat.service --no-pager

service-logs:
	@echo "Showing heartbeat service logs (Ctrl+C to exit)..."
	sudo journalctl -u heartbeat.service -f

service-logs-recent:
	@echo "Showing recent heartbeat service logs..."
	sudo journalctl -u heartbeat.service -n 50 --no-pager

service-uninstall:
	@echo "Uninstalling heartbeat service..."
	@sudo systemctl stop heartbeat.service 2>/dev/null || true
	@sudo systemctl disable heartbeat.service 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/heartbeat.service
	@sudo systemctl daemon-reload
	@echo "✓ Service uninstalled"
