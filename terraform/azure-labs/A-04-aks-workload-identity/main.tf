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
}

#--------------------------------------------------------------
# TODO 2: User Assigned Managed Identity
#--------------------------------------------------------------
# 對比 AWS：IAM Role（IRSA 讓 Pod 扮演的角色）
# Azure：User Assigned Identity 是一個獨立資源，可附加到多個服務
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity
#
# 需要設定：
#   name                = "${local.name_prefix}-identity"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   tags                = local.common_tags

resource "azurerm_user_assigned_identity" "workload" {
  # TODO
}

#--------------------------------------------------------------
# TODO 3: Federated Identity Credential
#--------------------------------------------------------------
# 對比 AWS：IAM Role Trust Policy 中的 OIDC condition
#   AWS：  "StringEquals": {"oidc.eks.../id/xxx:sub": "system:serviceaccount:ns:sa"}
#   Azure：直接建一個 federated_identity_credential 資源，更明確
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential
#
# 需要設定：
#   name                = "${local.name_prefix}-federated"
#   resource_group_name = azurerm_resource_group.rg.name
#   parent_id           = azurerm_user_assigned_identity.workload.id
#   issuer              = var.aks_oidc_issuer_url   # 來自 A-03 output
#   subject             = local.federated_subject   # "system:serviceaccount:<ns>:<sa>"
#   audience            = ["api://AzureADTokenExchange"]   # 固定值
#
# ⚠️ 注意：audience 是 list，不是 string

resource "azurerm_federated_identity_credential" "workload" {
  # TODO
}

#--------------------------------------------------------------
# TODO 4: Key Vault
#--------------------------------------------------------------
# 對比 AWS：Secrets Manager（lab 33）
# 差異：Key Vault 需要明確設定 tenant_id 與存取政策
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault
#
# 需要設定：
#   name                       = local.key_vault_name   # 全域唯一，3-24 字元
#   location                   = azurerm_resource_group.rg.location
#   resource_group_name        = azurerm_resource_group.rg.name
#   tenant_id                  = data.azurerm_client_config.current.tenant_id
#   sku_name                   = "standard"
#   enable_rbac_authorization  = true   # 用 RBAC 而非舊式 Access Policy
#   tags                       = local.common_tags
#
# ⚠️ 注意：enable_rbac_authorization = true 後，存取權限改用 Role Assignment 管理

resource "azurerm_key_vault" "kv" {
  # TODO
}

#--------------------------------------------------------------
# TODO 5: Key Vault Secret（測試用）
#--------------------------------------------------------------
# 存一個測試 secret，讓 Pod 稍後讀取驗證 Workload Identity 是否生效
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret
#
# 需要設定：
#   name         = "demo-secret"
#   value        = var.key_vault_secret_value
#   key_vault_id = azurerm_key_vault.kv.id
#   tags         = local.common_tags
#
# ⚠️ 注意：建立 secret 需要 terraform 執行者本身有 Key Vault Secrets Officer 權限
#    → 用下方 TODO 6 的 Role Assignment 先授權給自己

resource "azurerm_key_vault_secret" "demo" {
  # TODO
  depends_on = [azurerm_role_assignment.terraform_kv_admin]
}

#--------------------------------------------------------------
# TODO 6: Role Assignment — Terraform 執行者寫入 Key Vault
#--------------------------------------------------------------
# Terraform apply 時需要寫入 secret，所以 terraform 執行者本身也要有權限
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
#
# 需要設定：
#   scope                = azurerm_key_vault.kv.id
#   role_definition_name = "Key Vault Secrets Officer"
#   principal_id         = data.azurerm_client_config.current.object_id   # 目前登入的帳號

resource "azurerm_role_assignment" "terraform_kv_admin" {
  # TODO
}

#--------------------------------------------------------------
# TODO 7: Role Assignment — Workload Identity 讀取 Key Vault
#--------------------------------------------------------------
# 讓 Pod（透過 User Assigned Identity）有讀取 secret 的權限
# 對比 AWS：IAM Role 附加 secretsmanager:GetSecretValue policy
#
# 需要設定：
#   scope                = azurerm_key_vault.kv.id
#   role_definition_name = "Key Vault Secrets User"   # 唯讀
#   principal_id         = azurerm_user_assigned_identity.workload.principal_id

resource "azurerm_role_assignment" "workload_kv_read" {
  # TODO
}
