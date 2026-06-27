# ── 全域 ──────────────────────────────────────────────────

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS 部署區域"
}

variable "project" {
  type        = string
  default     = "windows-bastion"
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
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.1.0/24", "10.30.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.2.0/24", "10.30.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# ── Windows Instance ───────────────────────────────────────

variable "instance_type" {
  type        = string
  default     = "m5a.xlarge"
  description = "EC2 instance type（Windows 建議至少 m5a.xlarge）"
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
  default     = 50
  description = "Root EBS volume size in GB（Windows Server 2025 最低 30GB）"
}
