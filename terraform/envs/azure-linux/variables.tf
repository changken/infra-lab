# ── 全域 ──────────────────────────────────────────────────

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID（執行 az account show --query id -o tsv 取得）"
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "Azure 部署區域"
}

variable "project" {
  type        = string
  default     = "az-linux-bastion"
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
    condition     = can(cidrhost(var.my_ip, 0)) && tonumber(split("/", var.my_ip)[1]) >= 16
    error_message = "必須是合法的 CIDR 格式且 prefix >= 16，例如 1.2.3.4/32"
  }
}

variable "vnet_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "public_subnets" {
  type    = map(string)
  default = { "public-1" = "10.40.1.0/24" }
}

variable "private_subnets" {
  type    = map(string)
  default = { "private-1" = "10.40.11.0/24" }
}

# ── Linux VM ───────────────────────────────────────────────

variable "vm_size" {
  type        = string
  default     = "Standard_B1s"
  description = "Azure VM 規格（Free Tier 等級：Standard_B1s ~$0.01/hr）"
}

variable "os_disk_size_gb" {
  type        = number
  default     = 30
  description = "OS 磁碟大小 GB（最少 30）"
}

variable "admin_ssh_public_key" {
  type        = string
  default     = null
  description = "SSH 公鑰（OpenSSH 格式）。不填則自動生成金鑰，私鑰存至本地 .pem 檔"
  sensitive   = true
}
