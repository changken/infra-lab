variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "japaneast"
}

variable "project" {
  description = "專案名稱，用於命名與 tag"
  type        = string
  default     = "aks-lab"
}

variable "environment" {
  description = "環境名稱"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes 版本（留空使用 Azure 預設最新穩定版）"
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "Node VM 大小（Standard_B2s = $0.048/hr，最便宜可用的 AKS node）"
  type        = string
  default     = "Standard_B2s"
}

variable "node_count" {
  description = "Node 數量（學習用 1 個即可）"
  type        = number
  default     = 1
}

variable "acr_id" {
  description = "A-02 建立的 ACR resource ID（選填，設定後 AKS 可直接拉 ACR image）"
  type        = string
  default     = null
}
