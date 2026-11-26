variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "cicd-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' (e.g. 'myorg/my-app'). Used to restrict which repo can assume the IAM Role."
  type        = string
}
