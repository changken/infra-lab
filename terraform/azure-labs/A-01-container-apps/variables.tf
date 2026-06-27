variable "subscription_id" {
  description = "Azure Subscription ID（貼上你的 Student subscription ID）"
  type        = string
}

variable "location" {
  description = "Azure region（Student 帳號推薦 japaneast）"
  type        = string
  default     = "japaneast"
}

variable "project" {
  description = "專案名稱，用於命名與 tag"
  type        = string
  default     = "aca-lab"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

variable "container_image" {
  description = "要部署的 container image（預設用公開的 nginx）"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Container 監聽的 port"
  type        = number
  default     = 80
}

variable "min_replicas" {
  description = "最少 replica 數（設 0 可縮到零，完全免費）"
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "最多 replica 數"
  type        = number
  default     = 1
}
