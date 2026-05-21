variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "s3-trigger-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "function_name" {
  type    = string
  default = "s3-file-processor"
}
