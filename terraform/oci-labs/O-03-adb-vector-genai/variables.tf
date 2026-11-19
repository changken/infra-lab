variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（envs/oci-governance 的 output）"
  type        = string
}

variable "allowed_cidr" {
  description = "你的對外 IP（/32）：用於 ADB public endpoint 的 ACL（whitelisted_ips）"
  type        = string

  validation {
    condition     = var.allowed_cidr != "0.0.0.0/0"
    error_message = "allowed_cidr 不可為 0.0.0.0/0，資料庫不要對全世界開放。"
  }
}

variable "admin_password" {
  description = "ADMIN 密碼：12–30 字元，需含大寫、小寫、數字，不可含雙引號與 admin"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o03-vec"
}

variable "db_name" {
  description = "ADB 的 db_name：僅限英數、≤ 30 字元、英文開頭"
  type        = string
  default     = "O03VEC"
}

variable "db_version" {
  description = "ADB 版本。VECTOR 型別與 AI Vector Search 需要 23ai 以上（19c 沒有）"
  type        = string
  default     = "23ai"

  validation {
    condition     = contains(["23ai", "26ai"], var.db_version)
    error_message = "db_version 只能是 23ai 或 26ai（19c 不支援 VECTOR）。"
  }
}

variable "db_workload" {
  description = "OLTP（ATP）／DW（ADW）"
  type        = string
  default     = "OLTP"
}

variable "compute_count" {
  description = "ECPU 數量。💰 付費資源；ECPU 模式最小 2"
  type        = number
  default     = 2

  validation {
    condition     = var.compute_count >= 2 && var.compute_count <= 4
    error_message = "compute_count 請介於 2～4，本 lab 的資料量很小，不需要更多。"
  }
}

variable "data_storage_gbs" {
  description = "資料儲存 GB。💰 以容量計費，lab 用最小值即可"
  type        = number
  default     = 20
}

variable "par_expires_at" {
  description = "Pre-authenticated request 的到期時間（RFC 3339）。預設為 credit 到期日"
  type        = string
  default     = "2026-11-22T00:00:00Z"

  validation {
    condition     = can(formatdate("YYYY-MM-DD", var.par_expires_at))
    error_message = "par_expires_at 必須是 RFC 3339 格式，例如 2026-11-22T00:00:00Z。"
  }
}

variable "idcs_endpoint" {
  description = "Identity Domain 的 URL（Console → Identity → Domains → Default → Domain URL，含 :443）。用於建立 dynamic resource group"
  type        = string
}

variable "domain_name" {
  description = "Identity Domain 名稱（policy 內以 'domain'/'group' 引用）"
  type        = string
  default     = "Default"
}
