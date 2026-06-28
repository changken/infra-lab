variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure Tenant ID (Entra ID)"
  type        = string
}

variable "location" {
  description = "Azure region（Service Connection 的 RG 位置）"
  type        = string
  default     = "japaneast"
}

variable "project" {
  description = "專案名稱"
  type        = string
  default     = "ado-lab"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

# ── Azure DevOps 設定 ─────────────────────────────────────────
variable "azuredevops_org_url" {
  description = "Azure DevOps 組織 URL，e.g. https://dev.azure.com/myorg"
  type        = string
}

variable "azuredevops_pat" {
  description = "Azure DevOps Personal Access Token（需要 Project、Build、Service Endpoints 權限）"
  type        = string
  sensitive   = true
}

variable "devops_project_name" {
  description = "要建立的 Azure DevOps 專案名稱"
  type        = string
  default     = "azure-labs-pipeline"
}

# ── 串接 A-02 ACR（選填）────────────────────────────────────
variable "acr_name" {
  description = "A-02 的 ACR 名稱（選填，pipeline 推送 image 用）"
  type        = string
  default     = ""
}

variable "acr_resource_group" {
  description = "A-02 的 ACR 所在 Resource Group（acr_name 有值時必填）"
  type        = string
  default     = ""
}
