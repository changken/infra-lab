variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Must be a valid AWS region (e.g. us-east-1)."
  }
}

variable "name_prefix" {
  type        = string
  default     = "win2025"
  description = "Prefix for all resource names to avoid collision across environments."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment (e.g. dev, staging, prod)."
}

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR notation, e.g. 1.2.3.4/32"
  validation {
    condition     = can(cidrhost(var.my_ip, 0))
    error_message = "Must be a valid CIDR block (e.g. 1.2.3.4/32)."
  }
}

variable "instance_type" {
  type        = string
  default     = "m5a.xlarge"
  description = "EC2 instance type for the Spot instance."
}

variable "market_type" {
  type        = string
  default     = "spot"
  description = "Instance market type: \"spot\" or \"on-demand\"."
  validation {
    condition     = contains(["spot", "on-demand"], var.market_type)
    error_message = "market_type must be \"spot\" or \"on-demand\"."
  }
}

variable "spot_max_price" {
  type        = string
  default     = null
  description = "Max spot price in USD. null = on-demand price cap."
  validation {
    condition     = var.spot_max_price == null || can(tonumber(var.spot_max_price))
    error_message = "spot_max_price must be null or a numeric string like \"0.10\"."
  }
}

variable "root_volume_size" {
  type        = number
  default     = 50
  description = "Root EBS volume size in GB (minimum 30 for Windows Server 2025)."
  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GB for Windows Server 2025."
  }
}

variable "public_key_content" {
  type        = string
  default     = null
  description = "SSH public key (OpenSSH format). If null, a key pair is auto-generated (private key stored in tfstate)."
  sensitive   = true
}
