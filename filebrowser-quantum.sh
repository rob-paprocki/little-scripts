#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# set -e

# --- Configuration ---
INSTALL_DIR="/opt/filebrowser"
BINARY_PATH="/usr/local/bin/filebrowser"
REPO_URL="https://github.com/gtsteffaniak/filebrowser.git"
LOG_FILE="/var/log/filebrowser_update.log"

# --- Functions ---

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- Main Script ---

# 1. Install Dependencies
log "Updating package lists and installing dependencies..."
apt-get update
apt-get install -y golang git

# 2. Clone or Update the Repository
if [ -d "$INSTALL_DIR" ]; then
    log "Filebrowser directory exists. Pulling latest changes."
    cd "$INSTALL_DIR"
    git pull
else
    log "Cloning Filebrowser repository."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# 3. Build the Binary
log "Preparing Go module..."
# Initialize the Go module if go.mod doesn't exist
if [ ! -f "go.mod" ]; then
    go mod init github.com/gtsteffaniak/filebrowser
fi
# Tidy ensures all dependencies are present
go mod tidy

log "Building Filebrowser binary..."
# Point the build command to the correct subdirectory
go build -o filebrowser ./cmd/filebrowser

# 4. Install the Binary
log "Installing Filebrowser to $BINARY_PATH..."
mv filebrowser "$BINARY_PATH"

# 5. Set up Cron Job
CRON_JOB="0 2 * * * root $(readlink -f "$0")"
if ! grep -q "$CRON_JOB" /etc/crontab; then
    log "Adding cron job to /etc/crontab..."
    echo "$CRON_JOB" >> /etc/crontab
else
    log "Cron job already exists."
fi

log "Installation and setup complete."
