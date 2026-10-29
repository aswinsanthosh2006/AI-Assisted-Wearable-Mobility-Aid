#!/bin/bash
# setup_env.sh — Bootstrap the Python virtual environment for
# AI-Assisted Wearable Mobility Aid on Raspberry Pi OS Bookworm (32-bit).
#
# Usage:
#   chmod +x scripts/setup_env.sh
#   ./scripts/setup_env.sh
#
# Run this script from the project root directory.

set -e

VENV_NAME="blind_env"
REQUIREMENTS="requirements.txt"

echo "======================================================"
echo " AI Blind Assist — Environment Setup"
echo "======================================================"

# Check we are on a Raspberry Pi
if ! uname -m | grep -qE "armv7l|aarch64"; then
    echo "WARNING: This script is intended for Raspberry Pi (ARM)."
    echo "         Continuing anyway — some packages may not install."
fi

# Install system packages
echo ""
echo "[1/4] Installing system packages..."
sudo apt-get update -q
sudo apt-get install -y \
    python3-dev \
    libatlas-base-dev \
    espeak-ng \
    alsa-utils \
    python3-rpi.gpio \
    v4l-utils

# Create virtual environment
echo ""
echo "[2/4] Creating virtual environment: ${VENV_NAME}"
python3 -m venv "${VENV_NAME}"
source "${VENV_NAME}/bin/activate"

# Upgrade pip
echo ""
echo "[3/4] Upgrading pip..."
pip install --upgrade pip --quiet

# Install dependencies
echo ""
echo "[4/4] Installing Python dependencies from ${REQUIREMENTS}..."
pip install -r "${REQUIREMENTS}"

echo ""
echo "======================================================"
echo " Setup complete."
echo ""
echo " To activate the environment:"
echo "   source ${VENV_NAME}/bin/activate"
echo ""
echo " To run the application:"
echo "   python3 webcam_detect.py"
echo ""
echo " Remember to download detect.tflite first:"
echo "   See docs/software-setup.md Step 5"
echo "======================================================"
