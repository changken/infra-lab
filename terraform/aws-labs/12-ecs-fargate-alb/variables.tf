variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ecs-alb-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ecr_image_url" {
  description = "ECR image URL（來自 Lab 10）, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:latest"
  type        = string
}

variable "container_name" {
  description = "Container name in task definition"
  type        = string
  default     = "my-app"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "CPU units for Fargate task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MB) for Fargate task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of task instances to run"
  type        = number
  default     = 1
}
