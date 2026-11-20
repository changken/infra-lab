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
  description = "MySQL 管理者帳號（不可用 root、admin 等保留字）"
  type        = string
  default     = "dbadmin"
}

variable "admin_password" {
  description = "MySQL 管理者密碼：8–32 字元，需含大寫、小寫、數字、特殊字元"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o04-mysql"
}

variable "vcn_cidr" {
  description = "Lab 專用 VCN CIDR"
  type        = string
  default     = "10.32.0.0/16"
}

variable "mysql_shape" {
  description = "DB system shape。💰 付費資源。`oci mysql shape list` 看得到 MySQL.N；HeatWave 能掛哪些 shape 以 Console／文件為準"
  type        = string
  default     = "MySQL.2"
}

variable "data_storage_gbs" {
  description = "DB system 資料儲存 GB。💰 以容量計費，lab 用最小值即可"
  type        = number
  default     = 50

  validation {
    condition     = var.data_storage_gbs >= 50 && var.data_storage_gbs <= 200
    error_message = "data_storage_gbs 請介於 50～200，lab 的資料量很小。"
  }
}

variable "enable_ha" {
  description = "TODO 2：是否開 High Availability（跨 fault domain 的多個 instance）。💰 DB system 費用會變多倍"
  type        = bool
  default     = false
}

variable "enable_heatwave" {
  description = "TODO 3：是否建立 HeatWave cluster。💰 本 lab 最貴的部分，用完立刻關"
  type        = bool
  default     = false
}

variable "heatwave_shape" {
  description = "HeatWave 節點 shape（Singapore 實測可用：HeatWave.32GB、HeatWave.512GB、HeatWave.Free；256GB 會被拒）"
  type        = string
  default     = "HeatWave.32GB"
}

variable "heatwave_cluster_size" {
  description = "HeatWave 節點數。💰 每個節點都計費；lab 用最小值"
  type        = number
  default     = 1

  validation {
    condition     = var.heatwave_cluster_size >= 1 && var.heatwave_cluster_size <= 2
    error_message = "heatwave_cluster_size 請介於 1～2，lab 不需要更多。"
  }
}

variable "ssh_public_key" {
  description = "TODO 4 Bastion session 用的 SSH 公鑰（對應的私鑰用來開 tunnel）。沒做 TODO 4 可留空"
  type        = string
  default     = null
}
