variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "lambda-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "function_name" {
  description = "Lambda function name"
  type        = string
  default     = "hello-world"
}
