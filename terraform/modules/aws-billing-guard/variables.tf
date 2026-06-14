variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "billing-guard"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "budget_limit_amount" {
  description = "月消費警戒線（USD）。超過此金額觸發 Lambda 清理 RDS"
  type        = number
  default     = 38
}

variable "alert_email" {
  description = "帳單告警通知 Email"
  type        = string
}

variable "dry_run" {
  description = "true = 只 log 不執行刪除（測試用）"
  type        = bool
  default     = false
}
