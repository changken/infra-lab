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

variable "ocivm_private_ip" {
  description = "第一台 A1 的固定內網 IP"
  type        = string
}

variable "ocivm2_private_ip" {
  description = "第二台 A1 的固定內網 IP"
  type        = string
}

variable "boot_volume_ids" {
  description = "boot volume OCID：使用中的碟，以及 clone 的來源碟（已 TERMINATED，僅供 source_details 必填欄位使用）"
  type = object({
    ocivm_k3s    = string
    ocivm2_k3s   = string
    clone_source = string
  })
}

variable "instance_names" {
  description = "兩台 A1 的 display name / hostname label（boot volume 名稱由此衍生）"
  type = object({
    primary   = string
    secondary = string
  })
}

variable "backup_names" {
  description = "手動 boot volume backup 的 display name"
  type = object({
    first  = string
    second = string
  })
}
