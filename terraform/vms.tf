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
    # Baseline sans durcissement : audit Lynis de référence (« avant »)
    lynis-test = {
      ip        = "192.168.1.71"
      cores     = 2
      memory    = 2048
      disk_size = 20
    }
    # Supervision : Prometheus (réception OTLP) et Grafana
    grafana = {
      ip        = "192.168.1.73"
      cores     = 2
      memory    = 2048
      disk_size = 20
    }
    # Développement du rôle de durcissement, comparé à l'audit de lynis-test
    hardening-test = {
      ip        = "192.168.1.72"
      cores     = 2
      memory    = 2048
      disk_size = 20
    }
  }
}
