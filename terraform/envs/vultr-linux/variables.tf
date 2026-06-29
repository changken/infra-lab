# ── 認證 ──────────────────────────────────────────────────

variable "api_key" {
  type        = string
  description = "Vultr API Key（從 Vultr 控制台 Account > API 取得）"
  sensitive   = true
}

# ── 全域 ──────────────────────────────────────────────────

variable "project" {
  type        = string
  default     = "vultr-linux"
  description = "專案名稱前綴，用於資源命名與標籤"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "環境標籤（dev / staging / prod）"
}

# ── 網路與存取 ─────────────────────────────────────────────

variable "my_ip" {
  type        = string
  description = "你的公網 IP（CIDR 格式），用於限制 SSH 連入。例如：1.2.3.4/32"
  validation {
    condition     = can(cidrhost(var.my_ip, 0))
    error_message = "必須是合法的 CIDR 格式，例如 1.2.3.4/32"
  }
}

variable "ssh_public_key" {
  type        = string
  description = "SSH 公鑰內容（例如 ~/.ssh/id_rsa.pub 的內容）"
}

# ── 實例設定 ───────────────────────────────────────────────

variable "region" {
  type        = string
  default     = "nrt"
  description = "Vultr 區域代碼（nrt=東京、sgp=新加坡、ewr=紐澤西）"
}

variable "plan" {
  type        = string
  default     = "vc2-1c-1gb"
  description = "實例規格（vc2-1c-1gb ~$6/月、vc2-1c-2gb ~$12/月）"
}

variable "os_id" {
  type        = number
  default     = 1743
  description = "作業系統 ID（1743 = Ubuntu 22.04 LTS x64）"
}

variable "hostname" {
  type        = string
  default     = "vultr-dev"
  description = "主機名稱（修改後會觸發 force-replace，請謹慎更改）"
}

variable "enable_ipv6" {
  type        = bool
  default     = false
  description = "是否啟用 IPv6"
}

variable "backups" {
  type        = string
  default     = "disabled"
  description = "自動備份（enabled 會額外收費，disabled 停用）"
  validation {
    condition     = contains(["enabled", "disabled"], var.backups)
    error_message = "backups 必須是 \"enabled\" 或 \"disabled\""
  }
}
