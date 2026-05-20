variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name (used in tags and resource names)"
  type        = string
  default     = "dynamo-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "orders"
}

variable "ttl_enabled" {
  description = "Enable TTL (Time-to-Live) on the table"
  type        = bool
  default     = true
}
