output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  value = { for k, s in azurerm_subnet.this : k => s.id }
}

output "vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}

output "vm_private_ip" {
  value = azurerm_network_interface.vm.private_ip_address
}

output "admin_username" {
  value = var.admin_username
}

output "ssh_private_key_path" {
  value = local_sensitive_file.ssh_private_key.filename
}

output "ssh_command" {
  value = "ssh -i ${local_sensitive_file.ssh_private_key.filename} ${var.admin_username}@${azurerm_public_ip.vm.ip_address}"
}

output "ssh_private_key_openssh" {
  description = "貼到 Zeabur 用：terraform output -raw ssh_private_key_openssh"
  value       = tls_private_key.ssh.private_key_openssh
  sensitive   = true
}
