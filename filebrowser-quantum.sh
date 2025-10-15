#!/bin/bash

# This script installs Filebrowser Quantum on a Debian 13 Proxmox LXC.
# Version 1.4: Added ffmpeg as a dependency.

# --- Exit on error ---
set -e

# --- Welcome Message ---
echo "🚀 Starting Filebrowser Quantum Interactive Installation..."
echo "--------------------------------------------------------"

# --- Update and upgrade the system ---
echo "Updating and upgrading the system (this may take a moment)..."
sudo apt-get update > /dev/null 2>&1 && sudo apt-get upgrade -y > /dev/null 2>&1
echo "System updated."

# --- Install necessary dependencies ---
echo "Installing dependencies (curl, wget, ffmpeg)..."
sudo apt-get install -y curl wget ffmpeg > /dev/null 2>&1
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

# --- Get the latest release of Filebrowser Quantum ---
echo "Finding the latest Filebrowser Quantum release..."

# Look for the raw binary file, anchored to the end of the line
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest" | grep -Po '"browser_download_url": "\K.*linux-amd64-filebrowser$' || true)

if [[ -z "${LATEST_RELEASE}" ]]; then
    echo "❌ ERROR: Could not find the download URL for the 'linux-amd64-filebrowser' release asset."
    echo "This can be caused by a network issue, GitHub API rate limiting, or a change in release assets."
    echo "Please check the releases page manually: https://github.com/gtsteffaniak/filebrowser/releases/latest"
    exit 1
fi

echo "Downloading and installing Filebrowser binary..."
# Download the binary directly to its final destination
sudo wget -qO /usr/local/bin/filebrowser "${LATEST_RELEASE}"

# Make the binary executable
sudo chmod +x /usr/local/bin/filebrowser

# --- Create a directory for Filebrowser data ---
sudo mkdir -p /srv/filebrowser
echo "Data directory created at /srv/filebrowser."

# --- Create a systemd service for Filebrowser ---
echo "Creating systemd service..."
sudo tee /etc/systemd/system/filebrowser.service > /dev/null <<EOF
[Unit]
Description=Filebrowser
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

# --- Create an automatic update script ---
echo "Creating automatic update script at /usr/local/bin/update_filebrowser.sh..."
sudo tee /usr/local/bin/update_filebrowser.sh > /dev/null <<'EOF'
#!/bin/bash
set -e
echo "Checking for new Filebrowser Quantum release..."
LATEST_RELEASE_URL=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest" | grep -Po '"browser_download_url": "\K.*linux-amd64-filebrowser$' || true)
if [[ -z "${LATEST_RELEASE_URL}" ]]; then
    echo "Could not fetch latest release URL. Skipping update."
    exit 0
fi

CURRENT_VERSION=$(/usr/local/bin/filebrowser version)
LATEST_VERSION=$(echo ${LATEST_RELEASE_URL} | grep -Po 'v[0-9]+\.[0-9]+\.[0-9]+')

if [[ "v${CURRENT_VERSION}" == "${LATEST_VERSION}" ]]; then
    echo "Filebrowser is already up to date. (Version ${CURRENT_VERSION})"
    exit 0
fi

echo "New version ${LATEST_VERSION} found. Updating from ${CURRENT_VERSION}..."
wget -qO /tmp/filebrowser.new "${LATEST_RELEASE_URL}"
systemctl stop filebrowser.service
mv /tmp/filebrowser.new /usr/local/bin/filebrowser
chmod +x /usr/local/bin/filebrowser
systemctl start filebrowser.service
echo "Filebrowser successfully updated to ${LATEST_VERSION}."
EOF

# --- Make the update script executable ---
sudo chmod +x /usr/local/bin/update_filebrowser.sh

# --- Add a cron job to run the update script daily ---
echo "Adding cron job for daily updates..."
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/update_filebrowser.sh >/dev/null 2>&1") | crontab -

# --- Installation complete ---
echo ""
echo "--------------------------------------------------------"
echo "🎉 Filebrowser Quantum installation is complete! 🎉"
echo ""
echo "You can access it at: http://<your-lxc-ip>:${FILEBROWSER_PORT}"
echo "Default login: admin / admin (Change this immediately!)"
echo ""
echo "A cron job has been created to automatically update Filebrowser daily at 3:00 AM."
echo "--------------------------------------------------------"
