#!/bin/bash

# This script installs the Filebrowser Quantum fork by building it from source.
# Version 4.2: Adds 'go mod init' to correctly initialize the project as a Go
#              module before compiling, fixing the 'cannot find main module' error.

# --- Exit on error ---
set -e

# --- Welcome Message ---
echo "🚀 Starting Filebrowser Quantum (Build from Source) Installation..."
echo "--------------------------------------------------------"

# --- Update and upgrade the system ---
echo "Updating and upgrading the system..."
sudo apt-get update > /dev/null 2>&1 && sudo apt-get upgrade -y > /dev/null 2>&1
echo "System updated."

# --- Install build dependencies ---
echo "Installing dependencies (git, golang, ffmpeg)..."
sudo apt-get install -y git golang ffmpeg > /dev/null 2>&1
echo "Dependencies installed."

# --- Interactively set the listen port ---
FILEBROWSER_PORT=""
while true; do
    read -p "➡️ Enter the port for Filebrowser to listen on (e.g., 8080): " FILEBROWSER_PORT
    if [[ "$FILEBROWSER_PORT" =~ ^[0-9]+$ ]] && [ "$FILEBROWSER_PORT" -gt 0 ] && [ "$FILEBROWSER_PORT" -le 65535 ]; then
        echo "✅ Port ${FILEBROWSER_PORT} is valid."
        break
    else
        echo "❌ Invalid input. Please enter a number between 1 and 65535."
    fi
done

# --- Download the source code ---
echo "Downloading Filebrowser Quantum source code..."
# Clean up any old source directories first
sudo rm -rf /tmp/filebrowser-src
git clone https://github.com/gtsteffaniak/filebrowser.git /tmp/filebrowser-src > /dev/null 2>&1

# --- Compile the binary from source ---
cd /tmp/filebrowser-src
echo "Initializing Go module..."
# This command creates the go.mod file that the compiler needs.
go mod init github.com/gtsteffaniak/filebrowser > /dev/null 2>&1

echo "Downloading Go modules..."
go mod tidy > /dev/null 2>&1

echo "Compiling the binary (this may take a minute)..."
go build -o filebrowser . > /dev/null 2>&1

# --- Install the compiled binary ---
echo "Installing the compiled binary..."
sudo mv ./filebrowser /usr/local/bin/

# --- Create a directory for Filebrowser data ---
sudo mkdir -p /srv/filebrowser
echo "Data directory created at /srv/filebrowser."

# --- Create a systemd service ---
echo "Creating systemd service..."
sudo tee /etc/systemd/system/filebrowser.service > /dev/null <<EOF
[Unit]
Description=Filebrowser Quantum
After=network-online.target

[Service]
User=root
Group=root
ExecStart=/usr/local/bin/filebrowser -r /srv/filebrowser -a 0.0.0.0 -p ${FILEBROWSER_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --- Reload systemd, enable and start Filebrowser ---
echo "Starting the Filebrowser service..."
sudo systemctl daemon-reload
sudo systemctl enable filebrowser.service > /dev/null 2>&1
sudo systemctl start filebrowser.service

# --- Clean up source files ---
cd ~
sudo rm -rf /tmp/filebrowser-src

# --- Installation complete ---
echo ""
echo "--------------------------------------------------------"
echo "🎉 Filebrowser Quantum installation is complete! 🎉"
echo ""
echo "You can access it at: http://<your-lxc-ip>:${FILEBROWSER_PORT}"
echo "Default login: admin / admin (Change this immediately!)"
echo "--------------------------------------------------------"
