#!/usr/bin/env bash
# Audit Lynis de toutes les VM étiquetées env=homelab dans Teleport, rapports importés
# dans DefectDojo. Aucun secret : identité Teleport par OIDC, jeton DefectDojo lu sur sa VM.
set -euo pipefail
# shellcheck source=ci/common.sh
. ci/common.sh

: "${TELEPORT_PROXY:?}" "${TELEPORT_CLUSTER:?}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tbot_dir="$work/tbot/out"

ansible_env

echo "== 1. Identité Teleport du bot (jonction gitlab, sans secret)"
teleport_identity "$work/tbot"

echo "== 2. VM étiquetées env=homelab"
# La liste vient de Teleport (et non de Terraform) : toute VM jointe avec l'étiquette est auditée.
tsh -i "$tbot_dir/identity" --proxy="$TELEPORT_PROXY" ls env=homelab --format=names > "$work/vms.txt"
{
  echo "[homelab]"
  while read -r vm; do
    echo "$vm ansible_host=$vm.$TELEPORT_CLUSTER"
  done < "$work/vms.txt"
} > "$work/homelab.ini"
cat "$work/vms.txt"
grep -qx defectdojo "$work/vms.txt" || { echo "ERREUR : VM defectdojo absente de Teleport"; exit 1; }

echo "== 3. Audit Lynis et import dans DefectDojo"
ansible-playbook -i "$work/homelab.ini" -e "ansible_ssh_common_args='-F $tbot_dir/ssh_config'" \
  -e "lynis_report_dir=$work/reports" ansible/lynis-audit.yml
