variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "auth-lab"
  # ⚠️ 不能包含 "cognito" 等 AWS 保留字（會影響 User Pool Domain 名稱）
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
