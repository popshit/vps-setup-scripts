#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/generate-local-key.sh KEY_NAME

Example:
  bash scripts/generate-local-key.sh vps-debian12

This creates:
  ~/.ssh/KEY_NAME_ed25519
  ~/.ssh/KEY_NAME_ed25519.pub
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

key_name="${1:-}"
if [[ -z "$key_name" ]]; then
  usage
  exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ERROR: ssh-keygen is required." >&2
  exit 1
fi

if [[ ! "$key_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: KEY_NAME may only contain letters, numbers, dots, underscores, and hyphens." >&2
  exit 1
fi

ssh_dir="${HOME}/.ssh"
key_path="${ssh_dir}/${key_name}_ed25519"

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

if [[ -e "$key_path" || -e "${key_path}.pub" ]]; then
  echo "ERROR: key already exists: $key_path" >&2
  echo "Choose a different KEY_NAME or move the existing key first." >&2
  exit 1
fi

ssh-keygen -t ed25519 -a 100 -f "$key_path" -C "$key_name" -N ""
chmod 600 "$key_path"
chmod 644 "${key_path}.pub"

echo
echo "Private key:"
echo "  $key_path"
echo
echo "Public key to pass into harden-vps.sh:"
cat "${key_path}.pub"
echo
echo "Example login after server hardening:"
echo "  ssh -i $key_path -p 2222 deploy@YOUR_SERVER_IP"
