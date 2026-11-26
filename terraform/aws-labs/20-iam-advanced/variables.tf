variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name (used for resource naming)"
  type        = string
  default     = "iam-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
