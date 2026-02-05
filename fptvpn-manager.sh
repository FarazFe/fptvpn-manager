#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="fptvpn-manager"
BIN_PATH="/usr/local/bin/${APP_NAME}"
CFG_DIR="/etc/fptvpn"
CFG_FILE="${CFG_DIR}/manager.conf"

RAW_INSTALL_URL="https://raw.githubusercontent.com/FarazFe/fptvpn-manager/main/fptvpn-manager.sh"

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

DEFAULT_BANDWIDTH_MBPS="100"
DEFAULT_EASY_USERNAME_PREFIX="fptn"

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
    *) echo "ERROR: curl not available and package manager unsupported." >&2; exit 1 ;;
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
  read -r -p "${label} [${def}]: " ans </dev/tty
  echo "${ans:-$def}"
}

fetch_public_ip() {
  ensure_curl
  curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null | tr -d ' \r\n' || true
}

write_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$content" > "$path"
}

save_manager_config() {
  mkdir -p "$CFG_DIR"
  write_file "$CFG_FILE" "$1"
}

load_install_dir() {
  if [ -f "$CFG_FILE" ]; then
    local d
    d="$(tr -d '\r\n' <"$CFG_FILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "$d" ]; then
      echo "$d"
      return 0
    fi
  fi
  echo "$DEFAULT_INSTALL_DIR"
}

dc() {
  local dir; dir="$(load_install_dir)"
  (cd "$dir" && docker compose "$@")
}

need_install_dir() {
  local dir; dir="$(load_install_dir)"
  if [ ! -f "${dir}/docker-compose.yml" ]; then
    echo "ERROR: Not installed yet. Run an install first." >&2
    return 1
  fi
  return 0
}

wait_for_container_ready() {
  local i
  for i in $(seq 1 90); do
    if dc exec -T fptn-server sh -c "true" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: fptn-server did not become ready in time." >&2
  return 1
}

env_get() {
  local key="$1"
  local dir; dir="$(load_install_dir)"
  local envfile="${dir}/.env"
  [ -f "$envfile" ] || return 1
  awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$envfile"
}

run_with_timeout() {
  local seconds="$1"; shift
  local pid killer rc

  ("$@") &
  pid=$!

  ( sleep "$seconds"; kill -TERM "$pid" >/dev/null 2>&1 || true ) &
  killer=$!

  wait "$pid" || rc=$?
  rc="${rc:-0}"

  kill "$killer" >/dev/null 2>&1 || true
  return "$rc"
}

read_secret_tty() {
  local prompt="$1"
  local var
  IFS= read -r -s -p "$prompt" var </dev/tty
  echo >/dev/tty
  printf "%s" "$var"
}

easy_username() {
  printf "%s%s" "$DEFAULT_EASY_USERNAME_PREFIX" "$(date +%H%M%S)"
}

# -------------------------
# Compose + Env
# -------------------------
write_compose() {
  local dir="$1"
  cat > "${dir}/docker-compose.yml" <<'YAML'
services:
  fptn-server:
    restart: unless-stopped
    image: fptnvpn/fptn-vpn-server:latest
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
      - NET_RAW
      - SYS_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
      - net.ipv4.conf.all.rp_filter=0
      - net.ipv4.conf.default.rp_filter=0
    ulimits:
      nproc:
        soft: 524288
        hard: 524288
      nofile:
        soft: 524288
        hard: 524288
      memlock:
        soft: 524288
        hard: 524288
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "${FPTN_PORT}:443/tcp"
    volumes:
      - ./fptn-server-data:/etc/fptn
    environment:
      - ENABLE_DETECT_PROBING=${ENABLE_DETECT_PROBING}
      - DEFAULT_PROXY_DOMAIN=${DEFAULT_PROXY_DOMAIN}
      - ALLOWED_SNI_LIST=${ALLOWED_SNI_LIST}
      - DISABLE_BITTORRENT=${DISABLE_BITTORRENT}
      - PROMETHEUS_SECRET_ACCESS_KEY=${PROMETHEUS_SECRET_ACCESS_KEY}
      - USE_REMOTE_SERVER_AUTH=${USE_REMOTE_SERVER_AUTH}
      - REMOTE_SERVER_AUTH_HOST=${REMOTE_SERVER_AUTH_HOST}
      - REMOTE_SERVER_AUTH_PORT=${REMOTE_SERVER_AUTH_PORT}
      - MAX_ACTIVE_SESSIONS_PER_USER=${MAX_ACTIVE_SESSIONS_PER_USER}
      - SERVER_EXTERNAL_IPS=${SERVER_EXTERNAL_IPS}
      - DNS_IPV4_PRIMARY=${DNS_IPV4_PRIMARY}
      - DNS_IPV4_SECONDARY=${DNS_IPV4_SECONDARY}
      - DNS_IPV6_PRIMARY=${DNS_IPV6_PRIMARY}
      - DNS_IPV6_SECONDARY=${DNS_IPV6_SECONDARY}
    healthcheck:
      test: ["CMD", "sh", "-c", "pgrep dnsmasq && pgrep fptn-server"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
YAML
}

write_env() {
  local dir="$1"
  local fptn_port="$2"
  local server_external_ips="$3"
  local proxy_domain="$4"
  local detect_probing="$5"
  local disable_bt="$6"
  local max_sessions="$7"
  local dns4_1="$8"
  local dns4_2="$9"
  local dns6_1="${10}"
  local dns6_2="${11}"

  write_file "$dir/.env" \
"FPTN_PORT=${fptn_port}
SERVER_EXTERNAL_IPS=${server_external_ips}
ENABLE_DETECT_PROBING=${detect_probing}
DEFAULT_PROXY_DOMAIN=${proxy_domain}
ALLOWED_SNI_LIST=
DISABLE_BITTORRENT=${disable_bt}
USE_REMOTE_SERVER_AUTH=false
REMOTE_SERVER_AUTH_HOST=
REMOTE_SERVER_AUTH_PORT=443
PROMETHEUS_SECRET_ACCESS_KEY=
MAX_ACTIVE_SESSIONS_PER_USER=${max_sessions}
DNS_IPV4_PRIMARY=${dns4_1}
DNS_IPV4_SECONDARY=${dns4_2}
DNS_IPV6_PRIMARY=${dns6_1}
DNS_IPV6_SECONDARY=${dns6_2}
"
}

# -------------------------
# SSL
# -------------------------
ssl_gen_if_missing() {
  ensure_docker_stack
  need_install_dir || return 1

  local dir; dir="$(load_install_dir)"
  mkdir -p "${dir}/fptn-server-data"

  if [ -f "${dir}/fptn-server-data/server.key" ] && [ -f "${dir}/fptn-server-data/server.crt" ]; then
    return 0
  fi

  dc run --rm fptn-server sh -c "cd /etc/fptn && openssl genrsa -out server.key 2048"
  dc run --rm fptn-server sh -c "cd /etc/fptn && openssl req -new -x509 -key server.key -out server.crt -days 365 -subj '/CN=fptn'"
}

ssl_fingerprint() {
  ensure_docker_stack
  need_install_dir || return 1
  dc run --rm fptn-server sh -c \
"openssl x509 -noout -fingerprint -md5 -in /etc/fptn/server.crt | cut -d'=' -f2 | tr -d ':' | tr 'A-F' 'a-f' | xargs -I {} echo 'MD5 Fingerprint: {}'"
}

# -------------------------
# User + Token
# -------------------------
delete_user_if_exists() {
  local username="$1"

  echo "[*] Removing existing user if present: ${username}"

  # fptn-passwd asks for confirmation; feed "y" and enforce a hard timeout.
  if has_cmd timeout; then
    printf "y\n" | timeout 10s dc exec -i -T fptn-server fptn-passwd --del-user "$username" >/dev/null 2>&1 || true
  else
    run_with_timeout 10 sh -c "printf 'y\n' | (cd \"$(load_install_dir)\" && docker compose exec -i -T fptn-server fptn-passwd --del-user \"$username\") >/dev/null 2>&1" || true
  fi
}

del_user_interactive() {
  local username="$1"
  local dir; dir="$(load_install_dir)"
  (cd "$dir" && docker compose exec -it fptn-server fptn-passwd --del-user "$username")
}

add_user_interactive() {
  local username="$1" bw="$2"
  local dir; dir="$(load_install_dir)"
  (cd "$dir" && docker compose exec -it fptn-server fptn-passwd --add-user "$username" --bandwidth "$bw")
}

generate_token_raw() {
  local username="$1" password="$2" server_ip="$3" server_port="$4"
  dc run --rm fptn-server token-generator \
    --user "$username" --password "$password" \
    --server-ip "$server_ip" --port "$server_port"
}

generate_token() {
  local username="$1" password="$2" server_ip="$3" server_port="$4"
  generate_token_raw "$username" "$password" "$server_ip" "$server_port" \
    | awk '/^fptn:/{print; found=1} END{exit (found?0:1)}'
}

print_token_block() {
  local token="$1"
  echo
  echo "================ TOKEN ================"
  echo "$token"
  echo "======================================="
}

# -------------------------
# Install flows
# -------------------------
easy_install() {
  ensure_docker_stack

  local dir="$DEFAULT_INSTALL_DIR"
  save_manager_config "$dir"
  mkdir -p "$dir"

  local server_external_ips
  server_external_ips="$(fetch_public_ip || true)"

  write_compose "$dir"
  write_env "$dir" \
    "$DEFAULT_FPTN_PORT" \
    "$server_external_ips" \
    "$DEFAULT_PROXY_DOMAIN" \
    "$DEFAULT_ENABLE_DETECT_PROBING" \
    "$DEFAULT_DISABLE_BITTORRENT" \
    "$DEFAULT_MAX_ACTIVE_SESSIONS_PER_USER" \
    "$DEFAULT_DNS_IPV4_PRIMARY" \
    "$DEFAULT_DNS_IPV4_SECONDARY" \
    "$DEFAULT_DNS_IPV6_PRIMARY" \
    "$DEFAULT_DNS_IPV6_SECONDARY"

  if [ -z "$server_external_ips" ]; then
    echo "[!] Warning: Could not auto-detect public IP. You may need to edit SERVER_EXTERNAL_IPS in $dir/.env" >&2
  fi

  echo "[*] Generating SSL certs (if missing)..."
  ssl_gen_if_missing

  echo "[*] Starting server..."
  dc up -d

  echo "[*] Waiting for fptn-server to be ready..."
  wait_for_container_ready

  echo
  ssl_fingerprint || true

  echo
  echo "[*] Server status:"
  dc ps || true

  local username password server_ip server_port token installed_port
  username="$(easy_username)"

  server_ip="$(fetch_public_ip || true)"
  installed_port="$(env_get FPTN_PORT 2>/dev/null || true)"
  server_port="${installed_port:-$DEFAULT_FPTN_PORT}"

  echo
  echo "[*] Creating easy VPN user (new each run): ${username}"
  echo "[!] You will now be prompted INSIDE the container to set the password for '${username}'."
  echo
  add_user_interactive "$username" "$DEFAULT_BANDWIDTH_MBPS"

  echo
  password="$(read_secret_tty "[*] Re-enter the SAME password to generate token: ")"

  if [ -z "${server_ip:-}" ]; then
    server_ip="YOUR_SERVER_PUBLIC_IP"
  fi

  echo
  echo "[!] Easy user credentials (save these):"
  echo "    Username: ${username}"
  echo "    Password: ${password}"

  token="$(generate_token "$username" "$password" "$server_ip" "$server_port" || true)"
  if [ -n "${token:-}" ]; then
    print_token_block "$token"
  else
    echo
    echo "[!] Token generation failed. Raw generator output:"
    generate_token_raw "$username" "$password" "$server_ip" "$server_port" || true
  fi

  echo
  echo "[+] Easy install complete."
}

custom_install() {
  ensure_docker_stack

  local dir fptn_port proxy_domain detect_probing disable_bt max_sessions
  local dns4_1 dns4_2 dns6_1 dns6_2
  local username password bw server_ip server_port server_external_ips token

  dir="$(prompt_default "Install directory" "$DEFAULT_INSTALL_DIR")"
  fptn_port="$(prompt_default "FPTN_PORT (host port)" "$DEFAULT_FPTN_PORT")"
  server_external_ips="$(prompt_default "SERVER_EXTERNAL_IPS (comma-separated, optional)" "$(fetch_public_ip || true)")"
  proxy_domain="$(prompt_default "DEFAULT_PROXY_DOMAIN" "$DEFAULT_PROXY_DOMAIN")"
  detect_probing="$(prompt_default "ENABLE_DETECT_PROBING (true/false)" "$DEFAULT_ENABLE_DETECT_PROBING")"
  disable_bt="$(prompt_default "DISABLE_BITTORRENT (true/false)" "$DEFAULT_DISABLE_BITTORRENT")"
  max_sessions="$(prompt_default "MAX_ACTIVE_SESSIONS_PER_USER" "$DEFAULT_MAX_ACTIVE_SESSIONS_PER_USER")"
  dns4_1="$(prompt_default "DNS_IPV4_PRIMARY" "$DEFAULT_DNS_IPV4_PRIMARY")"
  dns4_2="$(prompt_default "DNS_IPV4_SECONDARY" "$DEFAULT_DNS_IPV4_SECONDARY")"
  dns6_1="$(prompt_default "DNS_IPV6_PRIMARY" "$DEFAULT_DNS_IPV6_PRIMARY")"
  dns6_2="$(prompt_default "DNS_IPV6_SECONDARY" "$DEFAULT_DNS_IPV6_SECONDARY")"

  IFS= read -r -p "VPN Username: " username </dev/tty
  bw="$(prompt_default "Bandwidth Mbps" "$DEFAULT_BANDWIDTH_MBPS")"

  server_ip="$(prompt_default "Server public IP" "$(fetch_public_ip || true)")"
  server_port="$(prompt_default "Server public port" "$fptn_port")"

  save_manager_config "$dir"
  mkdir -p "$dir"

  write_compose "$dir"
  write_env "$dir" \
    "$fptn_port" \
    "$server_external_ips" \
    "$proxy_domain" \
    "$detect_probing" \
    "$disable_bt" \
    "$max_sessions" \
    "$dns4_1" "$dns4_2" "$dns6_1" "$dns6_2"

  echo "[*] Generating SSL certs (if missing)..."
  ssl_gen_if_missing

  echo "[*] Starting server..."
  dc up -d

  echo "[*] Waiting for fptn-server to be ready..."
  wait_for_container_ready

  echo
  ssl_fingerprint || true

  echo
  echo "[*] Creating VPN user (will overwrite if exists): ${username}"
  delete_user_if_exists "$username"

  echo
  echo "[!] You will now be prompted INSIDE the container to set the password for '${username}'."
  echo
  add_user_interactive "$username" "$bw"

  echo
  password="$(read_secret_tty "[*] Re-enter the SAME password to generate token: ")"

  token="$(generate_token "$username" "$password" "$server_ip" "$server_port" || true)"
  if [ -n "${token:-}" ]; then
    print_token_block "$token"
  else
    echo
    echo "[!] Token generation failed. Raw generator output:"
    generate_token_raw "$username" "$password" "$server_ip" "$server_port" || true
  fi

  echo
  echo "[+] Custom install complete."
}

# -------------------------
# Menu actions
# -------------------------
do_start()  { ensure_docker_stack; need_install_dir || return 1; dc up -d; }
do_stop()   { ensure_docker_stack; need_install_dir || return 1; dc down; }
do_status() { ensure_docker_stack; need_install_dir || return 1; dc ps; }
do_logs()   { ensure_docker_stack; need_install_dir || return 1; dc logs -f --tail=200; }
do_update() { ensure_docker_stack; need_install_dir || return 1; dc pull; dc up -d; }

menu_add_user_and_token() {
  ensure_docker_stack
  need_install_dir || return 1

  echo "[*] Waiting for fptn-server to be ready..."
  wait_for_container_ready

  local username password bw server_ip server_port token installed_port
  IFS= read -r -p "Username: " username </dev/tty
  bw="$(prompt_default "Bandwidth Mbps" "$DEFAULT_BANDWIDTH_MBPS")"

  installed_port="$(env_get FPTN_PORT 2>/dev/null || true)"
  server_ip="$(prompt_default "Server public IP" "$(fetch_public_ip || true)")"
  server_port="$(prompt_default "Server public port" "${installed_port:-$DEFAULT_FPTN_PORT}")"

  echo
  echo "[*] Creating VPN user (will overwrite if exists): ${username}"
  delete_user_if_exists "$username"

  echo
  echo "[!] You will now be prompted INSIDE the container to set the password for '${username}'."
  echo
  add_user_interactive "$username" "$bw"

  echo
  password="$(read_secret_tty "[*] Re-enter the SAME password to generate token: ")"

  token="$(generate_token "$username" "$password" "$server_ip" "$server_port" || true)"
  if [ -n "${token:-}" ]; then
    print_token_block "$token"
  else
    echo "[!] Token generation failed. Raw generator output:"
    generate_token_raw "$username" "$password" "$server_ip" "$server_port" || true
  fi
  echo
  echo "[+] Done."
}

menu_token_only() {
  ensure_docker_stack
  need_install_dir || return 1

  echo "[*] Waiting for fptn-server to be ready..."
  wait_for_container_ready

  local username password server_ip server_port token installed_port reset_choice

  IFS= read -r -p "Username: " username </dev/tty

  echo
  echo "Generate token for existing user '${username}'."
  echo "If you're not 100% sure about the password, choose YES to reset it now (recommended)."
  read -r -p "Reset password now? (y/N): " reset_choice </dev/tty

  if [[ "${reset_choice,,}" == "y" || "${reset_choice,,}" == "yes" ]]; then
    echo
    echo "[*] Resetting user: ${username}"
    echo "[!] Deleting user inside the container (you may need to confirm)."
    echo
    del_user_interactive "$username" || true

    echo
    echo "[!] Now you'll be prompted to set a NEW password for '${username}'."
    echo
    add_user_interactive "$username" "$DEFAULT_BANDWIDTH_MBPS"

    echo
    password="$(read_secret_tty "[*] Re-enter the SAME password to generate token: ")"
  else
    password="$(read_secret_tty "Password: ")"
  fi

  installed_port="$(env_get FPTN_PORT 2>/dev/null || true)"
  server_ip="$(prompt_default "Server public IP" "$(fetch_public_ip || true)")"
  server_port="$(prompt_default "Server public port" "${installed_port:-$DEFAULT_FPTN_PORT}")"

  token="$(generate_token "$username" "$password" "$server_ip" "$server_port" || true)"
  if [ -n "${token:-}" ]; then
    print_token_block "$token"
    echo
    echo "[*] If the client still says 'wrong password', re-run this option and choose YES to reset the password."
  else
    echo
    echo "[!] Token generation failed. Raw generator output:"
    generate_token_raw "$username" "$password" "$server_ip" "$server_port" || true
  fi
}

# -------------------------
# Self-install
# -------------------------
install_self() {
  require_root

  # If we are already running from the installed location, don't reinstall.
  if [ -e "$BIN_PATH" ] && [ "$(readlink -f "$0" 2>/dev/null || echo "$0")" = "$(readlink -f "$BIN_PATH" 2>/dev/null || echo "$BIN_PATH")" ]; then
    return 0
  fi

  # If run via pipe (curl | bash), don't attempt self-install.
  if [[ "${0##*/}" == "bash" || "${0##*/}" == "-bash" || "$0" == "-" ]]; then
    cat <<EOF
NOTE:
You ran this via pipe (curl | bash), so it can't self-install reliably.
Use this instead:

curl -fsSL ${RAW_INSTALL_URL} -o /tmp/${APP_NAME} && sudo bash /tmp/${APP_NAME}

EOF
    exit 0
  fi

  # Normal self-install
  if [ -f "$0" ]; then
    install -m 0755 "$0" "$BIN_PATH"
    echo "[*] Installed command: $BIN_PATH"
    return 0
  fi

  echo "ERROR: Cannot locate script path for self-install." >&2
  exit 1
}

# -------------------------
# Main menu
# -------------------------
menu() {
  while true; do
    echo
    echo "FPTVPN Manager (${APP_NAME})"
    echo "============================"
    echo "Install dir: $(load_install_dir)"
    echo
    echo "1) Easy install (creates a NEW user each run + token)"
    echo "2) Custom install (configure + user + token)"
    echo "3) Start service"
    echo "4) Stop service"
    echo "5) Show status"
    echo "6) View logs"
    echo "7) Update (pull latest image)"
    echo "8) SSL: Generate certs (if missing)"
    echo "9) SSL: Show MD5 fingerprint"
    echo "10) Add VPN user (prints token)"
    echo "11) Generate token (existing user / reset password)"
    echo "0) Exit"
    echo
    read -r -p "Select: " c </dev/tty
    case "$c" in
      1) easy_install ;;
      2) custom_install ;;
      3) do_start ;;
      4) do_stop ;;
      5) do_status ;;
      6) do_logs ;;
      7) do_update ;;
      8) ensure_docker_stack; need_install_dir || true; ssl_gen_if_missing ;;
      9) ensure_docker_stack; need_install_dir || true; ssl_fingerprint ;;
      10) menu_add_user_and_token ;;
      11) menu_token_only ;;
      0) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
  done
}

install_self
menu
