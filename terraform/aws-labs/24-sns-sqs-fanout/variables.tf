variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "fanout-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "max_receive_count" {
  type        = number
  default     = 3
  description = "SQS 訊息失敗幾次後移入 DLQ。"
}
