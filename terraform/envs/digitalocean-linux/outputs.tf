output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.main.id
}

output "public_ip" {
  description = "Droplet 公網 IPv4"
  value       = digitalocean_droplet.main.ipv4_address
}

output "droplet_status" {
  description = "Droplet 狀態"
  value       = digitalocean_droplet.main.status
}

output "price_monthly" {
  description = "月費估算（USD）"
  value       = "${digitalocean_droplet.main.price_monthly} USD/月"
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh root@${digitalocean_droplet.main.ipv4_address}"
}

output "firewall_id" {
  description = "Cloud Firewall ID"
  value       = digitalocean_firewall.main.id
}

output "ssh_key_fingerprint" {
  description = "SSH Key Fingerprint"
  value       = digitalocean_ssh_key.main.fingerprint
}
