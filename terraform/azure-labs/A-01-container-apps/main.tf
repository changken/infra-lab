#--------------------------------------------------------------
# TODO 1: Resource Group
#--------------------------------------------------------------
# Azure 所有資源都必須屬於一個 Resource Group（AWS 沒有這個概念）
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
# TODO 2: Log Analytics Workspace
#--------------------------------------------------------------
# Container Apps Environment 必須綁定一個 Log Analytics Workspace 才能收 log
# 對比 AWS：類似 CloudWatch Log Group，但這裡要先建 workspace
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace
#
# 需要設定：
#   name                = "${local.name_prefix}-law"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   sku                 = "PerGB2018"   # 最常用的方案
#   retention_in_days   = 30
#   tags                = local.common_tags

resource "azurerm_log_analytics_workspace" "law" {
  # TODO
  name                = "${local.name_prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

#--------------------------------------------------------------
# TODO 3: Container Apps Environment
#--------------------------------------------------------------
# 對比 AWS：類似 ECS Cluster，是 Container App 的執行環境
# 一個 Environment 可以跑多個 Container App，共用 log 設定與網路
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment
#
# 需要設定：
#   name                       = "${local.name_prefix}-env"
#   location                   = azurerm_resource_group.rg.location
#   resource_group_name        = azurerm_resource_group.rg.name
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
#   tags                       = local.common_tags

resource "azurerm_container_app_environment" "env" {
  # TODO
  name                       = "${local.name_prefix}-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  tags                       = local.common_tags
}

#--------------------------------------------------------------
# TODO 4: Container App
#--------------------------------------------------------------
# 對比 AWS：類似 ECS Service + Task Definition 合一，但更簡潔
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app
#
# 需要設定：
#   name                         = "${local.name_prefix}-app"
#   container_app_environment_id = azurerm_container_app_environment.env.id
#   resource_group_name          = azurerm_resource_group.rg.name
#   revision_mode                = "Single"   # 或 "Multiple"（藍綠部署用）
#   tags                         = local.common_tags
#
# template block：
#   container block：
#     name   = "app"
#     image  = var.container_image
#     cpu    = 0.25      # 最小單位
#     memory = "0.5Gi"   # 對應 cpu 0.25 的最小 memory
#
#   min_replicas = var.min_replicas   ← 設 0 才能縮到零（完全免費）
#   max_replicas = var.max_replicas
#
# ingress block（對外開放 HTTP）：
#   external_enabled = true
#   target_port      = var.container_port
#   traffic_weight block：
#     percentage      = 100
#     latest_revision = true
#
# ⚠️ 注意：cpu 和 memory 有固定組合，不能任意設定
#   0.25 cpu → "0.5Gi" memory
#   0.5  cpu → "1Gi"   memory
#   1.0  cpu → "2Gi"   memory

resource "azurerm_container_app" "app" {
  # TODO
  name                         = "${local.name_prefix}-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  template {
    container {
      name   = "app"
      image  = var.container_image
      cpu    = 0.25
      memory = "0.5Gi"
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
  }

  ingress {
    external_enabled = true
    target_port      = var.container_port

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
