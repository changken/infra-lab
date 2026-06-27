locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  name_prefix = "${var.project}-${var.environment}"

  # SQL Server 名稱：全域唯一，只能小寫英數與連字號，3-63 字元
  sql_server_name = "${local.name_prefix}-sqlsrv"

  # Database 名稱：同一 Server 內唯一即可
  database_name = "${local.name_prefix}-db"
}
