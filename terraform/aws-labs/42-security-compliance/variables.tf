variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "sec-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "notification_email" {
  description = "Security alert notification email (optional, leave empty to skip SNS subscription)"
  type        = string
  default     = ""
}
