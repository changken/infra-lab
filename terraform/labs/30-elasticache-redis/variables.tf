variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "redis-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
  # 費用參考：cache.t3.micro = $0.017/hr，練完立刻 destroy！
}
