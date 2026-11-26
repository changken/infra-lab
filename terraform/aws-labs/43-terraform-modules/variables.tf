variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix（傳入所有 modules）"
  type        = string
  default     = "tf-lab"
}

variable "environment" {
  description = "Environment name（傳入所有 modules）"
  type        = string
  default     = "dev"
}

variable "notification_email" {
  description = "Alarm notification email (optional)"
  type        = string
  default     = ""
}
