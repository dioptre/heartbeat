.PHONY: help install install-system install-python setup-pi5 test clean

# Default target
help:
	@echo "Heartbeat Audio-Reactive LED Controller - Setup Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  make install         - Install all dependencies (system + Python)"
	@echo "  make install-system  - Install system dependencies only"
	@echo "  make install-python  - Install Python dependencies only"
	@echo "  make setup-pi5       - Setup Raspberry Pi 5 PWM configuration"
	@echo "  make test           - Run hardware test pattern"
	@echo "  make run            - Run with heartbeat.mp3"
	@echo "  make clean          - Clean up Python cache and build files"
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
