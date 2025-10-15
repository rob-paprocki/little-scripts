#!/bin/bash

# --- Configuration ---
# Installation directory for the yt-dlp binary
INSTALL_DIR="/usr/local/bin"
# Name of the final executable
BINARY_NAME="yt-dlp"
# URL to download the latest stable yt-dlp binary
DOWNLOAD_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"

# --- Script Logic ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

echo "--- Comprehensive yt-dlp Installer for Debian-based Systems ---"
echo "--- Installs recommended dependencies (websocat excluded) ---"
# Use dynamic date command for script run time
echo "--- Script run time: $(date '+%Y-%m-%d %H:%M:%S %Z') ---"
# Removed static location line

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
   echo "[ERROR] This script must be run as root (or using sudo)." >&2
   exit 1
fi

# 2. Update package list
echo "[INFO] Updating package list..."
apt-get update

# 3. Install dependencies
# Removed websocat from the list below
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

echo "[INFO] Core, metadata, crypto, python-websockets, shell completion, and accelerator dependencies installed."

# 4. Download yt-dlp binary
echo "[INFO] Downloading latest yt-dlp binary from GitHub..."
# Use curl to download the file. -L follows redirects. -o specifies the output file.
# Download to a temporary location first.
TEMP_FILE="/tmp/${BINARY_NAME}"
if curl -L "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "[INFO] Download successful."
else
    echo "[ERROR] Failed to download yt-dlp binary from $DOWNLOAD_URL" >&2
    # Clean up temporary file if download failed partially
    rm -f "$TEMP_FILE"
    exit 1
fi

# 5. Place the binary in the installation directory
echo "[INFO] Installing yt-dlp to ${INSTALL_DIR}/${BINARY_NAME}..."
# Use install command which handles permissions and ownership better than mv
# -m sets the mode (permissions)
install -m 755 "$TEMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"

# Clean up the temporary file
rm -f "$TEMP_FILE"

echo "[INFO] yt-dlp installed."

# 6. Verify installation
echo "[INFO] Verifying installation..."
if command -v $BINARY_NAME &> /dev/null; then
    INSTALLED_VERSION=$($BINARY_NAME --version)
    echo "[SUCCESS] yt-dlp version ${INSTALLED_VERSION} installed successfully to ${INSTALL_DIR}/${BINARY_NAME}"
    echo "[INFO] Dependencies for metadata, crypto, WebSockets (via python3-websockets), Bash completion, and aria2c acceleration should now be available."
    echo "[INFO] You can now run yt-dlp using the command: ${BINARY_NAME} [OPTIONS] URL"
    echo "[INFO] Note: Bash completion may require restarting your shell session or running 'source ~/.bashrc'."
else
    echo "[ERROR] yt-dlp command not found after installation. Check PATH or installation step." >&2
    exit 1
fi

echo "--- Installation Complete ---"

exit 0
