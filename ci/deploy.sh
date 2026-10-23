#!/usr/bin/env bash
# Déploiement complet, sans secret stocké :
#   1. identité Teleport du bot (jeton OIDC GitLab)
#   2. clé SSH jetable, 3. Terraform crée les VM manquantes
#   4-6. les VM neuves rejoignent Teleport (jeton de 15 min, SSH direct une seule fois)
#   7-8. toutes les VM sont configurées à travers Teleport, puis idempotence vérifiée
set -euo pipefail
# shellcheck source=ci/common.sh
. ci/common.sh

: "${TELEPORT_PROXY:?}" "${TELEPORT_CLUSTER:?}" "${TELEPORT_TUNNEL_HOST:?}" "${TELEPORT_TUNNEL_IP:?}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tbot_dir="$work/tbot"

# Le dossier du dépôt est accessible en écriture à tous dans le conteneur :
# Ansible ignorerait ansible.cfg, on passe donc les réglages par l'environnement.
export ANSIBLE_ROLES_PATH="$PWD/ansible/roles"
export ANSIBLE_REMOTE_USER=ansible
export ANSIBLE_PYTHON_INTERPRETER=auto_silent
export ANSIBLE_FORCE_COLOR=1

teleport_vars=(
  -e "teleport_node_proxy_server=$TELEPORT_PROXY"
  -e "teleport_node_tunnel_host=$TELEPORT_TUNNEL_HOST"
  -e "teleport_node_tunnel_ip=$TELEPORT_TUNNEL_IP"
)

trust_gitlab_ca
terraform_env

echo "== 1. Identité Teleport du bot (jonction gitlab, sans secret)"
cat > "$work/tbot.yaml" <<EOF
version: v2
proxy_server: ${TELEPORT_PROXY}
oneshot: true
onboarding:
  join_method: gitlab
  token: homelab-ci-gitlab
storage:
  type: memory
outputs:
  - type: identity
    destination:
      type: directory
      path: ${tbot_dir}
EOF
tbot start -c "$work/tbot.yaml"
tsh_bot() { tsh -i "$tbot_dir/identity" --proxy="$TELEPORT_PROXY" "$@"; }

echo "== 2. Clé SSH jetable (détruite avec le conteneur)"
ssh-keygen -q -t ed25519 -N '' -C "bootstrap-job-${CI_JOB_ID}" -f "$work/bootstrap"
TF_VAR_bootstrap_ssh_public_key=$(cat "$work/bootstrap.pub")
export TF_VAR_bootstrap_ssh_public_key

echo "== 3. Terraform"
(
  cd terraform
  terraform init -input=false
  terraform apply -input=false -auto-approve -lock-timeout=60s
  terraform output -json vm_ips > "$work/vms.json"
)

echo "== 4. VM pas encore enregistrées dans Teleport"
tsh_bot ls --format=names > "$work/joined.txt"
mapfile -t new_vms < <(python3 - "$work/vms.json" "$work/joined.txt" <<'PY'
import json, sys
vms = json.load(open(sys.argv[1]))
joined = set(open(sys.argv[2]).read().split())
for name in sorted(vms):
    if name not in joined:
        print(name)
PY
)
echo "VM neuves : ${new_vms[*]:-aucune}"

if ((${#new_vms[@]})); then
  echo "== 5. Jeton de jonction de 15 minutes (jamais affiché)"
  token=$(python3 -c 'import secrets; print(secrets.token_hex(20))')
  (umask 077 && printf '%s' "$token" > "$work/node-token")
  expires=$(date -u -d '+15 min' +%Y-%m-%dT%H:%M:%SZ)
  printf 'kind: token\nversion: v2\nmetadata:\n  name: %s\n  expires: "%s"\nspec:\n  roles: [Node]\n  join_method: token\n' \
    "$token" "$expires" \
    | tctl --identity="$tbot_dir/identity" --auth-server="$TELEPORT_PROXY" create >/dev/null
  unset token

  echo "== 6. Amorçage en SSH direct avec la clé jetable : ${new_vms[*]}"
  python3 - "$work/vms.json" "${new_vms[@]}" > "$work/bootstrap.ini" <<'PY'
import json, sys
vms = json.load(open(sys.argv[1]))
print("[bootstrap]")
for name in sys.argv[2:]:
    print(f"{name} ansible_host={vms[name]}")
PY
  ansible-playbook -i "$work/bootstrap.ini" ansible/bootstrap.yml \
    -e "ansible_ssh_private_key_file=$work/bootstrap" \
    -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/known_hosts'" \
    -e "teleport_node_token_src=$work/node-token" \
    "${teleport_vars[@]}"
fi

echo "== 7. Configuration de toutes les VM à travers Teleport"
python3 - "$work/vms.json" "$TELEPORT_CLUSTER" > "$work/homelab.ini" <<'PY'
import json, sys
vms, cluster = json.load(open(sys.argv[1])), sys.argv[2]
print("[homelab]")
for name in sorted(vms):
    print(f"{name} ansible_host={name}.{cluster}")
PY
via_teleport=(-i "$work/homelab.ini" -e "ansible_ssh_common_args='-F $tbot_dir/ssh_config'")
ansible-playbook "${via_teleport[@]}" ansible/homelab.yml "${teleport_vars[@]}"

echo "== 8. Idempotence : le second passage ne doit rien changer"
ansible-playbook "${via_teleport[@]}" ansible/homelab.yml "${teleport_vars[@]}" | tee "$work/second.log"
if grep -E '^[^ ]+ +: ok=' "$work/second.log" | grep -vq ' changed=0 '; then
  echo "ERREUR : le second passage a modifié quelque chose (playbook non idempotent)"
  exit 1
fi
