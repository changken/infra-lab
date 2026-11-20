variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（envs/oci-governance 的 output）"
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID：查 Availability Domain 要用 tenancy，不是 compartment"
  type        = string
}

variable "allowed_cidr" {
  description = "你的對外 IP（/32）：LB 的 80/443 入口與 Bastion client allow list"
  type        = string

  validation {
    condition     = var.allowed_cidr != "0.0.0.0/0"
    error_message = "allowed_cidr 不可為 0.0.0.0/0，lab 的 LB 不要對全世界開放。"
  }
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o07-edge"
}

variable "vcn_cidr" {
  description = "Lab 專用 VCN CIDR"
  type        = string
  default     = "10.34.0.0/16"
}

variable "backend_shape" {
  description = "backend instance shape。💰 付費；A1 額度已被 envs/oci-linux 用滿，不可用 A1"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "backend_ocpus" {
  description = "每台 backend 的 OCPU"
  type        = number
  default     = 1
}

variable "backend_memory_gbs" {
  description = "每台 backend 的記憶體 GB"
  type        = number
  default     = 8
}

variable "backend_count" {
  description = "backend 數量（LB 的後端）。💰 費用 ×N"
  type        = number
  default     = 2

  validation {
    condition     = var.backend_count >= 1 && var.backend_count <= 2
    error_message = "backend_count 請介於 1～2。"
  }
}

variable "lb_min_bandwidth_mbps" {
  description = "TODO 1：Flexible LB 最小頻寬 Mbps（10 是最小值，lab 不需要更多）"
  type        = number
  default     = 10
}

variable "lb_max_bandwidth_mbps" {
  description = "TODO 1：Flexible LB 最大頻寬 Mbps"
  type        = number
  default     = 10
}

variable "enable_waf" {
  description = "TODO 2：是否建 WAF policy 並掛到 LB"
  type        = bool
  default     = false
}

variable "enable_network_firewall" {
  description = "TODO 3：是否建 Network Firewall 並把 backend 的出站流量導進去。💰💰 最貴的部分，量完立刻關"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "backend 的 SSH 公鑰，同時用於 TODO 4 Bastion session（對應私鑰用來開 tunnel）"
  type        = string
  default     = null
}
