#!/usr/bin/env bash
# Fonctions communes aux jobs Terraform et de déploiement.

# Les jobs parlent à l'API GitLab (état Terraform) : faire confiance à la CA interne,
# transmise par le runner (tls-ca-file).
trust_gitlab_ca() {
  cp "$CI_SERVER_TLS_CA_FILE" /usr/local/share/ca-certificates/homelab-gitlab.crt
  update-ca-certificates >/dev/null
}

# État Terraform hébergé par GitLab, authentifié par le jeton éphémère du job.
terraform_env() {
  : "${TERRAFORM_TOKEN:?variable CI TERRAFORM_TOKEN absente (branche non protégée ?)}"
  export PROXMOX_VE_API_TOKEN="$TERRAFORM_TOKEN"
  export TF_HTTP_ADDRESS="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/homelab"
  export TF_HTTP_LOCK_ADDRESS="${TF_HTTP_ADDRESS}/lock"
  export TF_HTTP_UNLOCK_ADDRESS="${TF_HTTP_ADDRESS}/lock"
  export TF_HTTP_LOCK_METHOD=POST
  export TF_HTTP_UNLOCK_METHOD=DELETE
  export TF_HTTP_USERNAME=gitlab-ci-token
  export TF_HTTP_PASSWORD="$CI_JOB_TOKEN"
  export TF_IN_AUTOMATION=1
}

# Identité Teleport du bot CI, sans secret : jonction « gitlab » par le jeton OIDC du job.
# Usage : teleport_identity <dossier> (le fichier de configuration et l'identité y sont écrits)
teleport_identity() {
  local dir=$1
  mkdir -p "$dir"
  cat > "$dir/tbot.yaml" <<EOF
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
      path: ${dir}/out
EOF
  tbot start -c "$dir/tbot.yaml"
}

# Le dossier du dépôt est accessible en écriture à tous dans le conteneur :
# Ansible ignorerait ansible.cfg, on passe donc les réglages par l'environnement.
ansible_env() {
  export ANSIBLE_ROLES_PATH="$PWD/ansible/roles"
  export ANSIBLE_REMOTE_USER=ansible
  export ANSIBLE_PYTHON_INTERPRETER=auto_silent
  export ANSIBLE_FORCE_COLOR=1
}
