output "instance_id" {
  description = "Linode Instance ID"
  value       = linode_instance.main.id
}

output "public_ip" {
  description = "Instance 公網 IPv4"
  value       = linode_instance.main.ip_address
}

output "instance_status" {
  description = "Instance 狀態"
  value       = linode_instance.main.status
}

output "specs" {
  description = "Instance 規格（vCPU / RAM / 磁碟 / 月費流量）"
  value = {
    vcpus    = linode_instance.main.specs[0].vcpus
    memory   = "${linode_instance.main.specs[0].memory} MB"
    disk     = "${linode_instance.main.specs[0].disk} MB"
    transfer = "${linode_instance.main.specs[0].transfer} GB/月"
  }
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh root@${linode_instance.main.ip_address}"
}

output "firewall_id" {
  description = "Firewall ID"
  value       = linode_firewall.main.id
}
