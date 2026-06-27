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
  description = "專案名稱，用於命名與 tag"
  type        = string
  default     = "acr-lab"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

variable "acr_sku" {
  description = "ACR SKU：Basic（$0.167/天）/ Standard / Premium"
  type        = string
  default     = "Basic"
}

variable "admin_enabled" {
  description = "啟用 admin 帳密登入（練習用）。生產環境改用 Managed Identity"
  type        = bool
  default     = true
}

variable "image_name" {
  description = "要 build 並推送的 image 名稱"
  type        = string
  default     = "hello-azure"
}

variable "image_tag" {
  description = "Image tag"
  type        = string
  default     = "v1"
}
