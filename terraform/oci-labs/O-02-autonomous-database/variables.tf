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
  description = "你的對外 IP（/32）：用於 Bastion 的 client_cidr_block_allow_list"
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

variable "wallet_password" {
  description = "Wallet 密碼（下載 wallet 時用，≥ 8 字元）"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o02-adb"
}

variable "db_name" {
  description = "ADB 的 db_name：僅限英數、≤ 30 字元、英文開頭"
  type        = string
  default     = "O02ADB"
}

variable "vcn_cidr" {
  description = "Lab 專用 VCN CIDR（只有 private endpoint 練習會用到）"
  type        = string
  default     = "10.31.0.0/16"
}

variable "db_workload" {
  description = "OLTP（ATP）／DW（ADW）／AJD／APEX"
  type        = string
  default     = "OLTP"
}

variable "compute_count" {
  description = "ECPU 數量。💰 付費資源，ECPU 愈多愈貴；ECPU 模式最小 2"
  type        = number
  default     = 2

  validation {
    condition     = var.compute_count >= 2 && var.compute_count <= 8
    error_message = "compute_count 請介於 2～8，避免無謂計費（lab 不需要更多）。"
  }
}

variable "data_storage_gbs" {
  description = "資料儲存 GB。💰 以容量計費，lab 用最小值即可（實際最小值請以 Console／文件為準）"
  type        = number
  default     = 20
}

variable "ssh_public_key" {
  description = "TODO 7 Bastion session 用的 SSH 公鑰（對應的私鑰用來開 tunnel）。沒做 TODO 7 可留空"
  type        = string
  default     = null
}
