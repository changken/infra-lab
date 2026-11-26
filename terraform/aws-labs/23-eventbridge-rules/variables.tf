variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "eventbridge-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "schedule_expression" {
  type        = string
  default     = "rate(2 minutes)"
  description = "排程觸發頻率。rate(N unit) 或 cron(分 時 日 月 週 年)。測試用 rate(2 minutes) 即可。"
}
