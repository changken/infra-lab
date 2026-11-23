variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（envs/oci-governance 的 output）"
  type        = string
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o09-kafka"
}

variable "stream_name" {
  description = "Kafka 相容 topic／OCI Stream 名稱"
  type        = string
  default     = "integration-events"
}

variable "partitions" {
  description = "Stream partitions；先用 1，增加 partition 前先思考 key ordering"
  type        = number
  default     = 1

  validation {
    condition     = var.partitions >= 1 && var.partitions <= 3
    error_message = "partitions 請介於 1～3；本 lab 不需要更多。"
  }
}

variable "retention_in_hours" {
  description = "事件保留時數；依 OCI Streaming 支援範圍與成本確認後調整"
  type        = number
  default     = 24

  validation {
    condition     = var.retention_in_hours >= 24 && var.retention_in_hours <= 168
    error_message = "retention_in_hours 請介於 24～168 小時。"
  }
}
