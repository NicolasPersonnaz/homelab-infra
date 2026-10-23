terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.117.0"
    }
  }

  # État hébergé par GitLab (verrouillage, versions, chiffré au repos).
  # Adresse et identifiants par variables d'environnement TF_HTTP_* (voir ci/deploy.sh).
  backend "http" {}
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = true # certificat auto-signé : lab uniquement
}
