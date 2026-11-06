variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（取自 oci-governance 的 output）"
  type        = string
}

variable "subnet_id" {
  description = "實例所在 subnet OCID（取自 oci-vcn 的 output）"
  type        = string
}

variable "nsg_id" {
  description = "套用在實例 VNIC 的 NSG OCID（取自 oci-vcn 的 output）"
  type        = string
}

variable "ssh_public_key" {
  description = "實例的 SSH 公鑰（authorized_keys 內容）"
  type        = string
}
