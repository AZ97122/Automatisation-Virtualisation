output "pbs_ip" {
  description = "IP de la VM PBS"
  value       = "192.168.100.221"
}

output "pbs_web_ui" {
  description = "Interface web PBS"
  value       = "https://192.168.100.221:8007"
}

output "test_vms_info" {
  description = "Informations sur les VMs de test"
  value = {
    for k, v in proxmox_virtual_environment_vm.test_vms :
    k => {
      name = v.name
      vmid = v.vm_id
      ip   = split("/", v.initialization[0].ip_config[0].ipv4[0].address)[0]
    }
  }
}
