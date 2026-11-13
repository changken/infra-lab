output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "subnet_id" {
  description = "供 oci-linux 使用"
  value       = oci_core_subnet.public.id
}

output "nsg_id" {
  description = "供 oci-linux 使用"
  value       = oci_core_network_security_group.main.id
}
