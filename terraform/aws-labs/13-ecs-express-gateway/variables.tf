variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ecs-express-lab"
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
  description = "CPU units for the task (e.g. '256', '512', '1024')"
  type        = string
  default     = "256"
}

variable "memory" {
  description = "Memory in MiB for the task (e.g. '512', '1024')"
  type        = string
  default     = "512"
}
