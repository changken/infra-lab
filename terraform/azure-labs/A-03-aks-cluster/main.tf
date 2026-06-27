#--------------------------------------------------------------
# TODO 1: Resource Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group
#
# 需要設定：
#   name     = "${local.name_prefix}-rg"
#   location = var.location
#   tags     = local.common_tags

resource "azurerm_resource_group" "rg" {
  # TODO
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

#--------------------------------------------------------------
# TODO 2: AKS Cluster
#--------------------------------------------------------------
# 對比 AWS：aws_eks_cluster + aws_eks_node_group（EKS 拆成兩個資源）
# Azure：azurerm_kubernetes_cluster 一個資源包含 cluster + default node pool
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster
#
# 需要設定（頂層）：
#   name                = local.cluster_name
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   dns_prefix          = local.cluster_name   # cluster 的 DNS 前綴，隨意取
#   kubernetes_version  = var.kubernetes_version
#   tags                = local.common_tags
#
# default_node_pool block（必填，對比 EKS managed node group）：
#   name       = "system"          # 只能小寫英數，不超過 12 字
#   node_count = var.node_count
#   vm_size    = var.node_vm_size  # Standard_B2s
#
# identity block（讓 AKS 用 Managed Identity，對比 EKS 的 IAM Role）：
#   type = "SystemAssigned"
#
# oidc_issuer_enabled      = true   # A-04 Workload Identity 的前置條件
# workload_identity_enabled = true  # A-04 前置條件
#
# ⚠️ 注意：default_node_pool 建立後無法更名，只能 destroy 重建
# ⚠️ 注意：AKS apply 需要 5-10 分鐘，比 EKS 快一點

resource "azurerm_kubernetes_cluster" "aks" {
  # TODO
  name                = local.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  tags                = local.common_tags

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

#--------------------------------------------------------------
# TODO 3: Role Assignment — AKS 拉取 ACR image（選填）
#--------------------------------------------------------------
# 對比 AWS：EKS node group IAM role 附加 AmazonEC2ContainerRegistryReadOnly policy
# Azure：把 AcrPull role 指派給 AKS kubelet 的 Managed Identity
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
#
# 需要設定：
#   scope                = var.acr_id
#   role_definition_name = "AcrPull"
#   principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
#
# ⚠️ 注意：var.acr_id 為 null 時不應建立此資源，用 count 控制：
#   count = var.acr_id != null ? 1 : 0
#   scope = var.acr_id  （count = 0 時不會 evaluate）

resource "azurerm_role_assignment" "acr_pull" {
  # TODO（選填，acr_id 有值才需要）
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
