#!/bin/bash

# This script installs Filebrowser Quantum on a Debian 13 Proxmox LXC.
# Version 1.8: Made jq query more robust to handle releases with null/empty assets.

# --- Exit on error ---
set -e

# --- Welcome Message ---
echo "🚀 Starting Filebrowser Quantum Interactive Installation...🚀"
echo "--------------------------------------------------------"

# --- Update and upgrade the system ---
echo "Updating and upgrading the system (this may take a moment)..."
sudo apt-get update > /dev/null 2>&1 && sudo apt-get upgrade -y > /dev/null 2>&1
echo "System updated."

# --- Install necessary dependencies ---
echo "Installing dependencies (curl, wget, ffmpeg, jq, unzip)..."
sudo apt-get install -y curl wget ffmpeg jq unzip > /dev/null 2>&1
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
echo "Finding the latest Filebrowser release archive..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases" | jq -r '[.[] | select((.assets | length > 0) and (.assets[].name == "linux-amd64.zip"))] | .[0].assets[] | select(.name == "linux-amd64.zip") | .browser_download_url')

if [[ -z "$LATEST_RELEASE" || "$LATEST_RELEASE" == "null" ]]; then
    echo "❌ ERROR: Could not dynamically find a download URL for the 'linux-amd64.zip' asset."
    echo "This can be caused by a network issue or GitHub API rate limiting."
    exit 1
fi

echo "Downloading release from ${LATEST_RELEASE}"
wget -qO /tmp/filebrowser.zip "${LATEST_RELEASE}"

# --- Extract and install the correct binary ---
echo "Extracting and installing server binary..."
unzip -q -o /tmp/filebrowser.zip -d /tmp/
sudo mv /tmp/filebrowser /usr/local/bin/
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
echo "Creating automatic update script..."
sudo tee /usr/local/bin/update_filebrowser.sh > /dev/null <<'EOF'
#!/bin/bash
set -e
echo "Checking for new Filebrowser Quantum release..."
LATEST_RELEASE_URL=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases" | jq -r '[.[] | select((.assets | length > 0) and (.assets[].name == "linux-amd64.zip"))] | .[0].assets[] | select(.name == "linux-amd64.zip") | .browser_download_url')

if [[ -z "$LATEST_RELEASE_URL" || "$LATEST_RELEASE_URL" == "null" ]]; then
    echo "Could not fetch latest release URL. Skipping update."
    exit 0
fi

echo "New version found. Updating..."
wget -qO /tmp/filebrowser.zip "${LATEST_RELEASE_URL}"
systemctl stop filebrowser.service
unzip -q -o /tmp/filebrowser.zip -d /tmp/
mv /tmp/filebrowser /usr/local/bin/
chmod +x /usr/local/bin/filebrowser
systemctl start filebrowser.service
rm /tmp/filebrowser.zip
echo "Filebrowser successfully updated."
EOF

# --- Make the update script executable ---
sudo chmod +x /usr/local/bin/update_filebrowser.sh

# --- Add a cron job for daily updates ---
echo "Adding cron job for daily updates..."
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/update_filebrowser.sh >/dev/null 2>&1") | crontab -

# --- Clean up downloaded files ---
rm /tmp/filebrowser.zip

# --- Installation complete ---
echo
