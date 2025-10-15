#!/bin/bash

# --- Configuration ---
# This script installs File Browser from a direct binary link, sets it up
# as a systemd service, and creates a cron job for daily updates.
#
# It will prompt you to enter a port number during execution.
#
DEFAULT_PORT=8080
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="filebrowser"
CONFIG_DIR="/etc/filebrowser"
DATA_DIR="/srv"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
DATABASE_FILE="${CONFIG_DIR}/filebrowser.db"
UPDATE_SCRIPT_PATH="/usr/local/bin/update-filebrowser.sh"
CRON_FILE_PATH="/etc/cron.d/filebrowser-updater"
SERVICE_FILE_PATH="/etc/systemd/system/filebrowser.service"

# --- Script Logic ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

echo "--- Comprehensive File Browser Installer & Service Setup for Debian ---"
echo

# 1. Prompt for port and validate
read -p "Enter the port for File Browser to run on [${DEFAULT_PORT}]: " USER_PORT
# If the user just hits enter, use the default port.
USER_PORT=${USER_PORT:-$DEFAULT_PORT}

if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]] || [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
    echo "[ERROR] Invalid port number: '$USER_PORT'. Please provide a number between 1 and 65535." >&2
    exit 1
fi
echo "--- Using Port: $USER_PORT ---"


# 2. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

# 3. Install dependencies (only curl is needed)
echo "[INFO] Updating package list and installing dependencies (curl)..."
apt-get update
apt-get install -y curl

# 4. Create necessary directories
echo "[INFO] Creating configuration and data directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"

# 5. Create the configuration file
echo "[INFO] Creating config file at ${CONFIG_FILE}..."
cat << EOF > "$CONFIG_FILE"
# This file is managed by the installation script.
server:
  port: ${USER_PORT}
  baseURL: "/"
  log: "stdout" # Systemd will handle logging
  database: "${DATABASE_FILE}" # Specify database path
root: "${DATA_DIR}" # Specify root directory for files
auth:
  method: "noauth" # Default to no auth. Change as needed.
branding:
  name: "My Files"
  disableExternal: true
userDefaults:
  scope: "."
  locale: "en"
  viewMode: "mosaic"
  singleClick: false
  perm:
    admin: false
    execute: true
    create: false
    rename: false
    modify: false
    delete: false
    share: false
    download: true
EOF

echo "[INFO] Configuration file created."
echo "[WARNING] Initial configuration is set to 'noauth'. Run 'filebrowser users add <user> <pass> --perm.admin' after install to secure it."

# 6. Download and install File Browser
echo "[INFO] Downloading latest File Browser binary from GitHub..."
TEMP_BINARY="/tmp/${BINARY_NAME}"
if curl -L "$DOWNLOAD_URL" -o "$TEMP_BINARY"; then
    echo "[INFO] Download successful."
else
    echo "[ERROR] Failed to download File Browser from $DOWNLOAD_URL" >&2
    rm -f "$TEMP_BINARY"
    exit 1
fi

echo "[INFO] Installing File Browser to ${INSTALL_DIR}/${BINARY_NAME}..."
install -m 755 "$TEMP_BINARY" "${INSTALL_DIR}/${BINARY_NAME}"
rm -f "$TEMP_BINARY"

# 7. Verify installation
echo "[INFO] Verifying installation..."
if command -v $BINARY_NAME &> /dev/null; then
    INSTALLED_VERSION=$($BINARY_NAME version)
    echo "[SUCCESS] File Browser ${INSTALLED_VERSION} installed successfully to ${INSTALL_DIR}/${BINARY_NAME}"
else
    echo "[ERROR] filebrowser command not found after installation. Check PATH or installation step." >&2
    exit 1
fi

# 8. Create the systemd service file (Corrected ExecStart)
echo "[INFO] Creating systemd service file at ${SERVICE_FILE_PATH}..."
cat << EOF > "$SERVICE_FILE_PATH"
[Unit]
Description=File Browser
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=${INSTALL_DIR}/${BINARY_NAME} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 9. Enable and start the service
echo "[INFO] Reloading systemd daemon and starting File Browser service..."
systemctl daemon-reload
systemctl enable filebrowser.service
systemctl start filebrowser.service

echo "[INFO] Service enabled and started."

# 10. Setup Automatic Daily Updates
echo "[INFO] Setting up automatic daily updates..."
cat << EOF > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
# This script is run by cron to update File Browser automatically.

# Exit on error
set -e

# Download the latest binary to a temporary file
TEMP_BINARY_UPDATE="/tmp/filebrowser-update"
curl -L "${DOWNLOAD_URL}" -o "\$TEMP_BINARY_UPDATE"

# Stop the service to replace the binary
systemctl stop filebrowser.service

# Replace the old binary with the new one
install -m 755 "\$TEMP_BINARY_UPDATE" "${INSTALL_DIR}/${BINARY_NAME}"

# Start the service again
systemctl start filebrowser.service

# Clean up
rm -f "\$TEMP_BINARY_UPDATE"

exit 0
EOF

# Make the update script executable
chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created update script at ${UPDATE_SCRIPT_PATH}"

# Create the cron job file to run the script daily at 4:15 AM
echo "15 4 * * * root $UPDATE_SCRIPT_PATH >/dev/null 2>&1" > "$CRON_FILE_PATH"
chmod 644 "$CRON_FILE_PATH"

echo "[SUCCESS] Cron job created at ${CRON_FILE_PATH}"
echo "[INFO] File Browser will now be updated automatically every day at 4:15 AM."

# --- Final Instructions ---
echo
echo "--- Installation and Service Setup Complete ---"
echo "[INFO] File Browser is running and will start on boot."
echo "[INFO] Access it by navigating to http://<your-server-ip>:${USER_PORT} in a web browser."
echo "[INFO] To check the status, run: sudo systemctl status filebrowser.service"
echo "[INFO] To view logs, run: sudo journalctl -u filebrowser.service -f"
echo "[IMPORTANT] For security, create an admin user now: ${BINARY_NAME} users add <username> <password> --perm.admin"
echo "[IMPORTANT] Then, edit ${CONFIG_FILE} and change 'auth.method' to 'json' and restart with 'sudo systemctl restart filebrowser.service'."

exit 0
