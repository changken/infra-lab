variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "japaneast"
}

variable "project" {
  description = "專案名稱"
  type        = string
  default     = "sql-lab"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

variable "admin_login" {
  description = "SQL Server 管理員帳號（不能用 admin / sa / root 等保留字）"
  type        = string
  default     = "sqladmin"
}

variable "admin_password" {
  description = "SQL Server 管理員密碼（長度 8+，含大小寫、數字、特殊符號）"
  type        = string
  sensitive   = true
}

variable "min_capacity" {
  description = "Serverless 最小 vCore 數（最小 0.5，閒置時降到此值）"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Serverless 最大 vCore 數（決定效能上限）"
  type        = number
  default     = 1
}

variable "auto_pause_delay_minutes" {
  description = "閒置幾分鐘後自動暫停（-1 = 停用暫停功能，60 = 1 小時）"
  type        = number
  default     = 60
}

variable "allowed_client_ip" {
  description = "允許連入的用戶端 IP（留空則只允許 Azure 內部服務）"
  type        = string
  default     = ""
}
