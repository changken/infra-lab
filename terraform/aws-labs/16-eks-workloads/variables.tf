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
  description = "Project name (used for Kubernetes resource naming)"
  type        = string
  default     = "eks-workloads"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "namespace_name" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "demo"
}

variable "app_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:alpine"
}

variable "replica_count" {
  description = "Number of pod replicas"
  type        = number
  default     = 2
}
