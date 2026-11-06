variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（取自 oci-governance 的 output）"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "NSG my-sg 允許 SSH 的來源 CIDR（你的家用／辦公 IP，/32）"
  type        = string
}
