variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (must match Lab 15 output)"
  type        = string
  default     = "eks-lab"
}

variable "project" {
  description = "Project name (used for resource naming)"
  type        = string
  default     = "eks-irsa"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "namespace_name" {
  description = "Kubernetes namespace for the demo app"
  type        = string
  default     = "irsa-demo"
}
