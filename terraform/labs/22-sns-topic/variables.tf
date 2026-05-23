variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "sns-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "notification_email" {
  type        = string
  description = "接收 SNS Email 通知的信箱（apply 後需要點擊確認信才會生效）"
}
