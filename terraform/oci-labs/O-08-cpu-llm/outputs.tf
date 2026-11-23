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

output "instance2_id" {
  description = "第二台實例 OCID"
  value       = oci_core_instance.llm2.id
}

output "instance2_public_ip" {
  description = "第二台公網 IP"
  value       = oci_core_instance.llm2.public_ip
}

output "instance2_private_ip" {
  description = "第二台內網 IP"
  value       = oci_core_instance.llm2.private_ip
}

output "instance2_ssh_command" {
  description = "第二台 SSH 連線指令"
  value       = "ssh ${var.ssh_user}@${oci_core_instance.llm2.public_ip}"
}
