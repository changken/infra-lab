variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region（需與 A-03 AKS 相同）"
  type        = string
  default     = "japaneast"
}

variable "project" {
  description = "專案名稱"
  type        = string
  default     = "wi-lab"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

# ── 從 A-03 取得的值（terraform output） ──────────────────────────
variable "aks_oidc_issuer_url" {
  description = "A-03 的 OIDC Issuer URL（terraform output -raw oidc_issuer_url）"
  type        = string
}

variable "aks_cluster_name" {
  description = "A-03 的 AKS cluster 名稱（terraform output -raw cluster_name）"
  type        = string
}

variable "aks_resource_group_name" {
  description = "A-03 的 Resource Group 名稱（terraform output -raw resource_group_name）"
  type        = string
}
# ─────────────────────────────────────────────────────────────────

variable "namespace" {
  description = "Kubernetes namespace（Pod 執行的 namespace）"
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount 名稱（與 Federated Credential 綁定）"
  type        = string
  default     = "workload-identity-sa"
}

variable "key_vault_secret_value" {
  description = "測試用 Key Vault secret 的值"
  type        = string
  default     = "hello-from-keyvault"
  sensitive   = true
}
