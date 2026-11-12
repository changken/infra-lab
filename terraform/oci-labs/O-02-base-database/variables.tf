variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "tenancy_id" {
  description = "Tenancy OCID（查 Availability Domain 用）"
  type        = string
}

variable "compartment_id" {
  description = "homelab compartment OCID（envs/oci-governance 的 output）"
  type        = string
}

variable "allowed_cidr" {
  description = "你的對外 IP（/32）：用於 SSH(22)、SQL*Net(1521)"
  type        = string

  validation {
    condition     = var.allowed_cidr != "0.0.0.0/0"
    error_message = "allowed_cidr 不可為 0.0.0.0/0，資料庫不要對全世界開放。"
  }
}

variable "ssh_public_key" {
  description = "DB node SSH 公鑰（使用者為 opc）"
  type        = string
}

variable "db_admin_password" {
  description = "SYS / SYSTEM 密碼：9–30 字元，需含大寫、小寫、數字，特殊符號僅接受 _、#、- 且至少 2 個，不可含 sys/system/oracle"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o02-basedb"

  # 會直接當 DB System hostname 使用：≤ 12 字元，小寫英數與連字號
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,11}$", var.name_prefix))
    error_message = "name_prefix 需 ≤ 12 字元，小寫英文開頭，僅含小寫英數與連字號（會作為 DB hostname）。"
  }
}

variable "vcn_cidr" {
  description = "Lab 專用 VCN CIDR"
  type        = string
  default     = "10.30.0.0/16"
}

variable "db_version" {
  description = "Oracle 版本（可用 oci db version list --db-system-shape VM.BaseDB.x86 查）"
  type        = string
  default     = "19.0.0.0"
}

variable "database_edition" {
  description = "STANDARD_EDITION／ENTERPRISE_EDITION／ENTERPRISE_EDITION_HIGH_PERFORMANCE／..."
  type        = string
  default     = "STANDARD_EDITION"
}

variable "compute_count" {
  description = "ECPU 數量。VM.BaseDB.x86 最小 4；此帳號 service limit（vm-basedb-x86-ecpu-count）上限為 8"
  type        = number
  default     = 4

  # 💰 DB System 是付費資源，沒有 Always Free。ECPU 愈多愈貴。
  validation {
    condition     = var.compute_count >= 4 && var.compute_count <= 8
    error_message = "compute_count 必須介於 4～8（最小 4 ECPU；帳號 limit 上限 8）。"
  }
}

variable "data_storage_gbs" {
  description = "資料儲存 GB。此帳號 vm-block-storage-gb limit 為 1050；lab 用最小值即可"
  type        = number
  default     = 256

  validation {
    condition     = var.data_storage_gbs >= 256 && var.data_storage_gbs <= 512
    error_message = "data_storage_gbs 請介於 256～512，避免無謂計費。"
  }
}

variable "db_name" {
  description = "Database name（CDB，≤ 8 字元，英文開頭）"
  type        = string
  default     = "ORCL"
}

variable "pdb_name" {
  description = "PDB 名稱（連線用 service 為 <pdb>.<dns>）"
  type        = string
  default     = "PDB1"
}
