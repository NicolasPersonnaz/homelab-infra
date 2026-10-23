# Inventaire des VM, versionné : ajouter une entrée = créer une VM au prochain déploiement.
# La clé devient le nom de la VM, son nom d'hôte Linux et son nom dans Teleport.
variable "vms" {
  type = map(object({
    ip        = string
    cores     = number
    memory    = number # Mo
    disk_size = number # Go, doit être >= à la taille du disque du template
  }))

  default = {
    gitlab = {
      ip        = "192.168.1.69"
      cores     = 4
      memory    = 8192
      disk_size = 50
    }
    defectdojo = {
      ip        = "192.168.1.70"
      cores     = 2
      memory    = 4096
      disk_size = 40
    }
  }
}
