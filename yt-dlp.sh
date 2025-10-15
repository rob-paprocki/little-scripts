#!/bin/bash

# This script performs a comprehensive installation of yt-dlp and all its
# dependencies on Debian 13, and sets up an automatic weekly update cron job.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. Installation ---
echo "--- Starting yt-dlp Installation ---"

# Update Package Lists
echo "Updating package lists... 📦"
apt-get update

# Install System Dependencies
echo "Installing system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    ca-certificates \
    aria2 \
    atomicparsley \
    build-essential \
    libcurl4-openssl-dev

# Upgrade Pip
echo "Upgrading pip to the latest version... 🐍"
python3 -m pip install --upgrade pip

# Install Python Dependencies
echo "Installing yt-dlp and all requested Python modules..."
pip install \
    yt-dlp \
    mutagen \
    certifi \
    brotli \
    websockets \
    requests \
    curl_cffi

echo "✅ Installation complete."

# --- 2. Cron Job for Automatic Updates ---
echo ""
echo "--- Setting up Automatic Weekly Updates ---"

# Define the full path to python3 to ensure cron can find it
PYTHON_PATH=$(which python3)

# Define the full update command
UPDATE_COMMAND="$PYTHON_PATH -m pip install --upgrade yt-dlp mutagen certifi brotli websockets requests curl_cffi"

# Create a cron file in /etc/cron.d/
CRON_FILE="/etc/cron.d/yt-dlp-update"
echo "Creating cron job file at $CRON_FILE"

# The cron job will run as root every Sunday at 3:30 AM.
# Output is redirected to a log file for easy debugging.
# 30 3 * * 0 = At 03:30 on Sunday
(echo "# Automatic weekly update for yt-dlp and its dependencies."
 echo "30 3 * * 0 root $UPDATE_COMMAND > /var/log/yt-dlp-update.log 2>&1") > "$CRON_FILE"

# Set the correct permissions for the cron file
chmod 0644 "$CRON_FILE"

echo "✅ Cron job created successfully."
echo "   - It will run every Sunday at 3:30 AM."
echo "   - To change the schedule, edit the file: $CRON_FILE"
echo "   - Update logs will be available at: /var/log/yt-dlp-update.log"

# --- 3. Final Verification ---
echo ""
echo "--- Verifying Installation ---"
yt-dlp --version
echo ""
echo "All steps completed successfully! Your yt-dlp setup is ready and will update automatically."
