variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "rds-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Master username"
  type        = string
  default     = "labadmin"
}

variable "db_password" {
  description = "Master password — set in terraform.tfvars, never commit"
  type        = string
  sensitive   = true
}

variable "db_port" {
  type    = number
  default = 5432
}
