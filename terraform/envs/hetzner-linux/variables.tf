# ── 認證 ──────────────────────────────────────────────────

variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API Token（從 Cloud Console > 專案 > Security > API Tokens 取得）"
  sensitive   = true
}

# ── 全域 ──────────────────────────────────────────────────

variable "project" {
  type        = string
  default     = "hetzner-linux"
  description = "專案名稱前綴，用於資源命名與 labels"
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

# ── Server 設定 ────────────────────────────────────────────

variable "location" {
  type        = string
  default     = "sin"
  description = "Hetzner 資料中心位置（sin=新加坡、fsn1=德國、hel1=芬蘭、ash=美國維吉尼亞）"
}

variable "server_type" {
  type        = string
  default     = "cx22"
  description = "Server 規格（cx22=2vCPU/4GB ~€3.79/月、cx32=4vCPU/8GB ~€6.52/月）"
}

variable "image" {
  type        = string
  default     = "ubuntu-24.04"
  description = "作業系統映像名稱（ubuntu-24.04、ubuntu-22.04、debian-12）"
}

variable "server_name" {
  type        = string
  default     = "hetzner-dev"
  description = "Server 名稱（必須是合法的 RFC 1123 hostname）"
}

variable "backups" {
  type        = bool
  default     = false
  description = "是否啟用自動備份（額外收費，約 Server 費用的 20%）"
}
