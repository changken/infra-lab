#--------------------------------------------------------------
# General Variables
#--------------------------------------------------------------

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "terraform-web-server"
}

#--------------------------------------------------------------
# EC2 Variables
#--------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

#--------------------------------------------------------------
# Network Variables
#--------------------------------------------------------------

variable "availability_zone" {
  description = "Availability zone for the default subnet"
  type        = string
  default     = "us-east-1a"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "118.150.143.171/32"
}

#--------------------------------------------------------------
# SSH Key Variables
#--------------------------------------------------------------

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "my-ec2-key"
}
