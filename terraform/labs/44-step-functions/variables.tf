variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "sfn-lab"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "notification_email" {
  description = "Email for order notifications (optional — subscribe to SNS topic)"
  type        = string
  default     = ""
}
