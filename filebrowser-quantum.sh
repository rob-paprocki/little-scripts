#!/bin/bash

# --- Configuration ---
# Installation directory for the binary
INSTALL_DIR="/usr/local/bin"
# Name of the final executable
BINARY_NAME="filebrowser"
# URL to download the latest linux-amd64 binary
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"
# Directory for configuration files and data (as root)
CONFIG_DIR="/etc/filebrowser"
# Path to the main config file
CONFIG_FILE_PATH="${CONFIG_DIR}/config.yaml"
# Systemd service file path
SYSTEMD_SERVICE_FILE="/etc/systemd/system/filebrowser.service"
# Path for the separate update script
UPDATE_SCRIPT_PATH="/usr/local/bin/update-filebrowser.sh"
# Path for the cron job file
CRON_FILE_PATH="/etc/cron.d/filebrowser-updater"
# Log file for the update script
LOG_FILE="/var/log/filebrowser-update.log"

# --- Script Logic ---

set -e
set -u

echo "--- File Browser Installer & Updater (Root Mode) ---"

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

# 2. Prompt for Port Number with a default
FB_PORT=""
while true; do
    read -p "Enter the port for File Browser [8080]: " FB_PORT
    if [ -z "$FB_PORT" ]; then
        FB_PORT="8080"
    fi
    if [[ "$FB_PORT" =~ ^[0-9]+$ ]] && [ "$FB_PORT" -ge 1 ] && [ "$FB_PORT" -le 65535 ]; then
        echo "[INFO] File Browser will be configured to run on port ${FB_PORT}."
        break
    else
        echo "[ERROR] Invalid input. Please enter a number between 1 and 65535." >&2
        FB_PORT=""
    fi
done

# 3. Prompt for Discord Webhook URL (Optional)
DISCORD_WEBHOOK_URL=""
read -p "Enter your Discord webhook URL (or press Enter to skip): " DISCORD_WEBHOOK_URL
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "[INFO] Discord notifications will be sent upon update."
else
    echo "[INFO] Skipping Discord notification setup."
fi

# 4. Update package list and install dependencies
echo "[INFO] Updating package list and installing dependencies (curl)..."
apt-get update
apt-get install -y curl

# 5. Create necessary directories (will be owned by root)
echo "[INFO] Creating directory: ${CONFIG_DIR}"
mkdir -p "$CONFIG_DIR"

# 6. Create the configuration file
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

# 7. Download and Install File Browser
echo "[INFO] Downloading latest File Browser binary from GitHub..."
TEMP_FILE="/tmp/filebrowser-bin"
curl --fail -L "$DOWNLOAD_URL" -o "$TEMP_FILE"
echo "[INFO] Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"
rm -f "$TEMP_FILE"

# 8. Verify installation
if command -v $BINARY_NAME &> /dev/null; then
    INSTALLED_VERSION=$($BINARY_NAME version)
    echo "[SUCCESS] File Browser ${INSTALLED_VERSION} installed successfully."
else
    echo "[ERROR] filebrowser command not found after installation." >&2
    exit 1
fi

# 9. Create the systemd service file
echo "[INFO] Creating systemd service file at ${SYSTEMD_SERVICE_FILE}..."
cat << EOF > "$SYSTEMD_SERVICE_FILE"
[Unit]
Description=File Browser
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/filebrowser -c ${CONFIG_FILE_PATH}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
echo "[SUCCESS] Systemd service file created."

# 10. Enable and start the File Browser service
echo "[INFO] Enabling and starting the File Browser service..."
systemctl daemon-reload
systemctl enable filebrowser.service
systemctl start filebrowser.service
echo "[SUCCESS] Service enabled and started."

# 11. Setup Automatic Daily Updates with a Robust Method
echo "[INFO] Setting up automatic daily updates..."

# Use a 'here document' with a quoted delimiter to prevent shell expansion.
# This makes the script much cleaner and less prone to escaping errors.
cat << 'EOF' > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
set -e
set -u

# --- Configuration ---
TEMP_FILE="/tmp/filebrowser-update"
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"
INSTALL_PATH="/usr/local/bin/filebrowser"
SERVICE_NAME="filebrowser.service"
# This URL is a placeholder that will be replaced by the installer script.
DISCORD_WEBHOOK_URL="##DISCORD_WEBHOOK_URL_PLACEHOLDER##"

# --- Logic ---
echo "--- File Browser Update Started: $(date) ---"

echo "Downloading latest File Browser..."
# Use --fail to ensure curl exits with an error on HTTP failures (like 404)
# Use -sS for silent output on success, but show errors.
if ! curl -sS --fail -L "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "Error: Download failed from $DOWNLOAD_URL. Aborting update." >&2
    # Clean up the temp file if it was created
    rm -f "$TEMP_FILE"
    exit 1
fi

# Add a check to ensure the downloaded file is not empty
if [ ! -s "$TEMP_FILE" ]; then
    echo "Error: Downloaded file is empty. Aborting update." >&2
    rm -f "$TEMP_FILE" # Clean up empty file
    exit 1
fi

echo "Updating binary..."
systemctl stop "$SERVICE_NAME"
install -m 755 "$TEMP_FILE" "$INSTALL_PATH"
systemctl start "$SERVICE_NAME"

# Clean up the downloaded file
rm -f "$TEMP_FILE"

INSTALLED_VERSION=$($INSTALL_PATH version)
echo "File Browser update complete. Now running: ${INSTALLED_VERSION}"

# Send Discord notification if the URL was provided
if [[ -n "$DISCORD_WEBHOOK_URL" && "$DISCORD_WEBHOOK_URL" != "##DISCORD_WEBHOOK_URL_PLACEHOLDER##" ]]; then
    HOSTNAME=$(hostname)
    MESSAGE="✅ File Browser on server '${HOSTNAME}' was successfully updated to ${INSTALLED_VERSION}."
    # Properly format the JSON payload
    JSON_PAYLOAD=$(printf '{"content": "%s"}' "$MESSAGE")
    
    echo "Sending Discord notification..."
    curl -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" "$DISCORD_WEBHOOK_URL"
fi

echo "--- Update Finished ---"
echo ""
exit 0
EOF

# Use sed to safely replace the placeholder with the actual webhook URL.
# Using '|' as a separator avoids issues if the URL contains slashes '/'.
sed -i "s|##DISCORD_WEBHOOK_URL_PLACEHOLDER##|${DISCORD_WEBHOOK_URL}|g" "$UPDATE_SCRIPT_PATH"

chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created update script at ${UPDATE_SCRIPT_PATH}"

# Create the cron job file to run the script daily at 8:15 PM and log output
echo "20 21 * * * root $UPDATE_SCRIPT_PATH >> $LOG_FILE 2>&1" > "$CRON_FILE_PATH"
echo "[SUCCESS] Cron job created to run daily at 8:15 PM."
echo "[INFO] Update results will be logged to ${LOG_FILE}"

# --- Final Instructions ---
echo
echo "--- Installation and Auto-Update Setup Complete ---"
echo "✅ File Browser is now running as the ROOT user!"
echo "   - Access it at: http://<your-server-ip>:${FB_PORT}"
echo "   - Config file:  ${CONFIG_FILE_PATH}"
echo "   - Database will be at: ${CONFIG_DIR}/filebrowser.db"
echo "   - To check status: sudo systemctl status filebrowser.service"
echo "   - Update logs are at: ${LOG_FILE}"
