#!/bin/bash

# --- Configuration (Defaults & Placeholders) ---
# Installation directory for the binary
INSTALL_DIR="/usr/local/bin"
# Name of the final executable
BINARY_NAME="filebrowser"
# URL to download the latest linux-amd64 binary (Corrected URL)
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"
# Directory for configuration files
CONFIG_DIR="/etc/filebrowser"
# Path to the main config file
CONFIG_FILE_PATH="${CONFIG_DIR}/config.yaml"
# Directory for the database
DATA_DIR="/var/lib/filebrowser"
# Database file path
DATABASE_PATH="${DATA_DIR}/filebrowser.db"
# Systemd service file path
SYSTEMD_SERVICE_FILE="/etc/systemd/system/filebrowser.service"
# Path for the separate update script
UPDATE_SCRIPT_PATH="/usr/local/bin/update-filebrowser.sh"
# Path for the cron job file
CRON_FILE_PATH="/etc/cron.d/filebrowser-updater"
# User to run filebrowser as
SERVICE_USER="filebrowser"

# --- Script Logic ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

echo "--- Comprehensive File Browser Installer & Updater for Debian ---"
echo "--- Installs File Browser, creates a systemd service, and sets up a daily update cron job ---"

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

# 2. Prompt for Port Number
FB_PORT=""
while true; do
    read -p "Enter the port you want File Browser to run on (e.g., 8080): " FB_PORT
    # Check if input is an integer and within the valid port range
    if [[ "$FB_PORT" =~ ^[0-9]+$ ]] && [ "$FB_PORT" -ge 1 ] && [ "$FB_PORT" -le 65535 ]; then
        echo "[INFO] File Browser will be configured to run on port ${FB_PORT}."
        break
    else
        echo "[ERROR] Invalid input. Please enter a number between 1 and 65535." >&2
    fi
done

# 3. Update package list and install dependencies
echo "[INFO] Updating package list and installing dependencies (curl)..."
apt-get update
apt-get install -y curl

# 4. Create a dedicated user for File Browser
echo "[INFO] Creating a dedicated user '${SERVICE_USER}'..."
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    useradd -r -s /bin/false "$SERVICE_USER"
    echo "[SUCCESS] User '${SERVICE_USER}' created."
else
    echo "[INFO] User '${SERVICE_USER}' already exists."
fi

# 5. Create necessary directories
echo "[INFO] Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"
echo "[SUCCESS] Created directories: ${CONFIG_DIR} and ${DATA_DIR}"

# 6. Create the configuration file using the user-provided port
echo "[INFO] Creating configuration file at ${CONFIG_FILE_PATH}..."
cat << EOF > "$CONFIG_FILE_PATH"
server:
  port: ${FB_PORT}
  baseURL:  "/"
  logging:
    - levels: "info|warning|error"
  sources:
    - path: "/"
userDefaults:
  preview:
    image: true
    popup: true
    video: false
    office: false
    highQuality: false
  darkMode: true
  disableSettings: false
  singleClick: false
  permissions:
    admin: false
    modify: false
    share: false
    api: false
EOF
echo "[SUCCESS] Configuration file created."

# 7. Set ownership for directories and config
echo "[INFO] Setting ownership of config and data directories to '${SERVICE_USER}'..."
chown -R "${SERVICE_USER}:${SERVICE_USER}" "$CONFIG_DIR"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "$DATA_DIR"

# 8. Download and Install File Browser
echo "[INFO] Downloading latest File Browser binary from GitHub..."
TEMP_FILE="/tmp/filebrowser-bin"
curl -L "$DOWNLOAD_URL" -o "$TEMP_FILE"

echo "[INFO] Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
# Use install command which handles permissions and ownership better than mv
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"

# Clean up temporary files
rm -f "$TEMP_FILE"

# 9. Verify installation
echo "[INFO] Verifying installation..."
if command -v $BINARY_NAME &> /dev/null; then
    INSTALLED_VERSION=$($BINARY_NAME version)
    echo "[SUCCESS] File Browser ${INSTALLED_VERSION} installed successfully."
else
    echo "[ERROR] filebrowser command not found after installation. Check PATH or installation step." >&2
    exit 1
fi

# 10. Create the systemd service file
echo "[INFO] Creating systemd service file at ${SYSTEMD_SERVICE_FILE}..."
cat << EOF > "$SYSTEMD_SERVICE_FILE"
[Unit]
Description=File Browser
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
ExecStart=${INSTALL_DIR}/filebrowser -c ${CONFIG_FILE_PATH} -d ${DATABASE_PATH}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
echo "[SUCCESS] Systemd service file created."

# 11. Enable and start the File Browser service
echo "[INFO] Enabling and starting the File Browser service..."
systemctl daemon-reload
systemctl enable filebrowser.service
systemctl start filebrowser.service
echo "[SUCCESS] Service enabled and started."

# 12. Setup Automatic Daily Updates
echo "[INFO] Setting up automatic daily updates..."

# Create the dedicated update script
cat << 'EOF' > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
# This script is run by cron to update filebrowser automatically.

set -e

# Download the latest binary to a temporary file
TEMP_FILE="/tmp/filebrowser-update"
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"

echo "Downloading latest File Browser..."
curl -L "$DOWNLOAD_URL" -o "$TEMP_FILE"

# Stop the service, replace the binary, and start it again
echo "Updating binary..."
systemctl stop filebrowser.service
install -m 755 "$TEMP_FILE" "/usr/local/bin/filebrowser"
systemctl start filebrowser.service

# Clean up
rm -f "$TEMP_FILE"

echo "File Browser update complete."
exit 0
EOF

# Make the update script executable
chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created update script at ${UPDATE_SCRIPT_PATH}"

# Create the cron job file to run the script daily
# Runs at 3:30 AM every day. Output is sent to /dev/null to prevent cron emails.
echo "30 3 * * * root $UPDATE_SCRIPT_PATH >/dev/null 2>&1" > "$CRON_FILE_PATH"

echo "[SUCCESS] Cron job created at ${CRON_FILE_PATH}"
echo "[INFO] File Browser will now be updated automatically every day at 3:30 AM."

# --- Final Instructions ---
echo
echo "--- Installation and Auto-Update Setup Complete ---"
echo "✅ File Browser is now running!"
echo "   - Access it at: http://<your-server-ip>:${FB_PORT}"
echo "   - Config file:  ${CONFIG_FILE_PATH}"
echo "   - Database:     ${DATABASE_PATH}"
echo "   - To check status: sudo systemctl status filebrowser.service"
echo "   - To see logs:   sudo journalctl -u filebrowser.service"
echo
