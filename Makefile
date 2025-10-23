.PHONY: help install install-system install-python setup-pi5 setup-gpio test run loop clean stop service-install service-start service-stop service-status service-enable service-disable service-logs service-uninstall

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
	source .venv/bin/activate && python3 src/heartbeat.py heartbeat.mp3

loop:
	@if [ ! -f "heartbeat.mp3" ]; then \
		echo "❌ Error: heartbeat.mp3 not found"; \
		exit 1; \
	fi
	@echo "Starting heartbeat in loop mode (repeats forever)..."
	@echo "Press Ctrl+C to stop, or run 'make stop' from another terminal"
	source .venv/bin/activate && python3 src/heartbeat.py heartbeat.mp3 --loop

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
