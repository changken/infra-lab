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
  default     = "az-avd"
  description = "專案名稱前綴，用於所有資源命名"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "環境標籤"
}

# ── 網路 ─────────────────────────────────────────────────────

variable "vnet_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.60.1.0/24"
}

# ── AVD Host Pool ─────────────────────────────────────────────

variable "host_pool_type" {
  type        = string
  default     = "Pooled"
  description = "Pooled（多人共用）或 Personal（個人專屬）"
}

variable "max_sessions" {
  type        = number
  default     = 5
  description = "每台 Session Host 最大同時連線數"
}

# ── Session Host VM ───────────────────────────────────────────

variable "vm_count" {
  type        = number
  default     = 1
  description = "Session Host VM 數量"
}

variable "vm_size" {
  type        = string
  default     = "Standard_E2as_v4"
  description = "Session Host VM 規格（Standard_E2as_v4: 2 vCPU / 16GB RAM，符合 japaneast 配額）"
}

variable "os_disk_size_gb" {
  type        = number
  default     = 128
  description = "OS 磁碟大小 GB"
}

variable "admin_username" {
  type        = string
  default     = "azureadmin"
  description = "VM 管理員帳號"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "VM 管理員密碼（建議至少 12 字元，含大小寫英文 + 數字 + 特殊符號）"
}
