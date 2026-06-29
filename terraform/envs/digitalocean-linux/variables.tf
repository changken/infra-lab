# ── 認證 ──────────────────────────────────────────────────

variable "do_token" {
  type        = string
  description = "DigitalOcean API Token（從 DO 控制台 API > Generate New Token 取得）"
  sensitive   = true
}

# ── 全域 ──────────────────────────────────────────────────

variable "project" {
  type        = string
  default     = "do-linux"
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

# ── Droplet 設定 ───────────────────────────────────────────

variable "region" {
  type        = string
  default     = "sgp1"
  description = "DO 區域代碼（sgp1=新加坡、nrt1=東京、nyc3=紐約、sfo3=舊金山）"
}

variable "size" {
  type        = string
  default     = "s-1vcpu-1gb"
  description = "Droplet 規格 slug（s-1vcpu-1gb ~$6/月、s-1vcpu-2gb ~$12/月）"
}

variable "image" {
  type        = string
  default     = "ubuntu-22-04-x64"
  description = "作業系統映像 slug（ubuntu-22-04-x64、debian-12-x64）"
}

variable "droplet_name" {
  type        = string
  default     = "do-dev-vm"
  description = "Droplet 名稱"
}

variable "ipv6" {
  type        = bool
  default     = false
  description = "是否啟用 IPv6（啟用後無法關閉）"
}

variable "monitoring" {
  type        = bool
  default     = true
  description = "是否安裝 DO 監控代理程式（免費，建議開啟）"
}

variable "backups" {
  type        = bool
  default     = false
  description = "是否啟用自動備份（額外收費，約 Droplet 費用的 20%）"
}
