variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "r53-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "health_check_fqdn" {
  description = "FQDN for Route 53 HTTP health check（必須是公開可連線的域名）"
  type        = string
  default     = "example.com"
}
