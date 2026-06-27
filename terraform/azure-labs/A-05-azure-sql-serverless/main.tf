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
# TODO 2: SQL Server（邏輯伺服器）
#--------------------------------------------------------------
# 對比 AWS：aws_db_instance 是一體的，Azure 拆成兩層：
#   SQL Server（邏輯容器）→ Database（實際資料庫）
# 一個 SQL Server 可以跑多個 Database，共用防火牆設定
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_server
#
# 需要設定：
#   name                         = local.sql_server_name   # 全域唯一
#   resource_group_name          = azurerm_resource_group.rg.name
#   location                     = azurerm_resource_group.rg.location
#   version                      = "12.0"   # SQL Server 版本，12.0 = 2014+（固定用這個）
#   administrator_login          = var.admin_login
#   administrator_login_password = var.admin_password
#   tags                         = local.common_tags
#
# ⚠️ 注意：SQL Server 名稱全域唯一，apply 失敗常是名稱衝突

resource "azurerm_mssql_server" "server" {
  # TODO
}

#--------------------------------------------------------------
# TODO 3: SQL Database（Serverless 層級）
#--------------------------------------------------------------
# 對比 AWS：AWS 沒有對應的標準 RDS Serverless（只有 Aurora Serverless v2）
# Azure SQL Serverless：查詢時才計費，閒置自動暫停，開發測試超省
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_database
#
# 需要設定：
#   name      = local.database_name
#   server_id = azurerm_mssql_server.server.id
#   tags      = local.common_tags
#
#   sku_name  = "GP_S_Gen5_1"   # GP_S = General Purpose Serverless, Gen5, 1 vCore
#                                # 對比 AWS：db.t3.micro 等固定規格
#
#   min_capacity              = var.min_capacity            # 最小 vCore（0.5）
#   max_size_gb               = 32                          # 最大儲存空間
#   auto_pause_delay_in_minutes = var.auto_pause_delay_minutes  # 60 = 閒置 1hr 自動暫停
#
# ⚠️ 注意：sku_name 格式為 "GP_S_Gen5_<vCore數>"
#   GP_S_Gen5_1 = 最便宜，0.5-1 vCore
#   GP_S_Gen5_2 = 最多 2 vCore

resource "azurerm_mssql_database" "db" {
  # TODO
}

#--------------------------------------------------------------
# TODO 4: 防火牆規則 — 允許 Azure 內部服務連入
#--------------------------------------------------------------
# 對比 AWS：RDS Security Group，但 Azure SQL 有獨立的 Firewall Rules
# start_ip = end_ip = "0.0.0.0" 是 Azure 的特殊設定，代表「允許 Azure 服務」
#
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_firewall_rule
#
# 需要設定：
#   name             = "allow-azure-services"
#   server_id        = azurerm_mssql_server.server.id
#   start_ip_address = "0.0.0.0"
#   end_ip_address   = "0.0.0.0"

resource "azurerm_mssql_firewall_rule" "allow_azure" {
  # TODO
}

#--------------------------------------------------------------
# TODO 5: 防火牆規則 — 允許用戶端 IP（選填）
#--------------------------------------------------------------
# 讓本機可以用 SQL Server Management Studio / sqlcmd 直接連入
# 若 var.allowed_client_ip 為空則不建立
#
# 需要設定：
#   count            = var.allowed_client_ip != "" ? 1 : 0
#   name             = "allow-client-ip"
#   server_id        = azurerm_mssql_server.server.id
#   start_ip_address = var.allowed_client_ip
#   end_ip_address   = var.allowed_client_ip
#
# 💡 查詢本機 IP：curl -s https://api.ipify.org

resource "azurerm_mssql_firewall_rule" "allow_client" {
  # TODO（選填）
}
