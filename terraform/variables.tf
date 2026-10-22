variable "proxmox_endpoint" { type = string }
variable "node_name" { type = string }
variable "template_vmid" { type = number }
variable "ssh_public_key" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

# Une entrée par VM : la clé de la map devient le nom de la VM.
variable "vms" {
  type = map(object({
    ip        = string
    cores     = number
    memory    = number # Mo
    disk_size = number # Go, doit être >= à la taille du disque du template
  }))
}
