variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ecr-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "my-app"
}

variable "max_image_count" {
  description = "Maximum number of images to keep in ECR"
  type        = number
  default     = 5
}
