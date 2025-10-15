#!/bin/bash

# This script installs Filebrowser Quantum on a Debian 13 Proxmox LXC,
# allows interactive port setting, and sets up a daily update cron job.

# --- Exit on error ---
set -e

# --- Welcome Message ---
echo "🚀 Starting Filebrowser Quantum Interactive Installation..."
echo "--------------------------------------------------------"

# --- Update and upgrade the system ---
echo "Updating and upgrading the system..."
sudo apt-get update && sudo apt-get upgrade -y > /dev/null 2>&1
echo "System updated."

# --- Install necessary dependencies ---
echo "Installing dependencies (curl, wget)..."
sudo apt-get install -y curl wget > /dev/null 2>&1
echo "Dependencies installed."

# --- Interactively set the listen port ---
FILEBROWSER_PORT=""
while true; do
    read -p "➡️ Enter the port for Filebrowser to listen on (e.g., 8080): " FILEBROWSER_PORT
    # Check if input is a number and within the valid port range
    if [[ "$FILEBROWSER_PORT" =~ ^[0-9]+$ ]] && [ "$FILEBROWSER_PORT" -gt 0 ] && [ "$FILEBROWSER_PORT" -le 65535 ]; then
        echo "✅ Port ${FILEBROWSER_PORT} is valid."
        break # Exit loop if input is valid
    else
        echo "❌ Invalid input. Please enter a number between 1 and 65535."
    fi
done

# --- Get the latest release of Filebrowser Quantum ---
echo "Downloading the latest Filebrowser Quantum release..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest" | grep -Po '"browser_download_url": "\K.*linux-amd64\.tar\.gz')
wget -qO /tmp/filebrowser.tar.gz "${LATEST_RELEASE}"

# --- Extract and install Filebrowser ---
echo "Installing Filebrowser Quantum..."
tar -xf /tmp/filebrowser.tar.gz -C /tmp/
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
echo "Creating automatic update script at /usr/local/bin/update_filebrowser.sh..."
sudo tee /usr/local/bin/update_filebrowser.sh > /dev/null <<'EOF'
#!/bin/bash
set -e
echo "Checking for new Filebrowser Quantum release..."
LATEST_RELEASE_URL=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest" | grep -Po '"browser_download_url": "\K.*linux-amd64\.tar\.gz')
CURRENT_VERSION=$(/usr/local/bin/filebrowser version)
LATEST_VERSION=$(echo ${LATEST_RELEASE_URL} | grep -Po 'v[0-9]+\.[0-9]+\.[0-9]+')

if [[ "v${CURRENT_VERSION}" == "${LATEST_VERSION}" ]]; then
    echo "Filebrowser is already up to date. (Version ${CURRENT_VERSION})"
    exit 0
fi

echo "New version ${LATEST_VERSION} found. Updating from ${CURRENT_VERSION}..."
wget -q -O /tmp/filebrowser.tar.gz "${LATEST_RELEASE_URL}"
systemctl stop filebrowser.service
tar -xf /tmp/filebrowser.tar.gz -C /tmp/
mv /tmp/filebrowser /usr/local/bin/
chmod +x /usr/local/bin/filebrowser
systemctl start filebrowser.service
rm /tmp/filebrowser.tar.gz
echo "Filebrowser successfully updated to ${LATEST_VERSION}."
EOF

# --- Make the update script executable ---
sudo chmod +x /usr/local/bin/update_filebrowser.sh

# --- Add a cron job to run the update script daily ---
echo "Adding cron job for daily updates..."
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/update_filebrowser.sh >/dev/null 2>&1") | crontab -

# --- Clean up downloaded files ---
rm /tmp/filebrowser.tar.gz

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
