variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "192.168.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["192.168.2.0/24", "192.168.4.0/24"]
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets into (must match length of public/private subnet CIDRs)"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPC"
  type        = bool
  default     = true
}

variable "personal_pc_cidr" {
  description = "CIDR block of your personal PC for AWS access"
  type        = string
  default     = "100.0.0.1/32"
}
