output "instance_id" {
  description = "Vultr instance ID。"
  value       = vultr_instance.exit_node.id
}

output "public_ipv4" {
  description = "Vultr instance 公網 IPv4。"
  value       = vultr_instance.exit_node.main_ip
}

output "instance_status" {
  description = "Vultr instance 訂閱狀態。"
  value       = vultr_instance.exit_node.status
}

output "firewall_group_id" {
  description = "Vultr Firewall Group ID。"
  value       = vultr_firewall_group.exit_node.id
}
