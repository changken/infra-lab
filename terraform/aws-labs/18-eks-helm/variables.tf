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
  description = "Project name"
  type        = string
  default     = "eks-helm"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "metrics_server_version" {
  description = "Helm chart version for metrics-server (check: https://artifacthub.io/packages/helm/metrics-server/metrics-server)"
  type        = string
  default     = "3.12.1"
}

variable "ingress_nginx_version" {
  description = "Helm chart version for ingress-nginx (check: https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)"
  type        = string
  default     = "4.10.1"
}
