#!/bin/bash

# --- Configuration ---
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="yt-dlp"
DOWNLOAD_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
UPDATE_SCRIPT_PATH="/usr/local/bin/update-yt-dlp.sh"
CRON_FILE_PATH="/etc/cron.d/yt-dlp-updater"
LOG_FILE="/var/log/yt-dlp-update.log"

# --- Script Logic ---

# Exit on error, treat unset variables as error, and handle pipe failures
set -euo pipefail

echo "--- Comprehensive yt-dlp Installer & Updater for Debian-based Systems (v2) ---"
echo "--- Installs dependencies and sets up a robust daily update cron job ---"

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

# 2. Prompt user for Discord Webhook URL
echo
read -p "Enter your Discord Webhook URL (or press Enter to skip): " DISCORD_WEBHOOK_URL
if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    echo "[INFO] No webhook URL provided. Discord notifications will be disabled."
    DISCORD_WEBHOOK_URL="" 
else
    echo "[SUCCESS] Discord webhook URL received. Notifications will be enabled."
fi
echo

# 3. System update and dependency installation
echo "[INFO] Updating package list and installing dependencies..."
apt-get update
apt-get install -y \
    python3 ffmpeg ca-certificates curl atomicparsley \
    python3-mutagen python3-pycryptodome python3-websockets \
    bash-completion aria2

echo "[INFO] Dependencies installed."

# 4. Download and install yt-dlp
echo "[INFO] Downloading and installing the latest yt-dlp binary..."
TEMP_FILE=$(mktemp) # Use mktemp for a secure temporary file
if ! curl -L "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "[ERROR] Failed to download yt-dlp binary." >&2
    rm -f "$TEMP_FILE"
    exit 1
fi
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"
rm -f "$TEMP_FILE"
echo "[INFO] yt-dlp installed successfully."

# 5. Verify installation
# Use a function to avoid repeating the command
get_yt_dlp_version() {
    "${INSTALL_DIR}/${BINARY_NAME}" --version
}
if INSTALLED_VERSION=$(get_yt_dlp_version); then
    echo "[SUCCESS] yt-dlp version ${INSTALLED_VERSION} is now installed."
else
    echo "[ERROR] yt-dlp command failed after installation." >&2
    exit 1
fi

# 6. Setup Automatic Daily Updates
echo "[INFO] Setting up automatic daily updates..."

# [CORRECTED] Create the dedicated update script with robust syntax
cat << EOF > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
# This script is run by cron to update yt-dlp automatically.

set -euo pipefail

# --- Configuration ---
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
INSTALL_PATH="/usr/local/bin/yt-dlp"

# --- Function to send Discord notification ---
send_discord_notification() {
    local message="\$1"
    local color="\$2"

    if [ -z "\$DISCORD_WEBHOOK_URL" ]; then
        echo "Skipping Discord notification as no webhook is configured."
        return
    fi
    
    local json_payload
    json_payload=\$(printf '{"content": null, "embeds": [{"title": "yt-dlp Auto-Update Status","description": "%s","color": %s, "author": {"name": "Cron Job on %s"}}], "username": "yt-dlp Updater", "avatar_url": "https://i.imgur.com/tH31Yxt.png"}' "\$message" "\$color" "\$(hostname)")
    
    curl --silent --show-error -H "Content-Type: application/json" -X POST -d "\$json_payload" "\$DISCORD_WEBHOOK_URL" || echo "[ERROR] Failed to send Discord notification."
}

# --- Main Update Logic ---
echo "--- Starting yt-dlp update check: \$(date) ---"

if ! command -v "\$INSTALL_PATH" &> /dev/null; then
    send_discord_notification "🚨 **Update Failed!**\n\\\`yt-dlp\\\` not found at \$INSTALL_PATH." 15728640 # Red
    exit 1
fi

# [ROBUST] Correctly get current version or exit on failure
OLD_VERSION=\$("\$INSTALL_PATH" --version) || {
    send_discord_notification "🚨 **Update Failed!**\nCould not execute \\\`\$INSTALL_PATH --version\\\` to get current version." 15728640 # Red
    exit 1
}
echo "Current version: \$OLD_VERSION"

# Download to a secure temporary file
TEMP_FILE=\$(mktemp)
if ! curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "\$TEMP_FILE"; then
    send_discord_notification "🚨 **Update Failed!**\nCould not download the latest binary from GitHub." 15728640 # Red
    rm -f "\$TEMP_FILE"
    exit 1
fi

install -m 755 "\$TEMP_FILE" "\$INSTALL_PATH"
rm -f "\$TEMP_FILE"

# [ROBUST] Correctly get new version or exit on failure
NEW_VERSION=\$("\$INSTALL_PATH" --version) || {
    send_discord_notification "🚨 **Update Failed!**\nCould not get version after replacing the binary." 15728640 # Red
    exit 1
}
echo "New version: \$NEW_VERSION"

# Send notification based on result
if [ "\$OLD_VERSION" != "\$NEW_VERSION" ]; then
    MESSAGE="✅ **yt-dlp was updated successfully!**\n\n**Host:** \\\`\$(hostname)\\\`\n**Old Version:** \\\`\$OLD_VERSION\\\`\n**New Version:** \\\`\$NEW_VERSION\\\`"
    send_discord_notification "\$MESSAGE" 5814783 # Green
else
    MESSAGE="✔️ **yt-dlp update check complete.**\n\n**Host:** \\\`\$(hostname)\\\`\n**Status:** Already up-to-date\n**Current Version:** \\\`\$OLD_VERSION\\\`"
    send_discord_notification "\$MESSAGE" 3447003 # Blue
fi

echo "--- Update check finished ---"
exit 0
EOF

# Make the update script executable
chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created corrected update script at ${UPDATE_SCRIPT_PATH}"

# Create the cron job file to run the script at 8:30 PM (20:30)
echo "0 22 * * * root $UPDATE_SCRIPT_PATH >> $LOG_FILE 2>&1" > "$CRON_FILE_PATH"

echo "[SUCCESS] Cron job has been corrected and configured."
echo "[INFO] yt-dlp will check for updates daily at 10:00 PM."
echo "[INFO] Update logs are stored in ${LOG_FILE}"

echo "--- Setup Complete ---"
exit 0
