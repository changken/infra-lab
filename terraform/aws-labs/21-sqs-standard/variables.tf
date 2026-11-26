variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "sqs-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 30
  description = "訊息被消費者拿走後，其他消費者看不到的時間（秒）。應 >= Lambda timeout。"
}

variable "max_receive_count" {
  type        = number
  default     = 3
  description = "訊息被接收幾次後仍未刪除，就移入 DLQ。"
}
