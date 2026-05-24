variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "pipeline-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "task_cpu" {
  type        = number
  default     = 256
  description = "ECS Task CPU（256 = 0.25 vCPU）"
}

variable "task_memory" {
  type        = number
  default     = 512
  description = "ECS Task Memory（MB）"
}
