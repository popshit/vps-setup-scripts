#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'USAGE'
Usage:
  sudo ./setup-vps.sh --user USER --ssh-port PORT --public-key "ssh-ed25519 AAAA..." [options]

Required:
  --user USER                 New sudo user to create or update.
  --ssh-port PORT             SSH port to configure, usually 1024-65535.
  --public-key KEY            Public SSH key to install for USER.

Options:
  --swap-size SIZE            Create swap file with SIZE, for example 1G or 2G. Default: 0.
  --allow-http                Allow inbound 80/tcp in UFW.
  --allow-https               Allow inbound 443/tcp in UFW.
  --no-fail2ban               Do not install or configure fail2ban.
  --no-unattended-upgrades    Do not install unattended-upgrades.
  --reset-ufw                 Reset existing UFW rules before applying this baseline.
  --keep-root-ssh             Keep root SSH login enabled. Not recommended.
  --keep-password-ssh         Keep password SSH login enabled. Not recommended.
  -h, --help                  Show help.

Example:
  sudo ./setup-vps.sh \
    --user deploy \
    --ssh-port 2222 \
    --public-key "ssh-ed25519 AAAA_REPLACE_ME" \
    --swap-size 2G \
    --allow-http \
    --allow-https
USAGE
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run this script as root, for example: sudo $0 ..."
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

validate_user() {
  local value="$1"
  [[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid user name: $value"
  [[ "$value" != "root" ]] || die "--user must not be root"
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "SSH port must be a number"
  (( value >= 1 && value <= 65535 )) || die "SSH port must be between 1 and 65535"
  if (( value < 1024 )); then
    log "Warning: ports below 1024 are privileged. A port from 1024 to 65535 is usually simpler."
  fi
}

validate_public_key() {
  local value="$1"
  [[ "$value" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] \
    || die "public key does not look like an OpenSSH public key"
}

validate_swap_size() {
  local value="$1"
  [[ "$value" == "0" || "$value" =~ ^[1-9][0-9]*[MG]$ ]] || die "--swap-size must be 0 or a value like 1G, 2G, or 512M"
}

detect_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found"
  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    debian|ubuntu)
      ;;
    *)
      die "unsupported OS: ${PRETTY_NAME:-unknown}. This script supports Debian and Ubuntu."
      ;;
  esac

  log "Detected OS: ${PRETTY_NAME:-$ID}"
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "$@"
}

ensure_user() {
  local user="$1"
  local home_dir
  local sudoers_file="/etc/sudoers.d/90-${user}-nopasswd"

  if id "$user" >/dev/null 2>&1; then
    log "User exists: $user"
  else
    log "Creating sudo user: $user"
    adduser --disabled-password --gecos "" "$user"
  fi

  usermod -aG sudo "$user"
  printf '%s\n' "${user} ALL=(ALL:ALL) NOPASSWD:ALL" > "$sudoers_file"
  chmod 440 "$sudoers_file"
  visudo -cf "$sudoers_file" >/dev/null

  home_dir="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home_dir" ]] || die "could not determine home directory for $user"

  install -d -m 700 -o "$user" -g "$user" "$home_dir/.ssh"
  touch "$home_dir/.ssh/authorized_keys"
  chown "$user:$user" "$home_dir/.ssh/authorized_keys"
  chmod 600 "$home_dir/.ssh/authorized_keys"

  if ! grep -qxF "$PUBLIC_KEY" "$home_dir/.ssh/authorized_keys"; then
    printf '%s\n' "$PUBLIC_KEY" >> "$home_dir/.ssh/authorized_keys"
  fi

  chown "$user:$user" "$home_dir/.ssh/authorized_keys"
  chmod 600 "$home_dir/.ssh/authorized_keys"
}

configure_sshd() {
  local port="$1"
  local config_dir="/etc/ssh/sshd_config.d"
  local config_file="${config_dir}/99-vps-setup.conf"
  local root_login="no"
  local password_auth="no"
  local allow_users="$NEW_USER"

  [[ "$KEEP_ROOT_SSH" == "1" ]] && root_login="prohibit-password"
  [[ "$KEEP_PASSWORD_SSH" == "1" ]] && password_auth="yes"
  [[ "$KEEP_ROOT_SSH" == "1" ]] && allow_users="$NEW_USER root"

  install -d -m 755 "$config_dir"

  if [[ -f "$config_file" ]]; then
    cp -a "$config_file" "${config_file}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "$config_file" <<EOF
# Managed by $SCRIPT_NAME
Port $port
PubkeyAuthentication yes
PasswordAuthentication $password_auth
KbdInteractiveAuthentication no
PermitRootLogin $root_login
X11Forwarding no
AllowUsers $allow_users
EOF

  /usr/sbin/sshd -t || die "sshd config validation failed"

  local effective_ports
  effective_ports="$(/usr/sbin/sshd -T | awk '$1 == "port" { print $2 }')"
  grep -qx "$port" <<<"$effective_ports" || die "effective sshd config does not include port $port. Check earlier Port directives in sshd_config."

  log "Reloading SSH service"
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl reload ssh
  elif systemctl list-unit-files | grep -q '^sshd\.service'; then
    systemctl reload sshd
  else
    service ssh reload
  fi
}

configure_ufw() {
  local port="$1"

  log "Configuring UFW"
  if [[ "$RESET_UFW" == "1" ]]; then
    ufw --force reset
  fi

  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${port}/tcp" comment "SSH"

  if [[ "$ALLOW_HTTP" == "1" ]]; then
    ufw allow 80/tcp comment "HTTP"
  fi

  if [[ "$ALLOW_HTTPS" == "1" ]]; then
    ufw allow 443/tcp comment "HTTPS"
  fi

  ufw --force enable
  ufw status verbose
}

configure_fail2ban() {
  local port="$1"
  local jail_file="/etc/fail2ban/jail.d/sshd-setup.local"
  local ignore_ip="127.0.0.1/8 ::1"

  if [[ "${SSH_CLIENT:-}" =~ ^([0-9a-fA-F:.]+)[[:space:]] ]]; then
    ignore_ip="${ignore_ip} ${BASH_REMATCH[1]}"
  fi

  log "Configuring fail2ban"
  cat > "$jail_file" <<EOF
[sshd]
enabled = true
backend = systemd
port = $port
ignoreip = $ignore_ip
maxretry = 5
findtime = 10m
bantime = 1h
banaction = ufw
EOF

  systemctl enable --now fail2ban
  systemctl restart fail2ban
}

configure_unattended_upgrades() {
  log "Configuring unattended security upgrades"
  apt_install unattended-upgrades apt-listchanges
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --now unattended-upgrades || true
}

configure_swap() {
  local size="$1"
  local swap_file="/swapfile"

  [[ "$size" == "0" ]] && return 0

  if swapon --show=NAME --noheadings | grep -qx "$swap_file"; then
    log "Swap already active at $swap_file"
    return 0
  fi

  if [[ -e "$swap_file" ]]; then
    die "$swap_file already exists but is not active. Inspect it before rerunning."
  fi

  log "Creating swap file: $swap_file ($size)"
  if ! fallocate -l "$size" "$swap_file" 2>/dev/null; then
    local bs count
    bs="1M"
    count="${size%M}"
    if [[ "$size" == *G ]]; then
      count="$(( ${size%G} * 1024 ))"
    fi
    dd if=/dev/zero of="$swap_file" bs="$bs" count="$count" status=progress
  fi

  chmod 600 "$swap_file"
  mkswap "$swap_file"
  swapon "$swap_file"

  if ! grep -Eq '^[^#[:space:]]+[[:space:]]+none[[:space:]]+swap[[:space:]]' /etc/fstab; then
    printf '%s\n' '/swapfile none swap sw 0 0' >> /etc/fstab
  elif ! grep -Eq '^/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]' /etc/fstab; then
    log "A swap entry already exists in /etc/fstab. Not adding another one."
  fi
}

print_summary() {
  cat <<EOF

Done.

Test from a new terminal before closing this session:
  ssh -p $SSH_PORT $NEW_USER@YOUR_SERVER_IP

If you generated your key with scripts/generate-local-key.sh:
  ssh -i ~/.ssh/vps-debian12_ed25519 -p $SSH_PORT $NEW_USER@YOUR_SERVER_IP

Important:
  - Keep this current root session open until the new login works.
  - If login fails, use the provider web console or rescue mode to inspect SSH and UFW.
EOF
}

NEW_USER=""
SSH_PORT=""
PUBLIC_KEY=""
SWAP_SIZE="0"
ALLOW_HTTP="0"
ALLOW_HTTPS="0"
INSTALL_FAIL2BAN="1"
INSTALL_UNATTENDED_UPGRADES="1"
RESET_UFW="0"
KEEP_ROOT_SSH="0"
KEEP_PASSWORD_SSH="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      NEW_USER="${2:-}"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-}"
      shift 2
      ;;
    --public-key)
      PUBLIC_KEY="${2:-}"
      shift 2
      ;;
    --swap-size)
      SWAP_SIZE="${2:-}"
      shift 2
      ;;
    --allow-http)
      ALLOW_HTTP="1"
      shift
      ;;
    --allow-https)
      ALLOW_HTTPS="1"
      shift
      ;;
    --no-fail2ban)
      INSTALL_FAIL2BAN="0"
      shift
      ;;
    --no-unattended-upgrades)
      INSTALL_UNATTENDED_UPGRADES="0"
      shift
      ;;
    --reset-ufw)
      RESET_UFW="1"
      shift
      ;;
    --keep-root-ssh)
      KEEP_ROOT_SSH="1"
      shift
      ;;
    --keep-password-ssh)
      KEEP_PASSWORD_SSH="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_root
require_command awk
require_command grep
require_command systemctl

[[ -n "$NEW_USER" ]] || die "--user is required"
[[ -n "$SSH_PORT" ]] || die "--ssh-port is required"
[[ -n "$PUBLIC_KEY" ]] || die "--public-key is required"

validate_user "$NEW_USER"
validate_port "$SSH_PORT"
validate_public_key "$PUBLIC_KEY"
validate_swap_size "$SWAP_SIZE"
detect_os

log "Installing base packages"
apt_install openssh-server sudo ufw curl ca-certificates vim

ensure_user "$NEW_USER"
configure_sshd "$SSH_PORT"
configure_ufw "$SSH_PORT"

if [[ "$INSTALL_FAIL2BAN" == "1" ]]; then
  apt_install fail2ban
  configure_fail2ban "$SSH_PORT"
fi

if [[ "$INSTALL_UNATTENDED_UPGRADES" == "1" ]]; then
  configure_unattended_upgrades
fi

configure_swap "$SWAP_SIZE"
print_summary
