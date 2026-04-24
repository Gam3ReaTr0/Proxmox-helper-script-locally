#!/usr/bin/env bash
set -euo pipefail

APP_NAME="proxmox-helper-local"
DEFAULT_BRANCH="main"
DEFAULT_INSTALL_DIR="/opt/$APP_NAME"
DEFAULT_PORT=3000
DEFAULT_PROXMOX_HOST_IP="192.168.8.12"
DEFAULT_NODE_MAJOR=20
DEFAULT_REPO_URL="https://github.com/Gam3ReaTr0/Proxmox-helper-script-locally.git"

DEFAULT_LXC_NAME="$APP_NAME"
DEFAULT_LXC_MEMORY=2048
DEFAULT_LXC_CORES=2
DEFAULT_LXC_DISK=8
DEFAULT_LXC_BRIDGE="vmbr0"
DEFAULT_LXC_TEMPLATE_STORAGE=""

MODE="${MODE:-auto}"
REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
BRANCH="${BRANCH:-$DEFAULT_BRANCH}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
PORT="${PORT:-$DEFAULT_PORT}"
PROXMOX_HOST_IP="${PROXMOX_HOST_IP:-}"
NODE_MAJOR="${NODE_MAJOR:-$DEFAULT_NODE_MAJOR}"

LXC_ID="${LXC_ID:-}"
LXC_NAME="${LXC_NAME:-$DEFAULT_LXC_NAME}"
LXC_STORAGE="${LXC_STORAGE:-}"
LXC_TEMPLATE_STORAGE="${LXC_TEMPLATE_STORAGE:-$DEFAULT_LXC_TEMPLATE_STORAGE}"
LXC_TEMPLATE="${LXC_TEMPLATE:-}"
LXC_MEMORY="${LXC_MEMORY:-$DEFAULT_LXC_MEMORY}"
LXC_CORES="${LXC_CORES:-$DEFAULT_LXC_CORES}"
LXC_DISK="${LXC_DISK:-$DEFAULT_LXC_DISK}"
LXC_BRIDGE="${LXC_BRIDGE:-$DEFAULT_LXC_BRIDGE}"
LXC_IP="${LXC_IP:-dhcp}"
LXC_GATEWAY="${LXC_GATEWAY:-}"
HOST_ARG_SET=0
LXC_IP_ARG_SET=0
SETUP_UI_TITLE="Proxmox Helper Local Setup"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO_SOURCE=0

log() {
  printf "\n[setup] %s\n" "$*" >&2
}

warn() {
  printf "\n[setup] Warning: %s\n" "$*" >&2
}

fail() {
  printf "\n[setup] Error: %s\n" "$*" >&2
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

is_valid_ipv4() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

is_valid_ipv4_cidr() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]
}

can_prompt() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

use_whiptail_ui() {
  can_prompt && has_command whiptail
}

ensure_prompt_ui() {
  if ! can_prompt || has_command whiptail || ! has_command apt-get; then
    return
  fi

  log "Installing whiptail for the setup wizard"
  export DEBIAN_FRONTEND=noninteractive
  if ! apt-get update >/dev/null 2>&1; then
    warn "Could not refresh apt metadata for whiptail; falling back to plain prompts"
    return
  fi

  if ! apt-get install -y whiptail >/dev/null 2>&1; then
    warn "Could not install whiptail; falling back to plain prompts"
  fi
}

prompt_with_default() {
  local prompt="$1"
  local default_value="${2:-}"
  local value=""

  if use_whiptail_ui; then
    if ! value="$(whiptail --title "$SETUP_UI_TITLE" --inputbox "$prompt" 11 78 "$default_value" 3>&1 1>&2 2>&3)"; then
      fail "Setup was canceled"
    fi
    printf "%s\n" "$value"
    return
  fi

  if ! can_prompt; then
    printf "%s\n" "$default_value"
    return
  fi

  if [[ -n "$default_value" ]]; then
    printf "[setup] %s [%s]: " "$prompt" "$default_value" > /dev/tty
  else
    printf "[setup] %s: " "$prompt" > /dev/tty
  fi

  IFS= read -r value < /dev/tty || value=""
  if [[ -z "$value" ]]; then
    value="$default_value"
  fi

  printf "%s\n" "$value"
}

prompt_yes_no() {
  local prompt="$1"
  local default_answer="${2:-y}"
  local default_label="Y/n"
  local reply=""

  if [[ "${default_answer,,}" == "n" ]]; then
    default_label="y/N"
  fi

  if use_whiptail_ui; then
    if [[ "${default_answer,,}" == "n" ]]; then
      if whiptail --title "$SETUP_UI_TITLE" --defaultno --yesno "$prompt" 10 72; then
        return 0
      fi
    else
      if whiptail --title "$SETUP_UI_TITLE" --yesno "$prompt" 10 72; then
        return 0
      fi
    fi

    case $? in
      1) return 1 ;;
      255) fail "Setup was canceled" ;;
      *) return 1 ;;
    esac
  fi

  if ! can_prompt; then
    [[ "${default_answer,,}" == "y" ]]
    return
  fi

  while true; do
    printf "[setup] %s [%s]: " "$prompt" "$default_label" > /dev/tty
    IFS= read -r reply < /dev/tty || reply=""
    reply="${reply:-$default_answer}"
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
    printf "[setup] Please answer yes or no.\n" > /dev/tty
  done
}

prompt_menu() {
  local prompt="$1"
  shift

  if use_whiptail_ui; then
    local value=""
    if ! value="$(whiptail --title "$SETUP_UI_TITLE" --menu "$prompt" 15 78 4 "$@" 3>&1 1>&2 2>&3)"; then
      fail "Setup was canceled"
    fi
    printf "%s\n" "$value"
    return
  fi

  printf "%s\n" "$1"
}

usage() {
  cat <<'EOF'
Usage:
  sudo bash setup.sh [options]

Modes:
  auto              On a Proxmox host, create a dedicated Ubuntu LXC and install there.
                    On a normal Ubuntu/Debian box, install directly on the current system.
  host              Install directly on the current Ubuntu/Debian system using Node.js + PM2.
  lxc               Create a dedicated Ubuntu LXC on a Proxmox host, then install the app inside it.

Options:
  --mode <auto|host|lxc>         Force an install mode
  --install-on-host              Shortcut for --mode host
  --lxc                          Shortcut for --mode lxc
  --repo <git-url>               Git repo to clone or update
  --branch <name>                Git branch (default: main)
  --dir <path>                   Install directory inside Ubuntu/LXC (default: /opt/proxmox-helper-local)
  --host <address>               Default Proxmox host IP/hostname for first boot
  --port <port>                  App port (default: 3000)
  --node-major <version>         Node.js major version to install (default: 20)
  --lxc-id <id>                  LXC ID to create
  --lxc-name <name>              LXC hostname/name
  --lxc-storage <storage>        Rootfs storage for the LXC (auto when omitted)
  --lxc-template-storage <name>  Template storage for vzdump templates (auto when omitted)
  --lxc-template <template>      Explicit Ubuntu template filename
  --lxc-memory <mb>              LXC memory in MB (default: 2048)
  --lxc-cores <count>            LXC CPU cores (default: 2)
  --lxc-disk <gb>                LXC root disk size in GB (default: 8)
  --bridge <name>                Proxmox bridge for the LXC (default: vmbr0)
  --lxc-ip <dhcp|ip/cidr>        DHCP or a static IP/CIDR for the new LXC
  --lxc-gateway <ip>             Gateway for a static LXC IP
  -h, --help                     Show this help

Examples:
  sudo bash setup.sh --host 192.168.8.12
  sudo bash setup.sh --mode host --repo https://github.com/Gam3ReaTr0/Proxmox-helper-script-locally.git --host 192.168.8.12
  sudo bash setup.sh --mode lxc --lxc-id 301 --lxc-ip 192.168.8.50/24 --lxc-gateway 192.168.8.1

Notes:
  In interactive LXC mode, setup.sh can open a small whiptail-based setup wizard for the
  Proxmox host IP and the new LXC IP settings.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || fail "Missing value for --mode"
      MODE="$2"
      shift 2
      ;;
    --install-on-host)
      MODE="host"
      shift
      ;;
    --lxc)
      MODE="lxc"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || fail "Missing value for --repo"
      REPO_URL="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || fail "Missing value for --branch"
      BRANCH="$2"
      shift 2
      ;;
    --dir)
      [[ $# -ge 2 ]] || fail "Missing value for --dir"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || fail "Missing value for --host"
      PROXMOX_HOST_IP="$2"
      HOST_ARG_SET=1
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || fail "Missing value for --port"
      PORT="$2"
      shift 2
      ;;
    --node-major)
      [[ $# -ge 2 ]] || fail "Missing value for --node-major"
      NODE_MAJOR="$2"
      shift 2
      ;;
    --lxc-id)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-id"
      LXC_ID="$2"
      shift 2
      ;;
    --lxc-name)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-name"
      LXC_NAME="$2"
      shift 2
      ;;
    --lxc-storage)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-storage"
      LXC_STORAGE="$2"
      shift 2
      ;;
    --lxc-template-storage)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-template-storage"
      LXC_TEMPLATE_STORAGE="$2"
      shift 2
      ;;
    --lxc-template)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-template"
      LXC_TEMPLATE="$2"
      shift 2
      ;;
    --lxc-memory)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-memory"
      LXC_MEMORY="$2"
      shift 2
      ;;
    --lxc-cores)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-cores"
      LXC_CORES="$2"
      shift 2
      ;;
    --lxc-disk)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-disk"
      LXC_DISK="$2"
      shift 2
      ;;
    --bridge)
      [[ $# -ge 2 ]] || fail "Missing value for --bridge"
      LXC_BRIDGE="$2"
      shift 2
      ;;
    --lxc-ip)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-ip"
      LXC_IP="$2"
      LXC_IP_ARG_SET=1
      shift 2
      ;;
    --lxc-gateway)
      [[ $# -ge 2 ]] || fail "Missing value for --lxc-gateway"
      LXC_GATEWAY="$2"
      shift 2
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
[[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] || fail "Node major version must be numeric"
[[ "$LXC_MEMORY" =~ ^[0-9]+$ ]] || fail "LXC memory must be numeric"
[[ "$LXC_CORES" =~ ^[0-9]+$ ]] || fail "LXC cores must be numeric"
[[ "$LXC_DISK" =~ ^[0-9]+$ ]] || fail "LXC disk size must be numeric"
[[ -z "$LXC_ID" || "$LXC_ID" =~ ^[0-9]+$ ]] || fail "LXC ID must be numeric"
if [[ "$LXC_IP" != "dhcp" ]] && ! is_valid_ipv4_cidr "$LXC_IP"; then
  fail "LXC IP must be 'dhcp' or an IP/CIDR like 192.168.8.50/24"
fi
if [[ -n "$LXC_GATEWAY" ]] && ! is_valid_ipv4 "$LXC_GATEWAY"; then
  fail "LXC gateway must be an IPv4 address"
fi

if [[ $EUID -ne 0 ]]; then
  fail "Run this script with sudo or as root"
fi

if [[ -z "$REPO_URL" && -f "$SCRIPT_DIR/server.js" && -f "$SCRIPT_DIR/public/index.html" ]]; then
  LOCAL_REPO_SOURCE=1
  INSTALL_DIR="$SCRIPT_DIR"
fi

ensure_apt() {
  has_command apt-get || fail "This setup script supports Debian/Ubuntu systems with apt-get"
  export DEBIAN_FRONTEND=noninteractive
}

install_base_packages() {
  ensure_apt
  log "Installing base packages"
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    git \
    build-essential \
    python3 \
    gnupg
}

install_nodejs() {
  local current_major=""

  if has_command node; then
    current_major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || true)"
  fi

  if [[ "$current_major" =~ ^[0-9]+$ ]] && (( current_major >= NODE_MAJOR )); then
    log "Node.js $current_major is already installed"
    return
  fi

  log "Installing Node.js $NODE_MAJOR.x"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

  local distro_codename=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distro_codename="${VERSION_CODENAME:-}"
  fi
  [[ -n "$distro_codename" ]] || fail "Could not determine the Debian/Ubuntu codename for NodeSource"

  cat > /etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main
EOF

  apt-get update
  apt-get install -y nodejs
}

install_pm2() {
  log "Installing PM2"
  npm install -g pm2
}

detect_primary_ipv4() {
  local detected=""

  if has_command ip; then
    detected="$(ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
  fi

  if [[ -z "$detected" ]] && has_command hostname; then
    detected="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  printf "%s\n" "$detected"
}

resolve_proxmox_host_ip() {
  if [[ -n "$PROXMOX_HOST_IP" ]]; then
    printf "%s\n" "$PROXMOX_HOST_IP"
    return
  fi

  if is_proxmox_host; then
    local detected
    detected="$(detect_primary_ipv4)"
    if [[ -n "$detected" ]]; then
      log "Auto-detected Proxmox host IP: $detected"
      printf "%s\n" "$detected"
      return
    fi
  fi

  printf "%s\n" "$DEFAULT_PROXMOX_HOST_IP"
}

validate_lxc_network_settings() {
  if [[ "$LXC_IP" != "dhcp" ]] && ! is_valid_ipv4_cidr "$LXC_IP"; then
    fail "LXC IP must be 'dhcp' or an IP/CIDR like 192.168.8.50/24"
  fi

  if [[ "$LXC_IP" != "dhcp" && -z "$LXC_GATEWAY" ]]; then
    fail "Static LXC networking needs a gateway so the installer can reach the internet inside the new container"
  fi

  if [[ -n "$LXC_GATEWAY" ]] && ! is_valid_ipv4 "$LXC_GATEWAY"; then
    fail "LXC gateway must be an IPv4 address"
  fi
}

prompt_lxc_network_settings() {
  local network_mode=""
  local static_ip=""
  local static_gateway=""

  if (( LXC_IP_ARG_SET )); then
    validate_lxc_network_settings
    return
  fi

  if ! can_prompt; then
    validate_lxc_network_settings
    return
  fi

  if use_whiptail_ui; then
    network_mode="$(prompt_menu \
      "Choose how the new LXC should get its network settings" \
      "dhcp" "Use DHCP and get the address automatically" \
      "static" "Set a fixed IP address and gateway now")"
  elif prompt_yes_no "Use a static IP for the new LXC?" "n"; then
    network_mode="static"
  else
    network_mode="dhcp"
  fi

  if [[ "$network_mode" == "static" ]]; then
    while true; do
      static_ip="$(prompt_with_default "LXC IP/CIDR" "192.168.8.50/24")"
      if is_valid_ipv4_cidr "$static_ip"; then
        break
      fi
      printf "[setup] Enter the IP like 192.168.8.50/24.\n" > /dev/tty
    done

    while true; do
      static_gateway="$(prompt_with_default "LXC gateway" "192.168.8.1")"
      if is_valid_ipv4 "$static_gateway"; then
        break
      fi
      printf "[setup] Enter the gateway like 192.168.8.1.\n" > /dev/tty
    done

    LXC_IP="$static_ip"
    LXC_GATEWAY="$static_gateway"
  else
    LXC_IP="dhcp"
    LXC_GATEWAY=""
  fi

  validate_lxc_network_settings
}

configure_lxc_install_interactive() {
  local detected_host_ip=""

  if ! can_prompt; then
    return
  fi

  ensure_prompt_ui
  detected_host_ip="$(resolve_proxmox_host_ip)"
  if (( ! HOST_ARG_SET )); then
    PROXMOX_HOST_IP="$(prompt_with_default "Proxmox host IP or hostname for the app" "$detected_host_ip")"
  else
    PROXMOX_HOST_IP="$detected_host_ip"
  fi

  prompt_lxc_network_settings
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
  log "Installing app dependencies"
  cd "$INSTALL_DIR"
  npm install --omit=dev --no-audit --no-fund --unsafe-perm
}

write_runtime_env_file() {
  log "Writing runtime environment file"
  cat > "$INSTALL_DIR/.runtime.env" <<EOF
NODE_ENV=production
PORT=$PORT
PROXMOX_HOST_IP=$PROXMOX_HOST_IP
EOF
}

write_pm2_ecosystem() {
  log "Writing PM2 ecosystem file"
  cat > "$INSTALL_DIR/ecosystem.config.cjs" <<EOF
module.exports = {
  apps: [
    {
      name: '${APP_NAME}',
      cwd: '${INSTALL_DIR}',
      script: 'server.js',
      env: {
        NODE_ENV: 'production',
        PORT: '${PORT}',
        PROXMOX_HOST_IP: '${PROXMOX_HOST_IP}'
      }
    }
  ]
};
EOF
}

configure_pm2() {
  log "Starting the app with PM2"
  cd "$INSTALL_DIR"

  pm2 delete "$APP_NAME" >/dev/null 2>&1 || true
  pm2 startOrRestart ecosystem.config.cjs --only "$APP_NAME" --update-env
  pm2 save

  if has_command systemctl; then
    log "Configuring PM2 startup with systemd"
    env PATH="$PATH:/usr/bin:/usr/local/bin" pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || \
      warn "PM2 startup could not be configured automatically; the app still runs in PM2"
    systemctl enable --now pm2-root >/dev/null 2>&1 || \
      warn "pm2-root could not be enabled automatically; run 'systemctl enable --now pm2-root' if needed"
    pm2 save
  else
    warn "systemctl is not available, so PM2 startup on boot was skipped"
  fi
}

print_host_summary() {
  log "Install complete"
  printf "\nMode: host\n"
  printf "Directory: %s\n" "$INSTALL_DIR"
  printf "Port: %s\n" "$PORT"
  printf "Default Proxmox host: %s\n" "$PROXMOX_HOST_IP"
  printf "PM2 app: %s\n" "$APP_NAME"
  printf "Open: http://YOUR_SERVER_IP:%s\n" "$PORT"
  printf "\nUseful commands:\n"
  printf "  pm2 status\n"
  printf "  pm2 logs %s\n" "$APP_NAME"
  printf "  pm2 restart %s\n" "$APP_NAME"
}

is_proxmox_host() {
  has_command pct && has_command pveam
}

choose_mode() {
  case "$MODE" in
    auto)
      if is_proxmox_host; then
        printf "lxc\n"
      else
        printf "host\n"
      fi
      ;;
    host|lxc)
      printf "%s\n" "$MODE"
      ;;
    *)
      fail "Unsupported mode: $MODE"
      ;;
  esac
}

build_lxc_net0() {
  local net0="name=eth0,bridge=${LXC_BRIDGE}"

  if [[ "$LXC_IP" == "dhcp" ]]; then
    net0="${net0},ip=dhcp"
  else
    net0="${net0},ip=${LXC_IP}"
    if [[ -n "$LXC_GATEWAY" ]]; then
      net0="${net0},gw=${LXC_GATEWAY}"
    fi
  fi

  printf "%s\n" "$net0"
}

github_raw_setup_url() {
  local repo="$1"
  local branch="$2"
  local repo_path=""

  case "$repo" in
    https://github.com/*)
      repo_path="${repo#https://github.com/}"
      ;;
    http://github.com/*)
      repo_path="${repo#http://github.com/}"
      ;;
    git@github.com:*)
      repo_path="${repo#git@github.com:}"
      ;;
    *)
      fail "LXC mode currently requires a GitHub repo URL so the container can download setup.sh"
      ;;
  esac

  repo_path="${repo_path%.git}"
  [[ -n "$repo_path" ]] || fail "Could not parse the GitHub repository path from: $repo"
  printf "https://raw.githubusercontent.com/%s/%s/setup.sh\n" "$repo_path" "$branch"
}

pick_lxc_template_storage() {
  if [[ -n "$LXC_TEMPLATE_STORAGE" ]]; then
    printf "%s\n" "$LXC_TEMPLATE_STORAGE"
    return
  fi

  if pvesm status 2>/dev/null | awk 'NR>1 && $1=="local" {found=1} END{exit found ? 0 : 1}'; then
    printf "local\n"
    return
  fi

  local first_dir
  first_dir="$(pvesm status 2>/dev/null | awk 'NR>1 && $2=="dir" {print $1; exit}')"
  [[ -n "$first_dir" ]] || fail "Could not find a directory storage for LXC templates"
  printf "%s\n" "$first_dir"
}

pick_lxc_storage() {
  if [[ -n "$LXC_STORAGE" ]]; then
    printf "%s\n" "$LXC_STORAGE"
    return
  fi

  local candidate
  for candidate in local-lvm local-zfs local; do
    if pvesm status 2>/dev/null | awk -v target="$candidate" 'NR>1 && $1==target {found=1} END{exit found ? 0 : 1}'; then
      printf "%s\n" "$candidate"
      return
    fi
  done

  local first_storage
  first_storage="$(pvesm status 2>/dev/null | awk 'NR>1 {print $1; exit}')"
  [[ -n "$first_storage" ]] || fail "Could not determine a storage for the LXC rootfs"
  printf "%s\n" "$first_storage"
}

pick_lxc_template() {
  if [[ -n "$LXC_TEMPLATE" ]]; then
    printf "%s\n" "$LXC_TEMPLATE"
    return
  fi

  pveam update >/dev/null

  local pattern template
  for pattern in 'ubuntu-24.04-standard.*amd64\.tar\.(gz|zst)$' 'ubuntu-22.04-standard.*amd64\.tar\.(gz|zst)$'; do
    template="$(pveam available --section system 2>/dev/null | awk -v pattern="$pattern" '{for (i = 1; i <= NF; i++) if ($i ~ pattern) {print $i; exit}}')"
    if [[ -n "$template" ]]; then
      printf "%s\n" "$template"
      return
    fi
  done

  fail "Could not find an Ubuntu LXC template in pveam"
}

ensure_lxc_template_downloaded() {
  local storage="$1"
  local template="$2"

  if pveam list "$storage" 2>/dev/null | grep -Fq "$template"; then
    log "Using cached template $template from $storage"
    return
  fi

  log "Downloading template $template to $storage"
  pveam download "$storage" "$template"
}

next_lxc_id() {
  if [[ -n "$LXC_ID" ]]; then
    printf "%s\n" "$LXC_ID"
    return
  fi

  if has_command pvesh; then
    pvesh get /cluster/nextid
    return
  fi

  fail "Could not determine the next available LXC ID"
}

wait_for_lxc() {
  local id="$1"
  local tries=0

  while (( tries < 60 )); do
    if pct exec "$id" -- bash -lc "echo ready" >/dev/null 2>&1; then
      return
    fi
    tries=$((tries + 1))
    sleep 2
  done

  fail "LXC $id did not become ready in time"
}

create_lxc() {
  local id="$1"
  local template_storage="$2"
  local template="$3"
  local storage="$4"
  local net0

  net0="$(build_lxc_net0)"

  if pct status "$id" >/dev/null 2>&1; then
    fail "LXC $id already exists; choose another --lxc-id"
  fi

  log "Creating Ubuntu LXC $id on storage $storage"
  pct create "$id" "${template_storage}:vztmpl/${template}" \
    --hostname "$LXC_NAME" \
    --ostype ubuntu \
    --unprivileged 1 \
    --cores "$LXC_CORES" \
    --memory "$LXC_MEMORY" \
    --swap 512 \
    --rootfs "${storage}:${LXC_DISK}" \
    --net0 "$net0" \
    --features "nesting=1,keyctl=1" \
    --onboot 1 \
    --tags "$APP_NAME"

  pct start "$id"
}

bootstrap_lxc_install() {
  local id="$1"
  local raw_setup_url="$2"

  log "Installing the app inside LXC $id"
  pct exec "$id" -- bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y ca-certificates curl"

  local remote_cmd
  printf -v remote_cmd \
    "curl -fsSL %q | bash -s -- --mode host --repo %q --branch %q --dir %q --host %q --port %q --node-major %q" \
    "$raw_setup_url" \
    "$REPO_URL" \
    "$BRANCH" \
    "$INSTALL_DIR" \
    "$PROXMOX_HOST_IP" \
    "$PORT" \
    "$NODE_MAJOR"

  pct exec "$id" -- bash -lc "$remote_cmd"
}

lxc_primary_ip() {
  local id="$1"
  pct exec "$id" -- bash -lc "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r' || true
}

print_lxc_summary() {
  local id="$1"
  local ip="$2"
  local requested_ip=""

  if [[ "$LXC_IP" != "dhcp" ]]; then
    requested_ip="${LXC_IP%%/*}"
  fi

  log "LXC install complete"
  printf "\nMode: lxc\n"
  printf "LXC ID: %s\n" "$id"
  printf "LXC name: %s\n" "$LXC_NAME"
  printf "Default Proxmox host inside app: %s\n" "$PROXMOX_HOST_IP"
  if [[ -n "$requested_ip" ]]; then
    printf "Configured LXC IP: %s\n" "$requested_ip"
    if [[ -n "$LXC_GATEWAY" ]]; then
      printf "Configured gateway: %s\n" "$LXC_GATEWAY"
    fi
    printf "Open: http://%s:%s\n" "$requested_ip" "$PORT"
  elif [[ -n "$ip" ]]; then
    printf "LXC IP: %s\n" "$ip"
    printf "Open: http://%s:%s\n" "$ip" "$PORT"
  else
    printf "LXC IP: not detected yet\n"
  fi

  printf "\nUseful commands:\n"
  printf "  pct enter %s\n" "$id"
  printf "  pct status %s\n" "$id"
  printf "  pct stop %s && pct start %s\n" "$id" "$id"
}

install_host_mode() {
  PROXMOX_HOST_IP="$(resolve_proxmox_host_ip)"
  install_base_packages
  install_nodejs
  install_pm2
  sync_repo
  install_node_modules
  write_runtime_env_file
  write_pm2_ecosystem
  configure_pm2
  print_host_summary
}

install_lxc_mode() {
  is_proxmox_host || fail "LXC mode must be run on a Proxmox host"
  [[ -n "$REPO_URL" ]] || fail "LXC mode requires --repo so the new container can fetch setup.sh from GitHub"
  configure_lxc_install_interactive
  PROXMOX_HOST_IP="${PROXMOX_HOST_IP:-$(resolve_proxmox_host_ip)}"
  validate_lxc_network_settings

  local template_storage storage template id raw_setup_url ip
  template_storage="$(pick_lxc_template_storage)"
  storage="$(pick_lxc_storage)"
  template="$(pick_lxc_template)"
  id="$(next_lxc_id)"
  raw_setup_url="$(github_raw_setup_url "$REPO_URL" "$BRANCH")"

  ensure_lxc_template_downloaded "$template_storage" "$template"
  create_lxc "$id" "$template_storage" "$template" "$storage"
  wait_for_lxc "$id"
  bootstrap_lxc_install "$id" "$raw_setup_url"
  ip="$(lxc_primary_ip "$id")"
  print_lxc_summary "$id" "$ip"
}

main() {
  local chosen_mode
  chosen_mode="$(choose_mode)"
  log "Selected install mode: $chosen_mode"

  case "$chosen_mode" in
    host)
      install_host_mode
      ;;
    lxc)
      install_lxc_mode
      ;;
    *)
      fail "Unsupported resolved mode: $chosen_mode"
      ;;
  esac
}

main
