variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for resource naming and tags"
  type        = string
  default     = "infra-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# ── VPC ─────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones for public and private subnets (exactly 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) >= 2
    error_message = "EKS requires subnets in at least 2 Availability Zones."
  }
}

# ── EKS ─────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type: ON_DEMAND or SPOT"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
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
  description = "Root EBS disk size in GiB per node"
  type        = number
  default     = 20
}

variable "enable_console_access" {
  description = "Grant the Terraform caller EKS cluster-admin access (for AWS Console + kubectl)"
  type        = bool
  default     = true
}

# ── Karpenter ───────────────────────────────────────────────

variable "karpenter_version" {
  description = "Karpenter Helm chart version（對應 github.com/aws/karpenter/releases）"
  type        = string
  default     = "1.3.3"
}

# ── AWS Load Balancer Controller ────────────────────────────

variable "aws_lbc_version" {
  description = "AWS Load Balancer Controller version (used to fetch the IAM policy from GitHub)"
  type        = string
  default     = "v2.7.2"
}
