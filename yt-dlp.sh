#!/bin/bash

# --- Configuration ---
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="yt-dlp"
DOWNLOAD_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
UPDATE_SCRIPT_PATH="/usr/local/bin/update-yt-dlp.sh"
CRON_FILE_PATH="/etc/cron.d/yt-dlp-updater"
LOG_FILE="/var/log/yt-dlp-update.log"

# --- Script Logic ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

echo "--- Comprehensive yt-dlp Installer & Updater for Debian-based Systems ---"
echo "--- Installs dependencies, sets up a daily update cron job with Discord notifications ---"
echo "--- Script run time: $(date '+%Y-%m-%d %H:%M:%S %Z') ---"

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

# 2. [NEW] Prompt user for Discord Webhook URL
echo
echo "[CONFIG] To receive notifications when yt-dlp is updated, you can provide a Discord webhook URL."
echo "[INFO] How to get a URL: In your Discord server, go to Server Settings > Integrations > Webhooks > New Webhook."
# Use 'read -p' to prompt the user and store input in the DISCORD_WEBHOOK_URL variable
read -p "Enter your Discord Webhook URL (or press Enter to skip): " DISCORD_WEBHOOK_URL

# Check if the user provided a URL or skipped
if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    echo "[INFO] No webhook URL provided. Discord notifications will be disabled."
    # Set to an empty string to ensure the update script handles it correctly
    DISCORD_WEBHOOK_URL="" 
else
    echo "[SUCCESS] Discord webhook URL received. Notifications will be enabled."
fi
echo

# 3. Update package list
echo "[INFO] Updating package list..."
apt-get update

# 4. Install dependencies
echo "[INFO] Installing dependencies (core, metadata, crypto, python-websockets, shell completion, accelerator)..."
apt-get install -y \
    python3 \
    ffmpeg \
    ca-certificates \
    curl \
    atomicparsley \
    python3-mutagen \
    python3-pycryptodome \
    python3-websockets \
    bash-completion \
    aria2

echo "[INFO] Dependencies installed."

# 5. Download yt-dlp binary
echo "[INFO] Downloading latest yt-dlp binary from GitHub..."
TEMP_FILE="/tmp/${BINARY_NAME}"
if curl -L "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "[INFO] Download successful."
else
    echo "[ERROR] Failed to download yt-dlp binary from $DOWNLOAD_URL" >&2
    rm -f "$TEMP_FILE"
    exit 1
fi

# 6. Place the binary in the installation directory
echo "[INFO] Installing yt-dlp to ${INSTALL_DIR}/${BINARY_NAME}..."
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"
rm -f "$TEMP_FILE"
echo "[INFO] yt-dlp installed."

# 7. Verify installation
echo "[INFO] Verifying installation..."
if command -v $BINARY_NAME &> /dev/null; then
    INSTALLED_VERSION=$($BINARY_NAME --version)
    echo "[SUCCESS] yt-dlp version ${INSTALLED_VERSION} installed successfully to ${INSTALL_DIR}/${BINARY_NAME}"
else
    echo "[ERROR] yt-dlp command not found after installation. Check PATH or installation step." >&2
    exit 1
fi

# 8. Setup Automatic Daily Updates
echo "[INFO] Setting up automatic daily updates..."

# [ENHANCED] Create the dedicated update script with Discord notification logic
# The ${DISCORD_WEBHOOK_URL} variable from the prompt is passed directly into the script here.
cat << EOF > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
# This script is run by cron to update yt-dlp automatically.

# Exit on error, treat unset variables as error
set -eu

# --- Configuration ---
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
INSTALL_PATH="/usr/local/bin/yt-dlp"

# --- Function to send Discord notification ---
send_discord_notification() {
    local message="\$1"
    # Skip if webhook is not configured (is an empty string)
    if [ -z "\$DISCORD_WEBHOOK_URL" ]; then
        echo "Discord webhook URL not configured. Skipping notification."
        return
    fi
    
    # Construct a simple JSON payload with a formatted message
    JSON_PAYLOAD="{\\"content\\": null, \\"embeds\\": [{\\"title\\": \\"yt-dlp Auto-Update Status\\",\\"description\\": \\"\$message\\",\\"color\\": 5814783, \\"author\\": {\\"name\\": \\"Cron Job on \$(hostname)\\"}}], \\"username\\": \\"yt-dlp Updater\\", \\"avatar_url\\": \\"https://i.imgur.com/tH31Yxt.png\\"}"
    
    # Send notification using curl
    curl --silent --show-error -H "Content-Type: application/json" -X POST -d "\$JSON_PAYLOAD" "\$DISCORD_WEBHOOK_URL" || echo "[ERROR] Failed to send Discord notification."
}

# --- Main Update Logic ---
echo "--- Starting yt-dlp update check: \$(date) ---"

# Get current version before attempting update
if ! command -v \$INSTALL_PATH &> /dev/null; then
    echo "[ERROR] yt-dlp not found at \$INSTALL_PATH. Cannot update."
    send_discord_notification "🚨 **Update Failed!**\n\`yt-dlp\` not found at \$INSTALL_PATH."
    exit 1
fi
OLD_VERSION=\$("\$INSTALL_PATH" --version)
echo "Current version: \$OLD_VERSION"

# Download the latest yt-dlp to a temporary file
TEMP_FILE="/tmp/yt-dlp-update.\$\$"
echo "Downloading latest version..."
if ! curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "\$TEMP_FILE"; then
    echo "[ERROR] Download failed."
    rm -f "\$TEMP_FILE"
    send_discord_notification "🚨 **Update Failed!**\nCould not download the latest binary from GitHub."
    exit 1
fi

# Replace the old binary with the new one
install -m 755 "\$TEMP_FILE" "\$INSTALL_PATH"
rm -f "\$TEMP_FILE"

# Get new version after update
NEW_VERSION=\$("\$INSTALL_PATH" --version)
echo "New version: \$NEW_VERSION"

# Compare versions and send notification ONLY if it changed
if [ "\$OLD_VERSION" != "\$NEW_VERSION" ]; then
    echo "Update successful: \$OLD_VERSION -> \$NEW_VERSION"
    MESSAGE="✅ **yt-dlp was updated successfully!**\n\n**Host:** \`\$(hostname)\`\n**Old Version:** \`\$OLD_VERSION\`\n**New Version:** \`\$NEW_VERSION\`"
    send_discord_notification "\$MESSAGE"
else
    echo "yt-dlp is already up to date (version \$OLD_VERSION)."
fi

echo "--- Update check finished ---"
exit 0
EOF

# Make the update script executable
chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created update script at ${UPDATE_SCRIPT_PATH}"

# Create the cron job file to run the script at 8:30 PM (20:30)
echo "30 20 * * * root $UPDATE_SCRIPT_PATH >> $LOG_FILE 2>&1" > "$CRON_FILE_PATH"

echo "[SUCCESS] Cron job created at ${CRON_FILE_PATH}"
echo "[INFO] yt-dlp will now be updated automatically every day at 8:30 PM."
echo "[INFO] Update logs will be stored in ${LOG_FILE}"

echo "--- Installation and Auto-Update Setup Complete ---"
echo "[INFO] You can now run yt-dlp using the command: ${BINARY_NAME} [OPTIONS] URL"

exit 0
