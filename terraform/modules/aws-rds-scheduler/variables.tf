variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "rds-scheduler"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "alert_email" {
  description = "RDS 啟動/停止通知 Email"
  type        = string
}

# cron 預設為台灣時間（UTC+8）
# 停止：00:00 CST = 16:00 UTC → cron(0 16 * * ? *)
# 啟動：08:00 CST = 00:00 UTC → cron(0 0  * * ? *)
variable "stop_cron" {
  description = "EventBridge cron 表達式（UTC）：停止 RDS 的時間"
  type        = string
  default     = "cron(0 16 * * ? *)"
}

variable "start_cron" {
  description = "EventBridge cron 表達式（UTC）：啟動 RDS 的時間"
  type        = string
  default     = "cron(0 0 * * ? *)"
}
