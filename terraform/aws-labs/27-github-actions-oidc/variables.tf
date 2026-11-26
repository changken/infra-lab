variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "oidc-lab"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "github_org" {
  type        = string
  description = "GitHub 使用者名稱或 Organization 名稱（例如：changken）"
}

variable "github_repo" {
  type        = string
  description = "GitHub Repository 名稱（例如：infra-lab）"
}

variable "github_branch" {
  type        = string
  default     = "main"
  description = "允許觸發的分支。設為 \"*\" 允許所有分支（不建議用於生產環境）。"
}
