# ============================================================================
# AWS Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region for EC2 instances"
  type        = string
  default     = "us-east-1"
}

variable "cp_instance_type" {
  description = "K3s control plane EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "K3s worker node EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
  default     = 2
}

variable "aws_ssh_public_key_path" {
  description = "Path to emergency SSH public key for AWS EC2 access"
  type        = string
  default     = "./.ssh/aws_emergency_ed25519.pub"
}

variable "aws_availability_zone" {
  description = "AWS availability zone (empty = auto-select)"
  type        = string
  default     = ""
}

variable "cp_hostname" {
  description = "Hostname for K3s control plane node"
  type        = string
  default     = "my-cp"
}

variable "worker_hostname_prefix" {
  description = "Hostname prefix for K3s worker nodes (e.g. my-worker → my-worker-1, my-worker-2)"
  type        = string
  default     = "my-worker"
}

variable "ssh_allowed_cidr" {
  description = "Your public IP in CIDR format for emergency SSH access (e.g. 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"  # 建議改成你的 IP/32
}
