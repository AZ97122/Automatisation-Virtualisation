variable "proxmox_endpoint" {
  description = "URL de l'API Proxmox"
  type        = string
  default     = "https://192.168.100.241:8006/"
}

variable "proxmox_api_token_id" {
  description = "ID du token API (format user@realm!tokenid)"
  type        = string
  default     = "terraform@pve!tf-token"
}

variable "proxmox_api_token_secret" {
  description = "Secret du token API"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Nœud Proxmox cible"
  type        = string
  default     = "HYDRA-01"
}

variable "template_id" {
  description = "ID du template cloud-init"
  type        = number
  default     = 9001
}

variable "storage" {
  description = "Storage Proxmox pour les disques"
  type        = string
  default     = "VMs-Disks"
}

variable "network_bridge" {
  description = "Bridge réseau"
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Passerelle réseau"
  type        = string
  default     = "192.168.100.1"
}

variable "ssh_public_key" {
  description = "Clé publique SSH pour cloud-init"
  type        = string
}

variable "vm_user" {
  description = "Utilisateur créé par cloud-init"
  type        = string
  default     = "debian"
}
