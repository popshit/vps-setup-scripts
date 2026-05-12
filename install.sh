#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/popshit/vps-setup-scripts/main}"
INSTALL_DIR="${INSTALL_DIR:-/root}"

log() {
  printf '[install] %s\n' "$*"
}

die() {
  printf '[install] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run as root, for example: sudo bash <(curl -fsSL ${REPO_RAW_BASE}/install.sh)"
  fi
}

fetch_file() {
  local source_path="$1"
  local target_path="$2"

  log "Downloading ${source_path} -> ${target_path}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${REPO_RAW_BASE}/${source_path}" -o "$target_path"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$target_path" "${REPO_RAW_BASE}/${source_path}"
  else
    die "curl or wget is required"
  fi
}

require_root

install -d -m 700 "$INSTALL_DIR"
fetch_file "scripts/setup-vps.sh" "${INSTALL_DIR}/setup-vps.sh"
fetch_file "scripts/setup-vps-interactive.sh" "${INSTALL_DIR}/setup-vps-interactive.sh"
chmod +x "${INSTALL_DIR}/setup-vps.sh" "${INSTALL_DIR}/setup-vps-interactive.sh"

log "Starting interactive VPS setup"
bash "${INSTALL_DIR}/setup-vps-interactive.sh"
