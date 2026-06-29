# ── 認證 ──────────────────────────────────────────────────

variable "linode_token" {
  type        = string
  description = "Linode Personal Access Token（從 cloud.linode.com > Profile > API Tokens 取得）"
  sensitive   = true
}

# ── 全域 ──────────────────────────────────────────────────

variable "project" {
  type        = string
  default     = "linode-linux"
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

# ── Instance 設定 ──────────────────────────────────────────

variable "region" {
  type        = string
  default     = "ap-southeast"
  description = "Linode 區域（ap-southeast=新加坡、us-east=紐約、eu-central=法蘭克福）"
}

variable "type" {
  type        = string
  default     = "g6-nanode-1"
  description = "Instance 規格（g6-nanode-1=1vCPU/1GB ~$5/月、g6-standard-1=1vCPU/2GB ~$10/月）"
}

variable "image" {
  type        = string
  default     = "linode/ubuntu24.04"
  description = "作業系統映像（linode/ubuntu24.04、linode/ubuntu22.04、linode/debian12）"
}

variable "label" {
  type        = string
  default     = "linode-dev"
  description = "Instance 顯示名稱"
}

variable "backups_enabled" {
  type        = bool
  default     = false
  description = "是否啟用自動備份（額外收費，約 Instance 費用的 20%）"
}

variable "swap_size" {
  type        = number
  default     = 512
  description = "Swap 磁碟大小（MB）"
}
