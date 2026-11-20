output "backend_private_ips" {
  value = [for i in oci_core_instance.backend : i.private_ip]
}

output "backend_ids" {
  value = [for i in oci_core_instance.backend : i.id]
}

output "lb_public_ip" {
  value = oci_load_balancer_load_balancer.this.ip_address_details[0].ip_address
}

output "curl_command" {
  value = "curl http://${oci_load_balancer_load_balancer.this.ip_address_details[0].ip_address}/"
}

output "bastion_ssh_commands" {
  description = "每台 backend 一條；<privateKey> 已換成 ~/.ssh/id_rsa，請改成你的私鑰路徑"
  value = [
    for s in oci_bastion_session.backend :
    replace(s.ssh_metadata["command"], "<privateKey>", "~/.ssh/id_rsa")
  ]
}

output "firewall_private_ip" {
  description = "enable_network_firewall = false 時為 null"
  value       = try(oci_network_firewall_network_firewall.this[0].ipv4address, null)
}
