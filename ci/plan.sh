#!/usr/bin/env bash
# Plan Terraform en lecture seule, pour relecture avant le déploiement.
set -euo pipefail
# shellcheck source=ci/common.sh
. ci/common.sh

trust_gitlab_ca
terraform_env

cd terraform
terraform init -input=false
terraform plan -input=false -lock-timeout=60s
