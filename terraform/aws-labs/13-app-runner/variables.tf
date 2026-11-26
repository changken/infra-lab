variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "apprunner-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ecr_image_url" {
  description = "ECR image URL（來自 Lab 10）, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "vCPU for App Runner service (valid: '0.25 vCPU', '0.5 vCPU', '1 vCPU', '2 vCPU', '4 vCPU')"
  type        = string
  default     = "0.25 vCPU"
}

variable "memory" {
  description = "Memory for App Runner service (valid: '0.5 GB', '1 GB', '2 GB', ...)"
  type        = string
  default     = "0.5 GB"
}
