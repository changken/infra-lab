output "instance_id" {
  value = oci_core_instance.changken_ocivm.id
}

output "public_ip" {
  value = oci_core_instance.changken_ocivm.public_ip
}

output "ssh_command" {
  description = "預設使用者依 image 而定（Ubuntu 為 ubuntu，Oracle Linux 為 opc）"
  value       = "ssh <user>@${oci_core_instance.changken_ocivm.public_ip}"
}
