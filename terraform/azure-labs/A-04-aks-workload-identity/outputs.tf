output "identity_client_id" {
  description = "User Assigned Identity 的 client_id（kubectl annotation 用）"
  # TODO: azurerm_user_assigned_identity.workload.client_id
  value = null
}

output "key_vault_name" {
  description = "Key Vault 名稱"
  # TODO: azurerm_key_vault.kv.name
  value = null
}

output "key_vault_uri" {
  description = "Key Vault URI（Pod 連線用）"
  # TODO: azurerm_key_vault.kv.vault_uri
  value = null
}

output "service_account_manifest" {
  description = "要 apply 到 AKS 的 ServiceAccount YAML"
  value       = <<-EOT
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: ${var.service_account_name}
      namespace: ${var.namespace}
      annotations:
        azure.workload.identity/client-id: <填入 identity_client_id output>
    EOT
}

output "test_pod_manifest" {
  description = "驗證用 Pod YAML（讀取 Key Vault secret）"
  value       = <<-EOT
    apiVersion: v1
    kind: Pod
    metadata:
      name: wi-test
      namespace: ${var.namespace}
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: ${var.service_account_name}
      containers:
      - name: wi-test
        image: mcr.microsoft.com/azure-cli
        command: ["sleep", "3600"]
    EOT
}
