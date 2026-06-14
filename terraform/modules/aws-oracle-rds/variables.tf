variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "oracle-rds-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

# ── RDS Instance ──
variable "instance_class" {
  description = "RDS instance type. db.t3.medium 最省；db.m5.large 給較大工作負載"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Storage in GB (min 20 for Oracle SE2)"
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "Oracle SE2 engine version. 19c = '19'"
  type        = string
  default     = "19"
}

variable "license_model" {
  description = "license-included (SE2 LI) or bring-your-own-license"
  type        = string
  default     = "license-included"
}

# ── 資料庫認證 ──
variable "db_name" {
  description = "Oracle SID / DB name (大寫，長度 ≤ 8)"
  type        = string
  default     = "ORCL"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Master password — 設在 terraform.tfvars，禁止 commit"
  type        = string
  sensitive   = true
}

# ── 網路 ──
variable "allowed_cidr" {
  description = "允許連入 Oracle port 1521 的 CIDR（你的 IP）"
  type        = string
  default     = "118.150.143.171/32"
}

variable "publicly_accessible" {
  description = "RDS 是否開放公開存取（Lab 用 true）"
  type        = bool
  default     = true
}

# ── Lab 保護 ──
variable "skip_final_snapshot" {
  description = "destroy 時跳過 final snapshot（Lab 設 true 省費用）"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "防止意外刪除（Lab 設 false）"
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "Multi-AZ 部署（Lab 設 false 省費用）"
  type        = bool
  default     = false
}
