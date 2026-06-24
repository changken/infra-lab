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
  description = "CIDR block for the VPC (use 10.1.0.0/16 to avoid conflict with EKS lab)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "azs" {
  description = "Availability zones for public subnets (exactly 2 for ALB)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) >= 2
    error_message = "ALB requires subnets in at least 2 Availability Zones."
  }
}

# ── Container ────────────────────────────────────────────────

variable "container_image" {
  description = "Container image URI. 初始用 nginx 佔位，apply 後換成 ECR image。"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable-alpine"
}

variable "container_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Fargate task memory in MiB (minimum 512 for 256 CPU)"
  type        = number
  default     = 512
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "app_version" {
  description = "App version injected as APP_VERSION env var"
  type        = string
  default     = "1.0.0"
}

# ── ECS Service ──────────────────────────────────────────────

variable "service_desired_count" {
  description = "Desired number of running ECS tasks"
  type        = number
  default     = 2
}

# ── Auto Scaling ─────────────────────────────────────────────

variable "autoscaling_min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 5
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization (%) for auto scaling"
  type        = number
  default     = 70
}

variable "autoscaling_memory_target" {
  description = "Target memory utilization (%) for auto scaling"
  type        = number
  default     = 80
}

# ── GitHub OIDC ──────────────────────────────────────────────

variable "health_check_path" {
  description = "ALB health check path (/ for nginx, /health for the Go app)"
  type        = string
  default     = "/health"
}

variable "github_repo" {
  description = "GitHub repo in 'owner/name' format for OIDC trust (e.g. changken/ecs-app)"
  type        = string
  default     = "changken/ecs-app"
}
