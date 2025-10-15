#!/bin/bash

# --- Configuration ---
# Installation directory for the filebrowser binary
INSTALL_DIR="/usr/local/bin"
# Name of the final executable
BINARY_NAME="filebrowser"
# URL to download the latest stable filebrowser binary
DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser"
# Path for the separate update script
UPDATE_SCRIPT_PATH="/usr/local/bin/update-filebrowser.sh"
# Path for the cron job file
CRON_FILE_PATH="/etc/cron.d/filebrowser-updater"

# --- Script Logic ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

echo "--- Comprehensive File Browser Installer & Updater for Debian-based Systems ---"
echo "--- Installs the binary and sets up a daily update cron job ---"
echo "--- Script run time: $(date '+%Y-%m-%d %H:%M:%S %Z') ---"

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (or using sudo)." >&2
    exit 1
fi

# 2. Update package list and install required tools
echo "[INFO] Updating package list..."
apt-get update

echo "[INFO] Installing required tools (curl, ca-certificates)..."
apt-get install -y curl ca-certificates

# 3. Download filebrowser binary
echo "[INFO] Downloading latest File Browser binary from GitHub..."
# Use curl to download the file. -L follows redirects. -o specifies the output file.
# Download to a temporary location first.
TEMP_FILE="/tmp/${BINARY_NAME}"
if curl -L "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "[INFO] Download successful."
else
    echo "[ERROR] Failed to download File Browser binary from $DOWNLOAD_URL" >&2
    # Clean up temporary file if download failed partially
    rm -f "$TEMP_FILE"
    exit 1
fi

# 4. Place the binary in the installation directory
echo "[INFO] Installing File Browser to ${INSTALL_DIR}/${BINARY_NAME}..."
# Use install command which handles permissions and ownership better than mv
# -m sets the mode (permissions)
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"

# Clean up the temporary file
rm -f "$TEMP_FILE"

echo "[INFO] File Browser installed."

# 5. Verify installation
echo "[INFO] Verifying installation..."
if command -v $BINARY_NAME &> /dev/null; then
    # The 'version' command for filebrowser provides detailed output
    INSTALLED_VERSION=$($BINARY_NAME version | head -n 1)
    echo "[SUCCESS] File Browser ${INSTALLED_VERSION} installed successfully to ${INSTALL_DIR}/${BINARY_NAME}"
else
    echo "[ERROR] File Browser command not found after installation. Check PATH or installation step." >&2
    exit 1
fi

# 6. Setup Automatic Daily Updates
echo "[INFO] Setting up automatic daily updates..."

# Create the dedicated update script
cat << EOF > "$UPDATE_SCRIPT_PATH"
#!/bin/bash
# This script is run by cron to update File Browser automatically.

# Exit on error
set -e

# Download the latest filebrowser to a temporary file
TEMP_FILE="/tmp/filebrowser-update"
curl -L "https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser" -o "\$TEMP_FILE"

# Replace the old binary with the new one
install -m 755 "\$TEMP_FILE" "/usr/local/bin/filebrowser"

# Clean up
rm -f "\$TEMP_FILE"

exit 0
EOF

# Make the update script executable
chmod +x "$UPDATE_SCRIPT_PATH"
echo "[INFO] Created update script at ${UPDATE_SCRIPT_PATH}"

# Create the cron job file to run the script daily
# Runs at 3:25 AM every day. Output is sent to /dev/null to prevent cron emails.
echo "25 3 * * * root $UPDATE_SCRIPT_PATH >/dev/null 2>&1" > "$CRON_FILE_PATH"

echo "[SUCCESS] Cron job created at ${CRON_FILE_PATH}"
echo "[INFO] File Browser will now be updated automatically every day at 3:25 AM."

echo "--- Installation and Auto-Update Setup Complete ---"
echo "[INFO] You can now run File Browser using the command: ${BINARY_NAME} [OPTIONS]"

exit 0
