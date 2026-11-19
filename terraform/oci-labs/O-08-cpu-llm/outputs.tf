output "instance_id" {
  description = "實例 OCID（terraform import 與 oci CLI 用）"
  value       = oci_core_instance.llm.id
}

output "public_ip" {
  description = "公網 IP"
  value       = oci_core_instance.llm.public_ip
}

output "private_ip" {
  description = "內網 IP"
  value       = oci_core_instance.llm.private_ip
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh ${var.ssh_user}@${oci_core_instance.llm.public_ip}"
}
