# ── 全域 ──────────────────────────────────────────────────

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS 部署區域"
}

variable "project" {
  type        = string
  default     = "linux-bastion"
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
  description = "你的公網 IP（CIDR 格式），用於限制 SSH 連入。例如：1.2.3.4/32"
  validation {
    condition     = can(cidrhost(var.my_ip, 0))
    error_message = "必須是合法的 CIDR 格式，例如 1.2.3.4/32"
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.2.0/24", "10.20.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# ── Linux Instance ─────────────────────────────────────────

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type（Free Tier: t2.micro / t3.micro）"
}

variable "market_type" {
  type        = string
  default     = "spot"
  description = "\"spot\" 省錢但可能被中斷；\"on-demand\" 穩定但較貴"
  validation {
    condition     = contains(["spot", "on-demand"], var.market_type)
    error_message = "market_type must be \"spot\" or \"on-demand\"."
  }
}

variable "root_volume_size" {
  type        = number
  default     = 20
  description = "Root EBS volume size in GB"
}
