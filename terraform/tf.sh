#!/usr/bin/env bash
# Lance terraform avec le jeton Proxmox lu dans un fichier réservé à root.
# Usage : sudo ./tf.sh plan
set -euo pipefail

token_file=/root/.config/homelab/proxmox-token

if [[ $EUID -ne 0 ]]; then
  echo "Lancer avec sudo : sudo $0 $*" >&2
  exit 1
fi

if [[ $(stat -c %a "$token_file") != 600 ]]; then
  echo "$token_file doit être en 600" >&2
  exit 1
fi

PROXMOX_VE_API_TOKEN=$(<"$token_file")
export PROXMOX_VE_API_TOKEN

cd "$(dirname "$0")"
exec terraform "$@"
