#!/usr/bin/env bash
set -Eeuo pipefail

# ==================================
# FPTVPN Manager – fptvpn-manager-manager
# ==================================

APP_NAME="fptvpn-manager"
BIN_PATH="/usr/local/bin/${APP_NAME}"
CFG_DIR="/etc/fptvpn"
CFG_FILE="${CFG_DIR}/manager.conf"

# UPDATE THIS after publishing
RAW_INSTALL_URL="https://raw.githubusercontent.com/YOUR_ORG/fptvpn-manager/main/fptvpn-manager.sh"

# -------------------------
# Defaults
# -------------------------
DEFAULT_INSTALL_DIR="/opt/fptn"
DEFAULT_FPTN_PORT="443"
DEFAULT_PROXY_DOMAIN="cdnvideo.com"
DEFAULT_ENABLE_DETECT_PROBING="true"
DEFAULT_DISABLE_BITTORRENT="true"
DEFAULT_MAX_ACTIVE_SESSIONS_PER_USER="3"

DEFAULT_DNS_IPV4_PRIMARY="8.8.8.8"
DEFAULT_DNS_IPV4_SECONDARY="8.8.4.4"
DEFAULT_DNS_IPV6_PRIMARY="2001:4860:4860::8888"
DEFAULT_DNS_IPV6_SECONDARY="2001:4860:4860::8844"

# -------------------------
# Helpers
# -------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo)." >&2
    exit 1
  fi
}

detect_pkg_mgr() {
  if has_cmd apt-get; then echo "apt"
  elif has_cmd dnf; then echo "dnf"
  elif has_cmd yum; then echo "yum"
  else echo "unknown"
  fi
}

ensure_curl() {
  has_cmd curl && return
  local pm; pm="$(detect_pkg_mgr)"
  echo "[*] Installing curl..."
  case "$pm" in
    apt) apt-get update -y && apt-get install -y curl ;;
    dnf) dnf install -y curl ;;
    yum) yum install -y curl ;;
    *) echo "ERROR: curl not available." >&2; exit 1 ;;
  esac
}

start_enable_docker() {
  systemctl enable --now docker >/dev/null 2>&1 || service docker start || true
}

ensure_docker() {
  has_cmd docker && return
  echo "[*] Installing Docker..."
  ensure_curl
  curl -fsSL https://get.docker.com | sh
  start_enable_docker
}

ensure_compose() {
  docker compose version >/dev/null 2>&1 && return
  echo "[*] Installing Docker Compose v2..."
  local pm; pm="$(detect_pkg_mgr)"
  case "$pm" in
    apt) apt-get update -y && apt-get install -y docker-compose-plugin ;;
    dnf|yum) $pm install -y docker-compose-plugin ;;
    *) echo "ERROR: Docker Compose v2 not available." >&2; exit 1 ;;
  esac
}

ensure_docker_stack() {
  require_root
  ensure_docker
  ensure_compose
}

prompt_default() {
  local label="$1" def="$2" ans
  read -r -p "${label} [${def}]: " ans
  echo "${ans:-$def}"
}

fetch_public_ip() {
  curl -fsS https://api.ipify.org 2>/dev/null || true
}

prompt_server_external_ips() {
  echo
  echo "Press Enter to auto-detect your public IP."
  read -r -p "SERVER_EXTERNAL_IPS: " ans
  if [ -z "$ans" ]; then
    ans="$(fetch_public_ip)"
    echo "[*] Detected public IP: $ans"
  fi
  echo "$ans"
}

write_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$content" > "$path"
}

save_manager_config() {
  write_file "$CFG_FILE" "INSTALL_DIR=\"$1\""
}

load_install_dir() {
  [ -f "$CFG_FILE" ] && source "$CFG_FILE"
  echo "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
}

# -------------------------
# Install logic
# -------------------------
write_env() {
  local dir="$1" ip="$2"
  write_file "$dir/.env" "
FPTN_PORT=${DEFAULT_FPTN_PORT}
SERVER_EXTERNAL_IPS=${ip}
DEFAULT_PROXY_DOMAIN=${DEFAULT_PROXY_DOMAIN}
ENABLE_DETECT_PROBING=${DEFAULT_ENABLE_DETECT_PROBING}
DISABLE_BITTORRENT=${DEFAULT_DISABLE_BITTORRENT}
MAX_ACTIVE_SESSIONS_PER_USER=${DEFAULT_MAX_ACTIVE_SESSIONS_PER_USER}
DNS_IPV4_PRIMARY=${DEFAULT_DNS_IPV4_PRIMARY}
DNS_IPV4_SECONDARY=${DEFAULT_DNS_IPV4_SECONDARY}
DNS_IPV6_PRIMARY=${DEFAULT_DNS_IPV6_PRIMARY}
DNS_IPV6_SECONDARY=${DEFAULT_DNS_IPV6_SECONDARY}
"
}

write_compose() {
  local dir="$1"
  write_file "$dir/docker-compose.yml" '
services:
  fptn-server:
    image: fptnvpn/fptn-vpn-server:latest
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    ports:
      - "${FPTN_PORT}:443"
    volumes:
      - ./fptn-server-data:/etc/fptn
    env_file: .env
'
}

easy_install() {
  ensure_docker_stack
  local dir="$DEFAULT_INSTALL_DIR"
  local ip
  ip="$(prompt_server_external_ips)"

  echo "[*] Installing to $dir"
  save_manager_config "$dir"
  write_env "$dir" "$ip"
  write_compose "$dir"

  (cd "$dir" && docker compose up -d)

  echo
  echo "[+] FPTN VPN server installed successfully."
  echo "[+] Use '${APP_NAME}' to manage the service."
}

# -------------------------
# Self-install logic
# -------------------------
install_self() {
  require_root

  if [ -f "$0" ] && [[ "$0" != "bash" ]]; then
    install -m 0755 "$0" "$BIN_PATH"
    echo "[*] Installed command: $BIN_PATH"
    return
  fi

  cat <<EOF
NOTE:
This script was run via pipe (curl | bash).
For a permanent install, use:

curl -fsSL ${RAW_INSTALL_URL} -o /tmp/${APP_NAME} && sudo bash /tmp/${APP_NAME}
EOF
}

# -------------------------
# Menu
# -------------------------
menu() {
  while true; do
    echo
    echo "FPTVPN Manager"
    echo "=============="
    echo "1) Easy install (recommended)"
    echo "2) Start service"
    echo "3) Stop service"
    echo "4) Show status"
    echo "0) Exit"
    echo
    read -r -p "Select: " c
    case "$c" in
      1) easy_install ;;
      2) (cd "$(load_install_dir)" && docker compose up -d) ;;
      3) (cd "$(load_install_dir)" && docker compose down) ;;
      4) (cd "$(load_install_dir)" && docker compose ps) ;;
      0) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
  done
}

install_self
menu
