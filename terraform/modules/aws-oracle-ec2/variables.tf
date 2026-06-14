variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "oracle-ec2-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium (4GB RAM) 是最低建議規格"
  type        = string
  default     = "t3.medium"
}

variable "oracle_password" {
  description = "Oracle SYS/SYSTEM 密碼 — 設在 terraform.tfvars，禁止 commit"
  type        = string
  sensitive   = true
}

variable "allowed_cidr" {
  description = "允許連入 Oracle port 1521 的 CIDR"
  type        = string
  default     = "118.150.143.171/32"
}
