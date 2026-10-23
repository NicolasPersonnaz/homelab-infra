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
