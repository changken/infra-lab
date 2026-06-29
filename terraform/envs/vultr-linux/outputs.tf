output "instance_id" {
  description = "Vultr Instance ID"
  value       = vultr_instance.main.id
}

output "public_ip" {
  description = "Instance 公網 IP"
  value       = vultr_instance.main.main_ip
}

output "instance_status" {
  description = "Instance 狀態"
  value       = vultr_instance.main.status
}

output "default_password" {
  description = "Instance 預設 root 密碼（建議改用 SSH Key）"
  value       = vultr_instance.main.default_password
  sensitive   = true
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh -i ~/.ssh/id_rsa root@${vultr_instance.main.main_ip}"
}

output "firewall_group_id" {
  description = "Firewall Group ID"
  value       = vultr_firewall_group.main.id
}
