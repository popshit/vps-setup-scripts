#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARDEN_SCRIPT="${SCRIPT_DIR}/harden-vps.sh"

usage() {
  cat <<'USAGE'
Usage:
  sudo bash scripts/harden-vps-interactive.sh

This interactive wrapper asks for the important VPS hardening options, then
calls scripts/harden-vps.sh with explicit arguments.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

prompt_required() {
  local label="$1"
  local value=""

  while [[ -z "$value" ]]; do
    read -r -p "$label: " value
    if [[ -z "$value" ]]; then
      echo "This value is required." >&2
    fi
  done

  printf '%s' "$value"
}

prompt_default() {
  local label="$1"
  local default_value="$2"
  local value=""

  read -r -p "$label [$default_value]: " value
  printf '%s' "${value:-$default_value}"
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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  die "this wrapper does not accept arguments. Use ${HARDEN_SCRIPT} for non-interactive mode."
fi

if [[ "${EUID}" -ne 0 ]]; then
  die "run as root, for example: sudo bash scripts/harden-vps-interactive.sh"
fi

[[ -f "$HARDEN_SCRIPT" ]] || die "could not find harden-vps.sh at: $HARDEN_SCRIPT"

cat <<'INTRO'
VPS hardening interactive setup

Keep your current SSH session open after this script finishes. Open a second
terminal and test the new SSH login before closing the old root session.

INTRO

new_user="$(prompt_default "New sudo username" "deploy")"
ssh_port="$(prompt_default "New SSH port" "2222")"

echo
echo "Paste the public SSH key from your own computer."
echo "It usually starts with ssh-ed25519."
public_key="$(prompt_required "SSH public key")"

args=(
  --user "$new_user"
  --ssh-port "$ssh_port"
  --public-key "$public_key"
)

echo
if prompt_yes_no "Create swap" "y"; then
  swap_size="$(prompt_default "Swap size, for example 1G or 2G" "2G")"
  args+=(--swap-size "$swap_size")
fi

echo
echo "Open HTTP/HTTPS only if this VPS will host a website, API, reverse proxy, or ACME certificate challenge."
if prompt_yes_no "Allow HTTP on port 80" "n"; then
  args+=(--allow-http)
fi

if prompt_yes_no "Allow HTTPS on port 443" "n"; then
  args+=(--allow-https)
fi

echo
if ! prompt_yes_no "Install and enable fail2ban" "y"; then
  args+=(--no-fail2ban)
fi

if ! prompt_yes_no "Enable unattended security upgrades" "y"; then
  args+=(--no-unattended-upgrades)
fi

echo
echo "The next two options are mainly for temporary recovery access."
if prompt_yes_no "Temporarily keep root SSH login enabled" "n"; then
  args+=(--keep-root-ssh)
fi

if prompt_yes_no "Temporarily keep password SSH login enabled" "n"; then
  args+=(--keep-password-ssh)
fi

echo
if prompt_yes_no "Reset existing UFW firewall rules before applying this baseline" "n"; then
  args+=(--reset-ufw)
fi

echo
echo "About to run:"
printf '  '
printf '%q ' "$HARDEN_SCRIPT" "${args[@]}"
printf '\n\n'

if ! prompt_yes_no "Continue" "n"; then
  echo "Cancelled."
  exit 0
fi

bash "$HARDEN_SCRIPT" "${args[@]}"
