output "cluster_name" {
  description = "AKS cluster 名稱"
  # TODO: azurerm_kubernetes_cluster.aks.name
  value = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = azurerm_resource_group.rg.name
}

output "kube_config_cmd" {
  description = "取得 kubeconfig 的 az 指令（對比 aws eks update-kubeconfig）"
  # TODO: 組合成 "az aks get-credentials --resource-group <rg> --name <cluster>" 字串
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "oidc_issuer_url" {
  description = "OIDC Issuer URL（A-04 Workload Identity 會用到）"
  # TODO: azurerm_kubernetes_cluster.aks.oidc_issuer_url
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet Managed Identity object_id（用於 AcrPull role assignment）"
  # TODO: azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  value = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
