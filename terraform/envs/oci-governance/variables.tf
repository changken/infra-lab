variable "region" {
  description = "OCI region（IAM 資源屬 home region）"
  type        = string
  default     = "ap-singapore-1"
}

variable "tenancy_id" {
  description = "Tenancy (root compartment) OCID"
  type        = string
}

variable "home_ip_cidr" {
  description = "homelab 對外 IP（/32），用於 Network Source，限制 grab-bots 只能從此 IP 操作"
  type        = string
}

variable "budget_alert_email" {
  description = "預算超標通知收件者 email"
  type        = string
}
