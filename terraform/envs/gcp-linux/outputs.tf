output "instance_id" {
  description = "Compute Instance ID"
  value       = google_compute_instance.main.id
}

output "public_ip" {
  description = "VM 公網 IPv4（Ephemeral，重啟後可能改變）"
  value       = google_compute_instance.main.network_interface[0].access_config[0].nat_ip
}

output "internal_ip" {
  description = "VM 內網 IPv4"
  value       = google_compute_instance.main.network_interface[0].network_ip
}

output "instance_status" {
  description = "VM 狀態"
  value       = google_compute_instance.main.current_status
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh ${var.ssh_user}@${google_compute_instance.main.network_interface[0].access_config[0].nat_ip}"
}

output "gcloud_ssh_command" {
  description = "透過 gcloud CLI SSH（不需金鑰管理）"
  value       = "gcloud compute ssh ${var.instance_name} --zone=${var.zone} --project=${var.project_id}"
}

output "firewall_name" {
  description = "Firewall Rule 名稱"
  value       = google_compute_firewall.allow_ssh.name
}
