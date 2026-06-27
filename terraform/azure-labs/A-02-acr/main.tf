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
# TODO 2: Azure Container Registry (ACR)
#--------------------------------------------------------------
# 對比 AWS：ECR（aws_ecr_repository）
# 差異：ACR 是帳號級服務，一個 ACR 可存多個 repo；ECR 每個 repo 獨立
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry
#
# 需要設定：
#   name                = local.acr_name        # 全域唯一，只能英數
#   resource_group_name = azurerm_resource_group.rg.name
#   location            = azurerm_resource_group.rg.location
#   sku                 = var.acr_sku           # Basic / Standard / Premium
#   admin_enabled       = var.admin_enabled     # 練習用，生產換 Managed Identity
#   tags                = local.common_tags
#
# ⚠️ 注意：ACR 名稱全域唯一，不能有連字號，local.acr_name 已處理

resource "azurerm_container_registry" "acr" {
  # TODO
  name                = local.acr_name # 全域唯一，只能英數
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.acr_sku       # Basic / Standard / Premium
  admin_enabled       = var.admin_enabled # 練習用，生產換 Managed Identity
  tags                = local.common_tags
}

#--------------------------------------------------------------
# TODO 3: Role Assignment — ACA 拉取 ACR image
#--------------------------------------------------------------
# 對比 AWS：ECR 用 Resource Policy 讓 ECS Task Role 拉 image
# Azure：用 RBAC Role Assignment，把 AcrPull 角色指派給 Container App 的 Managed Identity
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
#
# 需要設定：
#   scope                = azurerm_container_registry.acr.id
#   role_definition_name = "AcrPull"
#   principal_id         = var.aca_principal_id   # 留空也 OK，之後 A-03 串接用
#
# ⚠️ 注意：此步驟是選填，先跳過也可以跑起來。
#    若 admin_enabled = true，Container App 可直接用 username/password 拉 image（不需要 RBAC）
#    生產環境應改用 Managed Identity + AcrPull，不用 admin 帳密

# resource "azurerm_role_assignment" "acr_pull" {
#   scope                = azurerm_container_registry.acr.id
#   role_definition_name = "AcrPull"
#   principal_id         = var.aca_principal_id
# }
