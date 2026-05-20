variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name (used in tags and bucket prefix)"
  type        = string
  default     = "s3-site-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "bucket_name_prefix" {
  description = "S3 bucket name prefix (will be suffixed with a random hex)"
  type        = string
  default     = "my-static-site"
}

variable "index_document" {
  description = "Default index document for the website"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for the website"
  type        = string
  default     = "error.html"
}
