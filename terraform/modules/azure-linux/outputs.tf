output "vm_id" {
  description = "ID of the Linux Virtual Machine"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "public_ip" {
  description = "Public IP address of the VM (null if create_public_ip = false)"
  value       = var.create_public_ip ? azurerm_public_ip.vm[0].ip_address : null
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value = var.create_public_ip ? (
    local.use_generated_key
    ? "ssh -i ${path.module}/${var.name_prefix}-key.pem ${var.admin_username}@${azurerm_public_ip.vm[0].ip_address}"
    : "ssh ${var.admin_username}@${azurerm_public_ip.vm[0].ip_address}"
  ) : "VM has no public IP — connect via private network"
}

output "private_key_path" {
  description = "Path to the auto-generated private key file (only set when admin_ssh_public_key is null)"
  sensitive   = true
  value       = local.use_generated_key ? "${path.module}/${var.name_prefix}-key.pem" : null
}

output "nic_id" {
  description = "ID of the Network Interface"
  value       = azurerm_network_interface.vm.id
}
