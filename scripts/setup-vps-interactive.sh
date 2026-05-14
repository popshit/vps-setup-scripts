#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/setup-vps.sh"
PROMPT_VALUE=""

usage() {
  cat <<'USAGE'
Usage:
  sudo bash scripts/setup-vps-interactive.sh

This interactive wrapper asks which VPS setup modules to run, collects only
the needed values, shows a final summary, then calls scripts/setup-vps.sh.

At value prompts, type "back" to return to that module's yes/no question.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

is_back() {
  case "$1" in
    back|Back|BACK|b|B)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_required_or_back() {
  local label="$1"
  local value=""

  while true; do
    read -r -p "$label: " value
    if is_back "$value"; then
      return 2
    fi
    if [[ -n "$value" ]]; then
      PROMPT_VALUE="$value"
      return 0
    fi
    echo "This value is required. Type 'back' to return to the previous question." >&2
  done
}

prompt_default_or_back() {
  local label="$1"
  local default_value="$2"
  local value=""

  read -r -p "$label [$default_value]: " value
  if is_back "$value"; then
    return 2
  fi
  PROMPT_VALUE="${value:-$default_value}"
  return 0
}

prompt_yes_no() {
  local label="$1"
  local default_value="$2"
  local prompt_suffix="[y/N]"
  local value=""

  case "$default_value" in
    y|Y|yes|YES)
      prompt_suffix="[Y/n]"
      ;;
    n|N|no|NO)
      prompt_suffix="[y/N]"
      ;;
    *)
      die "invalid yes/no default: $default_value"
      ;;
  esac

  while true; do
    read -r -p "$label $prompt_suffix: " value
    value="${value:-$default_value}"
    case "$value" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO)
        return 1
        ;;
      *)
        echo "Please answer y or n." >&2
        ;;
    esac
  done
}

ask_user_module() {
  while true; do
    echo
    if prompt_yes_no "Create/update a sudo user and install an SSH public key" "y"; then
      prompt_default_or_back "New sudo username" "deploy" || continue
      new_user="$PROMPT_VALUE"

      echo
      echo "Paste the public SSH key from your own computer."
      echo "It usually starts with ssh-ed25519. Type 'back' to choose again."
      prompt_required_or_back "SSH public key" || continue
      public_key="$PROMPT_VALUE"
      create_user="1"
    else
      create_user="0"
      new_user=""
      public_key=""
    fi
    return 0
  done
}

ask_ssh_module() {
  while true; do
    echo
    if [[ "$create_user" == "1" ]]; then
      if prompt_yes_no "Configure SSH port and login hardening" "y"; then
        configure_ssh="1"
      else
        configure_ssh="0"
      fi
    else
      echo "SSH hardening is skipped because this run is not creating/installing a login user."
      echo "This avoids disabling root login before a replacement user is ready."
      configure_ssh="0"
    fi

    if [[ "$configure_ssh" == "1" ]]; then
      prompt_default_or_back "New SSH port" "2222" || continue
      ssh_port="$PROMPT_VALUE"

      echo
      echo "The next two options are mainly for temporary recovery access."
      if prompt_yes_no "Temporarily keep root SSH login enabled" "n"; then
        keep_root_ssh="1"
      else
        keep_root_ssh="0"
      fi

      if prompt_yes_no "Temporarily keep password SSH login enabled" "n"; then
        keep_password_ssh="1"
      else
        keep_password_ssh="0"
      fi
    fi
    return 0
  done
}

ensure_ssh_port_for_service() {
  local label="$1"
  local default_port="${ssh_port:-22}"

  if [[ -z "$ssh_port" ]]; then
    prompt_default_or_back "$label" "$default_port" || return 2
    ssh_port="$PROMPT_VALUE"
  fi
  return 0
}

ask_ufw_module() {
  while true; do
    echo
    if prompt_yes_no "Configure UFW firewall rules" "y"; then
      configure_ufw="1"
      ensure_ssh_port_for_service "SSH port to allow in UFW" || continue

      echo
      echo "Open HTTP/HTTPS only if this VPS will host a website, API, reverse proxy, or ACME certificate challenge."
      if prompt_yes_no "Allow HTTP on port 80" "n"; then
        allow_http="1"
      else
        allow_http="0"
      fi

      if prompt_yes_no "Allow HTTPS on port 443" "n"; then
        allow_https="1"
      else
        allow_https="0"
      fi

      if prompt_yes_no "Reset existing UFW firewall rules before applying this baseline" "n"; then
        reset_ufw="1"
      else
        reset_ufw="0"
      fi
    else
      configure_ufw="0"
      allow_http="0"
      allow_https="0"
      reset_ufw="0"
    fi
    return 0
  done
}

ask_fail2ban_module() {
  while true; do
    echo
    if prompt_yes_no "Install and enable fail2ban for SSH" "y"; then
      install_fail2ban="1"
      ensure_ssh_port_for_service "SSH port for fail2ban to monitor" || continue
    else
      install_fail2ban="0"
    fi
    return 0
  done
}

ask_unattended_module() {
  echo
  if prompt_yes_no "Enable unattended security upgrades" "y"; then
    install_unattended="1"
  else
    install_unattended="0"
  fi
}

ask_swap_module() {
  while true; do
    echo
    if prompt_yes_no "Create swap" "y"; then
      create_swap="1"
      prompt_default_or_back "Swap size, for example 1G or 2G" "2G" || continue
      swap_size="$PROMPT_VALUE"
    else
      create_swap="0"
      swap_size="0"
    fi
    return 0
  done
}

print_plan() {
  echo
  echo "Planned changes:"

  if [[ "$create_user" == "1" ]]; then
    echo "  - Create or update sudo user: $new_user"
    echo "  - Install the provided SSH public key for: $new_user"
  else
    echo "  - Skip sudo user and SSH key setup"
  fi

  if [[ "$configure_ssh" == "1" ]]; then
    echo "  - Configure SSH port: $ssh_port"
    echo "  - Disable root SSH login: $([[ "$keep_root_ssh" == "1" ]] && echo "no" || echo "yes")"
    echo "  - Disable password SSH login: $([[ "$keep_password_ssh" == "1" ]] && echo "no" || echo "yes")"
  else
    echo "  - Skip SSH server configuration"
  fi

  if [[ "$configure_ufw" == "1" ]]; then
    echo "  - Configure UFW and allow SSH port: $ssh_port/tcp"
    [[ "$allow_http" == "1" ]] && echo "  - Allow HTTP: 80/tcp"
    [[ "$allow_https" == "1" ]] && echo "  - Allow HTTPS: 443/tcp"
    [[ "$reset_ufw" == "1" ]] && echo "  - Reset existing UFW rules first"
  else
    echo "  - Skip UFW configuration"
  fi

  if [[ "$install_fail2ban" == "1" ]]; then
    echo "  - Install and configure fail2ban for SSH port: $ssh_port"
  else
    echo "  - Skip fail2ban"
  fi

  if [[ "$install_unattended" == "1" ]]; then
    echo "  - Enable unattended security upgrades"
  else
    echo "  - Skip unattended security upgrades"
  fi

  if [[ "$create_swap" == "1" ]]; then
    echo "  - Create swap: $swap_size"
  else
    echo "  - Skip swap creation"
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  die "this wrapper does not accept arguments. Use ${SETUP_SCRIPT} for non-interactive mode."
fi

if [[ "${EUID}" -ne 0 ]]; then
  die "run as root, for example: sudo bash scripts/setup-vps-interactive.sh"
fi

[[ -f "$SETUP_SCRIPT" ]] || die "could not find setup-vps.sh at: $SETUP_SCRIPT"

cat <<'INTRO'
VPS interactive setup

Keep your current SSH session open after this script finishes. Open a second
terminal and test the new SSH login before closing the old root session.

Each module is optional. If you choose yes and then want to change your mind,
type "back" at a value prompt to return to that module's yes/no question.

INTRO

create_user="1"
new_user=""
public_key=""
configure_ssh="1"
ssh_port=""
keep_root_ssh="0"
keep_password_ssh="0"
configure_ufw="1"
allow_http="0"
allow_https="0"
reset_ufw="0"
install_fail2ban="1"
install_unattended="1"
create_swap="1"
swap_size="0"

ask_user_module
ask_ssh_module
ask_ufw_module
ask_fail2ban_module
ask_unattended_module
ask_swap_module

args=()

if [[ "$create_user" == "1" ]]; then
  args+=(--user "$new_user" --public-key "$public_key")
else
  args+=(--skip-user)
fi

if [[ -n "$ssh_port" ]]; then
  args+=(--ssh-port "$ssh_port")
fi

if [[ "$configure_ssh" == "0" ]]; then
  args+=(--skip-ssh)
fi

if [[ "$configure_ufw" == "0" ]]; then
  args+=(--skip-ufw)
fi

if [[ "$allow_http" == "1" ]]; then
  args+=(--allow-http)
fi

if [[ "$allow_https" == "1" ]]; then
  args+=(--allow-https)
fi

if [[ "$install_fail2ban" == "0" ]]; then
  args+=(--no-fail2ban)
fi

if [[ "$install_unattended" == "0" ]]; then
  args+=(--no-unattended-upgrades)
fi

if [[ "$keep_root_ssh" == "1" ]]; then
  args+=(--keep-root-ssh)
fi

if [[ "$keep_password_ssh" == "1" ]]; then
  args+=(--keep-password-ssh)
fi

if [[ "$reset_ufw" == "1" ]]; then
  args+=(--reset-ufw)
fi

if [[ "$create_swap" == "1" ]]; then
  args+=(--swap-size "$swap_size")
fi

print_plan

echo
echo "About to run:"
printf '  '
printf '%q ' "$SETUP_SCRIPT" "${args[@]}"
printf '\n\n'

if ! prompt_yes_no "Apply these changes" "n"; then
  echo "Cancelled. No server changes were applied by the setup script."
  exit 0
fi

bash "$SETUP_SCRIPT" "${args[@]}"
