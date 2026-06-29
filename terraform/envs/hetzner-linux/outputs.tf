output "server_id" {
  description = "Hetzner Server ID"
  value       = hcloud_server.main.id
}

output "public_ip" {
  description = "Server 公網 IPv4"
  value       = hcloud_server.main.ipv4_address
}

output "server_status" {
  description = "Server 狀態"
  value       = hcloud_server.main.status
}

output "server_type" {
  description = "Server 規格"
  value       = hcloud_server.main.server_type
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh root@${hcloud_server.main.ipv4_address}"
}

output "firewall_id" {
  description = "Firewall ID"
  value       = hcloud_firewall.main.id
}
