# ── GCP 專案 ───────────────────────────────────────────────

variable "project_id" {
  type        = string
  description = "GCP 專案 ID（例如 my-project-123456）"
}

# ── 全域 ──────────────────────────────────────────────────

variable "project" {
  type        = string
  default     = "gcp-linux"
  description = "資源命名前綴與標籤"
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

variable "ssh_user" {
  type        = string
  default     = "devuser"
  description = "SSH 登入使用者名稱（GCP 不允許用 root 直接登入）"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH 公鑰內容（例如 ~/.ssh/id_rsa.pub 的內容）"
}

# ── VM 設定 ────────────────────────────────────────────────

variable "region" {
  type        = string
  default     = "asia-east1"
  description = "GCP Region（asia-east1=台灣、asia-northeast1=東京、asia-southeast1=新加坡）"
}

variable "zone" {
  type        = string
  default     = "asia-east1-b"
  description = "GCP Zone（需與 region 一致，例如 asia-east1-b）"
}

variable "machine_type" {
  type        = string
  default     = "e2-micro"
  description = "機器類型（e2-micro=Free Tier 可用 ~$6/月、e2-small ~$12/月）"
}

variable "boot_image" {
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  description = "開機映像（ubuntu-os-cloud/ubuntu-2404-lts-amd64、debian-cloud/debian-12）"
}

variable "disk_size_gb" {
  type        = number
  default     = 20
  description = "開機磁碟大小（GB），Free Tier 單月 30GB 以內免費"
}

variable "instance_name" {
  type        = string
  default     = "gcp-dev-vm"
  description = "VM Instance 名稱（需符合 RFC1035：小寫英數 + 連字號）"
}
