# ============================================
# Définition des VMs de test
# ============================================
locals {
  test_vms = {
    "webserv" = {
      vm_id       = 310
      name        = "VM-WEBSERV"
      description = "Serveur web Nginx - test backup"
      node_name   = "HYDRA-01"
      cores       = 1
      memory      = 1024
      disk_size   = 10
      ip_address  = "192.168.100.222/24"
    }
    "dbserv" = {
      vm_id       = 311
      name        = "VM-DBSERV"
      description = "Base de données PostgreSQL - test backup"
      node_name   = "HYDRA-03"
      cores       = 2
      memory      = 2048
      disk_size   = 20
      ip_address  = "192.168.100.223/24"
    }
    "fileserv" = {
      vm_id       = 312
      name        = "VM-FILESERV"
      description = "Serveur de fichiers - test backup"
      node_name   = "HYDRA-04"
      cores       = 1
      memory      = 1024
      disk_size   = 30
      ip_address  = "192.168.100.224/24"
    }
  }
}

# ============================================
# VM Proxmox Backup Server
# ============================================
resource "proxmox_virtual_environment_vm" "pbs" {
  name        = "VM-PBS"
  description = "Proxmox Backup Server - managed by Terraform"
  node_name   = "HYDRA-02"  # ← Nœud dédié pour PBS
  vm_id       = 301

  clone {
    vm_id = var.template_id
    node_name = "HYDRA-01"
    full  = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = 32
    file_format  = "qcow2"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  initialization {
    datastore_id = var.storage

  dns {
    servers = ["8.8.8.8", "1.1.1.1"]
  }

    ip_config {
      ipv4 {
        address = "192.168.100.221/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }
}

# ============================================
# VMs de test (on fait une boucle, pourle placement par VM)
# ============================================
resource "proxmox_virtual_environment_vm" "test_vms" {
  for_each = local.test_vms

  name        = each.value.name
  description = each.value.description
  node_name   = each.value.node_name   # ← Lit le nœud depuis la map
  vm_id       = each.value.vm_id

  clone {
    vm_id = var.template_id
    node_name = "HYDRA-01"
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = each.value.disk_size
    file_format  = "qcow2"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  initialization {
    datastore_id = var.storage

  dns {
    servers = ["8.8.8.8", "1.1.1.1"]
  }

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }
}
