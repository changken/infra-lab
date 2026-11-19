variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（envs/oci-governance 的 output）"
  type        = string
}

variable "subnet_id" {
  description = "實例所在 subnet OCID（envs/oci-vcn 的 output；現況為 public-subnet-one）"
  type        = string
}

variable "ssh_public_key" {
  description = "實例的 SSH 公鑰（authorized_keys 內容）"
  type        = string
}

variable "image_id" {
  description = "開機映像檔 OCID（import 現況；改動會觸發 replace，故 lifecycle 內 ignore）"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain（ap-singapore-1 只有 1 個）"
  type        = string
  default     = "pimc:AP-SINGAPORE-1-AD-1"
}

variable "fault_domain" {
  description = "Fault Domain（import 現況）"
  type        = string
  default     = "FAULT-DOMAIN-1"
}

variable "instance_name" {
  description = "實例 display name"
  type        = string
  default     = "instance-20261119-2012"
}

variable "hostname_label" {
  description = "VNIC hostname label（Console 預設值，import 現況）"
  type        = string
  default     = "test"
}

variable "private_ip" {
  description = "VNIC 內網 IP（import 現況）"
  type        = string
  default     = "10.87.0.20"
}

variable "shape" {
  description = "Compute shape。💰 付費資源（無 Always Free）"
  type        = string
  default     = "VM.Standard.E5.Flex"
}

variable "ocpus" {
  description = "OCPU 數量。規劃為 8，Console 實際開成 23；改小會 resize（需重開機）"
  type        = number
  default     = 23

  validation {
    condition     = var.ocpus >= 1 && var.ocpus <= 32
    error_message = "ocpus 請介於 1～32（額度 standard-e5-core-count 為 83，但 lab 不需要更多）。"
  }
}

variable "memory_in_gbs" {
  description = "記憶體 GB。規劃為 64，Console 實際開成 276"
  type        = number
  default     = 276
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume 大小 GB。現況 1024（超出 Always Free 的 200 GB 總量，且已用 94 GB）"
  type        = number
  default     = 1024
}

variable "boot_volume_vpus_per_gb" {
  description = "Boot volume 效能（10 balanced／20 higher／30 ultra high）。現況 30 較貴"
  type        = number
  default     = 30
}
