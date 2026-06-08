variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "eks-template"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS cluster and managed node group. Use at least two subnets in different AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires at least two subnet IDs in different Availability Zones."
  }
}

variable "endpoint_public_access" {
  description = "Enable public access to the Kubernetes API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Enable private access to the Kubernetes API server endpoint"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public Kubernetes API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "compute_mode" {
  description = "EKS compute mode: ec2 creates a managed node group, fargate creates an EKS Fargate profile"
  type        = string
  default     = "ec2"

  validation {
    condition     = contains(["ec2", "fargate"], var.compute_mode)
    error_message = "compute_mode must be either ec2 or fargate."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 20
}

variable "node_capacity_type" {
  description = "Capacity type for worker nodes: ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be either ON_DEMAND or SPOT."
  }
}

variable "fargate_profile_name" {
  description = "Name suffix for the EKS Fargate profile"
  type        = string
  default     = "default"
}

variable "fargate_subnet_ids" {
  description = "Subnet IDs for the EKS Fargate profile. If empty, subnet_ids will be used. Private subnets are recommended for Fargate pods."
  type        = list(string)
  default     = []
}

variable "fargate_selectors" {
  description = "Kubernetes namespace and optional labels matched by the EKS Fargate profile"
  type = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  default = [
    {
      namespace = "default"
      labels    = {}
    },
    {
      namespace = "kube-system"
      labels = {
        k8s-app = "kube-dns"
      }
    }
  ]

  validation {
    condition     = length(var.fargate_selectors) > 0
    error_message = "fargate_selectors must contain at least one selector."
  }
}

variable "tags" {
  description = "Additional tags applied to all supported resources"
  type        = map(string)
  default     = {}
}
