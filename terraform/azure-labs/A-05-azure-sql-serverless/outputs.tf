output "sql_server_fqdn" {
  description = "SQL Server FQDN（連線字串用）e.g. xxx.database.windows.net"
  # TODO: azurerm_mssql_server.server.fully_qualified_domain_name
  value = null
}

output "database_name" {
  description = "Database 名稱"
  # TODO: azurerm_mssql_database.db.name
  value = null
}

output "connection_string" {
  description = "ADO.NET 連線字串（敏感）"
  # TODO: 組合成：
  # "Server=tcp:<fqdn>,1433;Database=<db>;User Id=<login>;Password=<password>;Encrypt=true;"
  value     = null
  sensitive = true
}

output "sqlcmd_connect" {
  description = "sqlcmd 連線指令（需本機安裝 sqlcmd 或 mssql-tools）"
  # TODO: 組合成：
  # "sqlcmd -S <fqdn> -U <admin_login> -P '<admin_password>' -d <database_name>"
  value     = null
  sensitive = true
}
