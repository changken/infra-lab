output "vm_id" {
  description = "ID of the Windows Virtual Machine"
  value       = azurerm_windows_virtual_machine.vm.id
}

output "public_ip" {
  description = "Public IP address of the VM (null if create_public_ip = false)"
  value       = var.create_public_ip ? azurerm_public_ip.vm[0].ip_address : null
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "rdp_command" {
  description = "RDP command to connect to the VM (Windows: mstsc, macOS: Microsoft Remote Desktop)"
  value       = var.create_public_ip ? "mstsc /v:${azurerm_public_ip.vm[0].ip_address}" : "VM has no public IP — connect via private network"
}

output "admin_username" {
  description = "Admin username for RDP login"
  value       = var.admin_username
}

output "admin_password" {
  description = "Admin password for RDP login (sensitive)"
  sensitive   = true
  value       = local.effective_password
}

output "password_file_path" {
  description = "Path to the auto-generated password file (only set when admin_password is null)"
  sensitive   = true
  value       = local.use_generated_password ? "${path.module}/${var.name_prefix}-password.txt" : null
}

output "nsg_id" {
  description = "ID of the NIC-level Network Security Group"
  value       = azurerm_network_security_group.vm.id
}

output "nic_id" {
  description = "ID of the Network Interface"
  value       = azurerm_network_interface.vm.id
}
