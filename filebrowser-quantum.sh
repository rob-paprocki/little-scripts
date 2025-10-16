#!/bin/bash

# --- Configuration ---
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="filebrowser"
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"
CONFIG_DIR="/etc/filebrowser"
CONFIG_FILE_PATH="${CONFIG_DIR}/config.yaml"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/filebrowser.service"
UPDATE_SCRIPT_PATH="/usr/local/bin/update-filebrowser.sh"
CRON_FILE_PATH="/etc/cron.d/filebrowser-updater"
LOG_FILE="/var/log/filebrowser-update.log"

# --- Script Logic ---

set -e
set -u

echo "--- File Browser Installer & Updater (Root Mode) ---"

## 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

---
## 2. Prompt for Port Number
FB_PORT=""
while true; do
    read -p "Enter the port for File Browser [8080]: " FB_PORT
    # If the user just hits Enter, use the default value.
    if [ -z "$FB_PORT" ]; then
        FB_PORT="8080"
    fi
    if [[ "$FB_PORT" =~ ^[0-9]+$ ]] && [ "$FB_PORT" -ge 1 ] && [ "$FB_PORT" -le 65535 ]; then
        echo "[INFO] File Browser will be configured to run on port ${FB_PORT}."
        break
    else
        echo "[ERROR] Invalid input. Please enter a number between 1 and 65535." >&2
        FB_PORT="" # Reset for the loop
    fi
done

---
## 3. Prompt for Discord Webhook URL (Optional)
DISCORD_WEBHOOK_URL=""
read -p "Enter your Discord webhook URL (or press Enter to skip): " DISCORD_WEBHOOK_URL
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "[INFO] Discord notifications will be sent upon update."
else
    echo "[INFO] Skipping Discord notification setup."
fi

---
## 4. Install Dependencies
echo "[INFO] Updating package list and installing dependencies (curl)..."
apt-get update
apt-get install -y curl

---
## 5. Create Directories
echo "[INFO] Creating directory: ${CONFIG_DIR}"
mkdir -p "$CONFIG_DIR"

---
## 6. Create Configuration File
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

---
## 7. Download and Install File Browser
echo "[INFO] Downloading latest File Browser binary from GitHub..."
TEMP_FILE="/tmp/filebrowser-bin"
# Use a User-Agent for the initial download as well for consistency
curl -sS --fail -L \
-A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
"$DOWNLOAD_URL" -o "$TEMP_FILE"

echo "[INFO] Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"
rm -f "$TEMP_FILE"

---
## 8. Verify Installation
if command -v $BINARY_NAME &> /dev/null; then
    INSTALLED_VERSION=$($BINARY_NAME version)
    echo "[SUCCESS] File Browser ${INSTALLED_VERSION} installed successfully."
else
    echo "[ERROR] filebrowser command not found after installation." >&2
    exit 1
fi

---
## 9. Create Systemd Service
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

---
## 10. Enable and Start Service
echo "[INFO] Enabling and starting the File Browser service..."
systemctl daemon-reload
systemctl enable filebrowser.service
systemctl start filebrowser.service
echo "[SUCCESS] Service enabled and started."

---
## 11. Setup Automatic Daily Updates
echo "[INFO] Setting up automatic daily updates..."
# Create the dedicated update script with the User-Agent fix
cat << EOF > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
set -e
TEMP_FILE="/tmp/filebrowser-update"
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
echo "--- File Browser Update Started: \$(date) ---"
echo "Downloading latest File Browser from gtsteffaniak/filebrowser..."
# Add a common browser User-Agent (-A) to prevent being blocked by GitHub
curl -sS --fail -L \\
-A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \\
"\$DOWNLOAD_URL" -o "\$TEMP_FILE"
# Check to ensure the file was downloaded successfully
if [ ! -s "\$TEMP_FILE" ]; then
    echo "Error: Download failed or the downloaded file is empty. Aborting update." >&2
    rm -f "\$TEMP_FILE"
    exit 1
fi
echo "Updating binary..."
systemctl stop filebrowser.service
install -m 755 "\$TEMP_FILE" "/usr/local/bin/filebrowser"
systemctl start filebrowser.service
rm -f "\$TEMP_FILE"
echo "File Browser update complete."
if [ -n "\$DISCORD_WEBHOOK_URL" ]; then
    HOSTNAME=\$(hostname)
    MESSAGE="✅ File Browser on server '\${HOSTNAME}' was successfully updated."
    JSON_PAYLOAD="{\\"content\\": \\"\${MESSAGE}\\"}"
    echo "Sending Discord notification..."
    curl -H "Content-Type: application/json" -X POST -d "\$JSON_PAYLOAD" "\$DISCORD_WEBHOOK_URL"
fi
echo "--- Update Finished ---"
echo ""
exit 0
EOF
chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created update script at ${UPDATE_SCRIPT_PATH}"

---
## 12. Create Cron Job
# Create the cron job file to run the script daily at 8:40 PM and log output
echo "40 20 * * * root $UPDATE_SCRIPT_PATH >> $LOG_FILE 2>&1" > "$CRON_FILE_PATH"
echo "[SUCCESS] Cron job created to run daily at 8:40 PM."
echo "[INFO] Update results will be logged to ${LOG_FILE}"

---
## 13. Final Instructions
echo
echo "--- Installation and Auto-Update Setup Complete ---"
echo "✅ File Browser is now running as the ROOT user!"
echo "   - Access it at: http://<your-server-ip>:${FB_PORT}"
echo "   - Config file:  ${CONFIG_FILE_PATH}"
echo "   - Database will be at: ${CONFIG_DIR}/filebrowser.db"
echo "   - To check status: sudo systemctl status filebrowser.service"
echo "   - Update logs are at: ${LOG_FILE}"
echo
