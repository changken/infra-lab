variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "order-backend"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "notification_email" {
  description = "Email address to receive order notifications"
  type        = string
}
