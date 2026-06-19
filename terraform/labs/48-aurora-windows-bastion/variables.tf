#==============================================================
# Lab 48 - Variables
#==============================================================

# ── 全域 ──────────────────────────────────────────────────

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS 部署區域"
}

variable "project" {
  type        = string
  default     = "aurora-win-lab"
  description = "專案名稱前綴，用於所有資源命名"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "環境標籤"
}

# ── 網路 ──────────────────────────────────────────────────

variable "my_ip" {
  type        = string
  description = "你的公網 IP（CIDR 格式），用於限制 RDP 連入。例如：1.2.3.4/32"
  validation {
    condition     = can(cidrhost(var.my_ip, 0))
    error_message = "必須是合法的 CIDR 格式，例如 1.2.3.4/32"
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.2.0/24", "10.10.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# ── Windows Spot ──────────────────────────────────────────

variable "windows_instance_type" {
  type    = string
  default = "m5a.xlarge"
}

variable "windows_market_type" {
  type    = string
  default = "spot"
}

# ── Aurora PostgreSQL ─────────────────────────────────────

variable "aurora_engine_version" {
  type    = string
  default = "15.4"
}

variable "aurora_min_acu" {
  type    = number
  default = 0.5
}

variable "aurora_max_acu" {
  type    = number
  default = 2.0
}

variable "db_name" {
  type    = string
  default = "mydb"
}

variable "db_username" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Aurora 管理者密碼，請設於 terraform.tfvars，禁止 commit"
}
