output "sql_server_fqdn" {
  description = "SQL Server FQDN（連線字串用）e.g. xxx.database.windows.net"
  # TODO: azurerm_mssql_server.server.fully_qualified_domain_name
  value = azurerm_mssql_server.server.fully_qualified_domain_name
}

output "database_name" {
  description = "Database 名稱"
  # TODO: azurerm_mssql_database.db.name
  value = azurerm_mssql_database.db.name
}

output "connection_string" {
  description = "ADO.NET 連線字串（敏感）"
  # TODO: 組合成：
  # "Server=tcp:<fqdn>,1433;Database=<db>;User Id=<login>;Password=<password>;Encrypt=true;"
  value     = "Server=tcp:${azurerm_mssql_server.server.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.db.name};User Id=${var.admin_login};Password=${var.admin_password};Encrypt=true;"
  sensitive = true
}

output "sqlcmd_connect" {
  description = "sqlcmd 連線指令（需本機安裝 sqlcmd 或 mssql-tools）"
  # TODO: 組合成：
  # "sqlcmd -S <fqdn> -U <admin_login> -P '<admin_password>' -d <database_name>"
  value     = "sqlcmd -S ${azurerm_mssql_server.server.fully_qualified_domain_name} -U ${var.admin_login} -P '${var.admin_password}' -d ${azurerm_mssql_database.db.name}"
  sensitive = true
}
