#!/bin/bash

# This script installs Filebrowser Quantum on a Debian 13 Proxmox LXC
# and sets up a daily cron job to keep it updated.

# --- Exit on error ---
set -e

# --- Update and upgrade the system ---
echo "Updating and upgrading the system..."
sudo apt update && sudo apt upgrade -y

# --- Install necessary dependencies ---
echo "Installing dependencies..."
sudo apt install -y curl wget

# --- Get the latest release of Filebrowser Quantum ---
echo "Downloading the latest Filebrowser Quantum release..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest" | grep -Po '"browser_download_url": "\K.*linux-amd64\.tar\.gz')
wget -O /tmp/filebrowser.tar.gz "${LATEST_RELEASE}"

# --- Extract and install Filebrowser ---
echo "Installing Filebrowser Quantum..."
tar -xvf /tmp/filebrowser.tar.gz -C /tmp/
sudo mv /tmp/filebrowser /usr/local/bin/
sudo chmod +x /usr/local/bin/filebrowser

# --- Create a directory for Filebrowser data ---
echo "Creating a directory for Filebrowser data..."
sudo mkdir -p /srv/filebrowser

# --- Create a systemd service for Filebrowser ---
echo "Creating a systemd service for Filebrowser..."
sudo tee /etc/systemd/system/filebrowser.service > /dev/null <<EOF
[Unit]
Description=Filebrowser
After=network-online.target

[Service]
User=root
Group=root
ExecStart=/usr/local/bin/filebrowser -r /srv/filebrowser -a 0.0.0.0 -p 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --- Reload systemd, enable and start Filebrowser ---
echo "Enabling and starting the Filebrowser service..."
sudo systemctl daemon-reload
sudo systemctl enable filebrowser.service
sudo systemctl start filebrowser.service

# --- Create an automatic update script ---
echo "Creating an automatic update script at /usr/local/bin/update_filebrowser.sh..."
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
tar -xvf /tmp/filebrowser.tar.gz -C /tmp/
mv /tmp/filebrowser /usr/local/bin/
chmod +x /usr/local/bin/filebrowser
systemctl start filebrowser.service
rm /tmp/filebrowser.tar.gz
echo "Filebrowser successfully updated to ${LATEST_VERSION}."
EOF

# --- Make the update script executable ---
sudo chmod +x /usr/local/bin/update_filebrowser.sh

# --- Add a cron job to run the update script daily ---
echo "Adding a cron job to run the update script daily at 3:00 AM..."
# This command safely adds the cron job without overwriting existing ones.
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/update_filebrowser.sh") | crontab -


# --- Clean up downloaded files ---
echo "Cleaning up initial download..."
rm /tmp/filebrowser.tar.gz

# --- Installation complete ---
echo "Filebrowser Quantum installation is complete!"
echo "You can access it at http://<your-lxc-ip>:8080"
echo "Default login: admin / admin"
echo "A cron job has been created to automatically update Filebrowser daily at 3:00 AM."
