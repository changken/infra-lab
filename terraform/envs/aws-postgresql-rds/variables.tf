variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "pgsql-rds"
}

variable "environment" {
  type    = string
  default = "dev"
}

# ── RDS Instance ──

variable "instance_class" {
  description = "RDS instance type. db.t3.micro 符合 Free Tier；db.t3.small 給較大工作負載"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Storage in GB (min 20)"
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

# ── 資料庫認證 ──

variable "db_name" {
  description = "初始資料庫名稱（小寫英數字）"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "pgadmin"
}

variable "db_password" {
  description = "Master password — 設在 terraform.tfvars，禁止 commit"
  type        = string
  sensitive   = true
}

# ── 網路 ──

variable "allowed_cidr" {
  description = "允許連入 PostgreSQL port 5432 的 CIDR（你的 IP，例如 1.2.3.4/32）"
  type        = string
  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], var.allowed_cidr) && tonumber(split("/", var.allowed_cidr)[1]) >= 24
    error_message = "allowed_cidr 必須是具體的 CIDR（前綴長度 >= /24），不允許 0.0.0.0/0。"
  }
}

variable "publicly_accessible" {
  description = "RDS 是否開放公開存取（需要從外部連線時才設 true）"
  type        = bool
  default     = false
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
