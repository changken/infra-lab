#==============================================================
# AWS Aurora PostgreSQL Module - Input Variables
#==============================================================

variable "region" {
  type        = string
  description = "AWS Region to deploy resources"
  default     = "us-east-1"
}

variable "project" {
  type        = string
  description = "專案名稱，會做為資源名稱首碼"
  default     = "aurora-pgsql-lab"
}

variable "environment" {
  type        = string
  description = "部署環境 (dev/prod)"
  default     = "dev"
}

variable "vpc_id" {
  type        = string
  description = "目標 VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "資料庫 Subnet ID 清單 (最少需 2 個不同可用區 AZ)"
}

# ── Aurora Engine and Instances ──

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL 引擎版本 (例如: 15.4, 16.1)"
  default     = "15.4"
}

variable "cluster_size" {
  type        = number
  description = "叢集中的實例數量 (1 代表單節點 Writer，2 代表 1 Writer + 1 Reader)"
  default     = 1
}

variable "instance_class" {
  type        = string
  description = "實例規格。若要使用 Serverless v2 則設為 'db.serverless'，否則可用 'db.t4g.medium' 等"
  default     = "db.serverless"
}

# ── Serverless Scaling Config ──

variable "serverless_min_capacity" {
  type        = number
  description = "Serverless 最小容量 (ACU)"
  default     = 0.5
}

variable "serverless_max_capacity" {
  type        = number
  description = "Serverless 最大容量 (ACU)"
  default     = 2.0
}

# ── Database Authentication ──

variable "db_name" {
  type        = string
  description = "預設建立的資料庫名稱"
  default     = "mydb"
}

variable "db_username" {
  type        = string
  description = "管理者帳號"
  default     = "postgres"
}

variable "db_password" {
  type        = string
  description = "管理者密碼 (必須設定在 terraform.tfvars 中，禁止 commit 該檔案)"
  sensitive   = true
}

# ── Network and Security ──

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "允許連入 PostgreSQL 5432 Port 的 CIDR 區段清單"
  default     = []
}

variable "allowed_security_groups" {
  type        = list(string)
  description = "允許連入 PostgreSQL 5432 Port 的外部 Security Group ID 清單"
  default     = []
}

# ── Lab Protection and Backups ──

variable "skip_final_snapshot" {
  type        = bool
  description = "刪除叢集時是否跳過 Final Snapshot (Lab 環境設為 true 以免產生多餘儲存費用)"
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "是否開啟刪除保護 (Lab 環境設為 false，避免 destroy 失敗)"
  default     = false
}

variable "backup_retention_period" {
  type        = number
  description = "自動備份保留天數"
  default     = 1
}
