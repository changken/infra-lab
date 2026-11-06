output "compartment_id" {
  description = "homelab compartment OCID，供 oci-vcn / oci-linux 的 tfvars 使用"
  value       = oci_identity_compartment.homelab.id
}
