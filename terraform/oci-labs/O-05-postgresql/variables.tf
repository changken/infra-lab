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
  description = "你的對外 IP（/32）：用於 Bastion 的 client_cidr_block_allow_list"
  type        = string

  validation {
    condition     = var.allowed_cidr != "0.0.0.0/0"
    error_message = "allowed_cidr 不可為 0.0.0.0/0，資料庫不要對全世界開放。"
  }
}

variable "admin_username" {
  description = "PostgreSQL 管理者帳號（不可用 postgres 等保留字）"
  type        = string
  default     = "dbadmin"
}

variable "admin_password" {
  description = "PostgreSQL 管理者密碼：8–32 字元，需含大寫、小寫、數字、特殊字元"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o05-psql"
}

variable "vcn_cidr" {
  description = "Lab 專用 VCN CIDR"
  type        = string
  default     = "10.33.0.0/16"
}

variable "db_version" {
  description = "PostgreSQL 主版本。用 `oci psql default-configuration-collection list-default-configurations`／Console 確認 Singapore 支援哪些版本"
  type        = string
  default     = "16"
}

variable "psql_shape" {
  description = "DB system shape。💰 付費資源；名稱為 PostgreSQL.VM.Standard.E5.Flex（OCPU／記憶體由 instance_ocpu_count、instance_memory_gbs 另外指定），實際可用值以 `oci psql shape-summary list-shapes --all` 為準"
  type        = string
  default     = "PostgreSQL.VM.Standard.E5.Flex"
}

variable "instance_ocpu_count" {
  description = "每個 instance 的 OCPU。💰 與 shape 要一致；lab 用最小值"
  type        = number
  default     = 2

  validation {
    condition     = var.instance_ocpu_count >= 2 && var.instance_ocpu_count <= 4
    error_message = "instance_ocpu_count 請介於 2～4，lab 不需要更多。"
  }
}

variable "instance_memory_gbs" {
  description = "每個 instance 的記憶體 GB。💰 與 shape 要一致"
  type        = number
  default     = 32
}

variable "instance_count" {
  description = "TODO 2：instance 數量（1 = 單節點；3 = 1 primary + 2 replica，HA）。💰 費用 ×N"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 3
    error_message = "instance_count 請介於 1～3。"
  }
}

variable "enable_reader_endpoint" {
  description = "TODO 3：是否開 reader endpoint（需要 instance_count >= 2 才有意義）"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "TODO 4 Bastion session 用的 SSH 公鑰（對應的私鑰用來開 tunnel）。沒做 TODO 4 可留空"
  type        = string
  default     = null
}
