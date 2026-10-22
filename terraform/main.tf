resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  on_boot   = true

  clone {
    vm_id = var.template_vmid
  }

  agent {
    enabled = false
  }

  # "host" expose le vrai processeur (x86-64-v2+, requis par semgrep). Pas de migration à chaud : un seul hôte.
  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Agrandit le disque cloné ; cloud-init étend la partition au premier démarrage.
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide2"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }

    user_account {
      username = "ansible"
      keys     = [var.ssh_public_key]
    }
  }
}

output "vm_ips" {
  value = { for name, vm in var.vms : name => vm.ip }
}
