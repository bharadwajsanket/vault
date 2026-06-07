#!/bin/bash
set -e

# Vault Installer
# Downloads and installs the latest Vault binary for your platform
# Usage: curl -fsSL https://raw.githubusercontent.com/bharadwajsanket/vault/main/install.sh | sh

VAULT_VERSION="${VAULT_VERSION:-latest}"
VAULT_INSTALL_DIR="${VAULT_INSTALL_DIR:-/usr/local/bin}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-$HOME/.vault}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS and architecture
detect_platform() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$OS" in
    darwin)
      OS="darwin"
      ;;
    linux)
      OS="linux"
      ;;
    *)
      echo -e "${RED}Unsupported OS: $OS${NC}"
      exit 1
      ;;
  esac

  case "$ARCH" in
    x86_64|amd64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    armv7l|armv7)
      ARCH="armv7"
      ;;
    *)
      echo -e "${RED}Unsupported architecture: $ARCH${NC}"
      exit 1
      ;;
  esac

  echo -e "${GREEN}Detected platform: ${OS}_${ARCH}${NC}"
}

# Get the latest release version if not specified
get_latest_version() {
  if [ "$VAULT_VERSION" = "latest" ]; then
    api_response=$(curl -sSL "https://api.github.com/repos/bharadwajsanket/vault/releases/latest")
    VAULT_VERSION=$(printf '%s' "$api_response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -z "$VAULT_VERSION" ]; then
      echo -e "${RED}No GitHub release found or API request failed.${NC}"
      echo -e "${YELLOW}Please create a release before using install.sh.${NC}"
      echo -e "${YELLOW}GitHub API response:${NC} $(printf '%s' "$api_response" | head -3)"
      exit 1
    fi
  fi
  echo -e "${GREEN}Using Vault version: ${VAULT_VERSION}${NC}"
}

# Download the binary
download_binary() {
  ARCHIVE_NAME="vault-${OS}-${ARCH}.tar.gz"
  DOWNLOAD_URL="https://github.com/bharadwajsanket/vault/releases/download/${VAULT_VERSION}/${ARCHIVE_NAME}"
  TEMP_DIR=$(mktemp -d)
  BINARY_PATH="${TEMP_DIR}/vault"

  echo -e "${YELLOW}Downloading from: ${DOWNLOAD_URL}${NC}"
  http_status=$(curl -sSL -w '%{http_code}' -o "${TEMP_DIR}/vault.tar.gz" "$DOWNLOAD_URL")

  if [ "$http_status" != "200" ]; then
    if [ "$http_status" = "404" ]; then
      echo -e "${RED}Expected asset not found:${NC} ${DOWNLOAD_URL}"
      echo -e "${YELLOW}Make sure the release contains a tarball named: ${ARCHIVE_NAME}${NC}"
    else
      echo -e "${RED}Failed to download Vault binary (HTTP ${http_status}).${NC}"
    fi
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  cd "$TEMP_DIR"
  if ! tar -xzf vault.tar.gz; then
    echo -e "${RED}Failed to extract downloaded archive.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${RED}Binary not found in archive${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  chmod +x "$BINARY_PATH"
  echo -e "${GREEN}Binary downloaded and extracted${NC}"
}

# Install the binary
install_binary() {
  if [ ! -w "$VAULT_INSTALL_DIR" ]; then
    echo -e "${YELLOW}Installing to $VAULT_INSTALL_DIR requires sudo${NC}"
    sudo cp "$BINARY_PATH" "${VAULT_INSTALL_DIR}/vault"
    sudo chmod +x "${VAULT_INSTALL_DIR}/vault"
  else
    cp "$BINARY_PATH" "${VAULT_INSTALL_DIR}/vault"
    chmod +x "${VAULT_INSTALL_DIR}/vault"
  fi
  
  echo -e "${GREEN}Vault installed to ${VAULT_INSTALL_DIR}/vault${NC}"
}

# Create data directory
setup_data_dir() {
  mkdir -p "$VAULT_DATA_DIR"
  echo -e "${GREEN}Data directory created at ${VAULT_DATA_DIR}${NC}"
}

# Optional: Setup systemd service
setup_systemd() {
  echo -e "${YELLOW}Would you like to setup a systemd service? (y/n)${NC}"
  read -r -n 1 -t 10 RESPONSE || RESPONSE="n"
  echo

  if [ "$RESPONSE" != "y" ] && [ "$RESPONSE" != "Y" ]; then
    echo -e "${YELLOW}Skipping systemd setup${NC}"
    return
  fi

  SERVICE_FILE="/etc/systemd/system/vault.service"
  SERVICE_CONTENT="[Unit]
Description=Vault - Web File Browser
After=network.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${VAULT_DATA_DIR}
ExecStart=${VAULT_INSTALL_DIR}/vault -r ${VAULT_DATA_DIR} -d ${VAULT_DATA_DIR}/vault.db
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
"

  if [ ! -w "$SERVICE_FILE" ] 2>/dev/null; then
    echo -e "${YELLOW}Creating systemd service requires sudo${NC}"
    echo "$SERVICE_CONTENT" | sudo tee "$SERVICE_FILE" > /dev/null
    sudo systemctl daemon-reload
    echo -e "${GREEN}Systemd service created${NC}"
    echo -e "${YELLOW}Start the service with: sudo systemctl start vault${NC}"
    echo -e "${YELLOW}Enable on boot with: sudo systemctl enable vault${NC}"
  else
    echo "$SERVICE_CONTENT" > "$SERVICE_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}Systemd service created${NC}"
  fi
}

# Cleanup
cleanup() {
  rm -rf "$TEMP_DIR"
}

# Main installation flow
main() {
  echo -e "${GREEN}=== Vault Installer ===${NC}"
  
  detect_platform
  get_latest_version
  download_binary
  install_binary
  setup_data_dir
  setup_systemd
  cleanup

  echo ""
  echo -e "${GREEN}=== Installation Complete ===${NC}"
  echo -e "${GREEN}Vault is ready to use!${NC}"
  echo ""
  echo "Quick start:"
  echo "  vault -r $VAULT_DATA_DIR"
  echo ""
  echo "Then open http://127.0.0.1:8080 in your browser"
}

trap cleanup EXIT
main
