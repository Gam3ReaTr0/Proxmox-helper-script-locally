#!/usr/bin/env bash
set -euo pipefail

APP_NAME="proxmox-helper-local"
SERVICE_NAME="$APP_NAME"
DEFAULT_BRANCH="main"
DEFAULT_INSTALL_DIR="/opt/$APP_NAME"
ENV_FILE="/etc/default/$APP_NAME"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-$DEFAULT_BRANCH}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
PORT="${PORT:-3000}"
PROXMOX_HOST_IP="${PROXMOX_HOST_IP:-192.168.8.12}"
SETUP_SERVICE=1

log() {
  printf "\n[setup] %s\n" "$*"
}

fail() {
  printf "\n[setup] Error: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  sudo bash setup.sh [options]

Options:
  --repo <git-url>    Git repo to clone or update
  --dir <path>        Install directory (default: /opt/proxmox-helper-local)
  --branch <name>     Git branch (default: main)
  --host <address>    Default Proxmox host IP/hostname (default: 192.168.8.12)
  --port <port>       App port (default: 3000)
  --no-service        Install only, do not create/start systemd service
  -h, --help          Show this help

Examples:
  sudo bash setup.sh --host 192.168.8.12
  sudo bash setup.sh --repo https://github.com/you/repo.git --host 192.168.8.12
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || fail "Missing value for --repo"
      REPO_URL="$2"
      shift 2
      ;;
    --dir)
      [[ $# -ge 2 ]] || fail "Missing value for --dir"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || fail "Missing value for --branch"
      BRANCH="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || fail "Missing value for --host"
      PROXMOX_HOST_IP="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || fail "Missing value for --port"
      PORT="$2"
      shift 2
      ;;
    --no-service)
      SETUP_SERVICE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] || fail "Port must be numeric"
(( PORT >= 1 && PORT <= 65535 )) || fail "Port must be between 1 and 65535"

if [[ $EUID -ne 0 ]]; then
  fail "Run this script with sudo or as root"
fi

if ! command -v apt-get >/dev/null 2>&1; then
  fail "This setup script currently supports Debian/Ubuntu systems with apt-get"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO_SOURCE=0

if [[ -z "$REPO_URL" && -f "$SCRIPT_DIR/server.js" && -f "$SCRIPT_DIR/public/index.html" ]]; then
  LOCAL_REPO_SOURCE=1
  INSTALL_DIR="$SCRIPT_DIR"
fi

install_packages() {
  log "Installing system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    git \
    build-essential \
    python3 \
    nodejs \
    npm
}

sync_repo() {
  if (( LOCAL_REPO_SOURCE )); then
    log "Using the current repository at $INSTALL_DIR"
    return
  fi

  [[ -n "$REPO_URL" ]] || fail "Provide --repo when running setup.sh outside the repository folder"

  if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
    fail "Install directory exists and is not a git checkout: $INSTALL_DIR"
  fi

  mkdir -p "$(dirname "$INSTALL_DIR")"

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Updating existing checkout in $INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch origin "$BRANCH"
    git -C "$INSTALL_DIR" checkout "$BRANCH"
    git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
  else
    log "Cloning $REPO_URL into $INSTALL_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
  fi
}

install_node_modules() {
  log "Installing Node dependencies"
  cd "$INSTALL_DIR"
  npm install --omit=dev --no-audit --no-fund --unsafe-perm
}

write_env_file() {
  log "Writing environment file to $ENV_FILE"
  cat > "$ENV_FILE" <<EOF
PORT=$PORT
PROXMOX_HOST_IP=$PROXMOX_HOST_IP
NODE_ENV=production
EOF
}

write_service_file() {
  log "Writing systemd service to $SERVICE_FILE"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Proxmox Helper Local
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=-$ENV_FILE
ExecStart=/usr/bin/env npm start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
  command -v systemctl >/dev/null 2>&1 || fail "systemctl is not available on this system"
  log "Enabling and starting $SERVICE_NAME"
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

print_summary() {
  log "Setup complete"
  printf "\nApp directory: %s\n" "$INSTALL_DIR"
  printf "Port: %s\n" "$PORT"
  printf "Default Proxmox host: %s\n" "$PROXMOX_HOST_IP"

  if (( SETUP_SERVICE )); then
    printf "Service: %s\n" "$SERVICE_NAME"
    printf "Status command: systemctl status %s\n" "$SERVICE_NAME"
  else
    printf "Start command: cd %s && PORT=%s PROXMOX_HOST_IP=%s npm start\n" "$INSTALL_DIR" "$PORT" "$PROXMOX_HOST_IP"
  fi

  printf "Open: http://YOUR_SERVER_IP:%s\n" "$PORT"
}

install_packages
sync_repo
install_node_modules

if (( SETUP_SERVICE )); then
  write_env_file
  write_service_file
  start_service
fi

print_summary
