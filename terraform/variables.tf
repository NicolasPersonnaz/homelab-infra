variable "proxmox_endpoint" { type = string }
variable "node_name" { type = string }
variable "template_vmid" { type = number }
variable "ssh_public_key" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }

# Clé SSH jetable générée par le job CI : sert uniquement à amorcer une VM neuve.
variable "bootstrap_ssh_public_key" {
  type    = string
  default = ""
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}
