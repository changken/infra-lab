variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ecs-rds-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ecr_image_url" {
  description = "ECR image URL（本 lab 的 Flask app image，需自行 build + push）"
  type        = string
}

variable "container_name" {
  type    = string
  default = "flask-app"
}

variable "container_port" {
  description = "Flask app port"
  type        = number
  default     = 5000
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

# RDS 設定
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "PostgreSQL admin password（請勿使用 @ # / 等特殊字元）"
  type        = string
  sensitive   = true
}
