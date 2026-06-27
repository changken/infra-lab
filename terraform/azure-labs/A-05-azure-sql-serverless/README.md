# A-05：Azure SQL Serverless 🟡 < $1

> 建立 Azure SQL Serverless 資料庫，對比 RDS PostgreSQL（lab 04）。
> 閒置時自動暫停、喚醒即用，開發環境幾乎免費。

**費用估算**：GP_S_Gen5_1，60 分鐘 auto-pause，主動查詢時 ≈ $0.000145/vCore-sec；
長時間閒置（暫停中）≈ $0（只收儲存費 $0.115/GB/月）

---

## 學習目標

- 理解 Azure SQL 的兩層架構：SQL Server（邏輯容器）+ Database
- 學會 Serverless 的 `sku_name` 格式與 auto-pause 設定
- 實作防火牆規則（Azure 服務 + 用戶端 IP）
- 體驗 Azure SQL vs AWS RDS 的命名與連線差異

## AWS vs Azure 對比

| 元素 | AWS (Lab 04) | Azure (本 Lab) |
|------|-------------|---------------|
| 資源層數 | 1 個（`aws_db_instance`） | 2 個（SQL Server + Database） |
| Serverless | Aurora Serverless v2 only | 標準 Azure SQL 就有 Serverless tier |
| 閒置計費 | 最低仍收費（db.t3.micro $0.017/hr）| 暫停中只收儲存費 |
| 防火牆 | Security Group（VPC 層） | SQL Server Firewall Rules（IP 白名單）|
| 連線埠 | 5432（PostgreSQL） | 1433（T-SQL） |
| 連線字串 | `postgresql://user:pass@host/db` | `Server=tcp:xxx.database.windows.net,1433;...` |

## 架構

```
本機 / Azure 服務
    │ TCP 1433
    ▼
┌─────────────────────────────────────┐
│  SQL Server（邏輯容器）              │
│  xxx.database.windows.net           │
│  Firewall: Azure services + 我的 IP │
│  ┌───────────────────────────────┐  │
│  │  Database (GP_S_Gen5_1)       │  │
│  │  0.5-1 vCore Serverless       │  │
│  │  auto-pause: 60min            │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
        Resource Group
```

## 你要做的事

| TODO | 資源 | 說明 |
|------|------|------|
| TODO 1 | `azurerm_resource_group` | 資源容器 |
| TODO 2 | `azurerm_mssql_server` | 邏輯 SQL Server（全域唯一名稱）|
| TODO 3 | `azurerm_mssql_database` | Serverless DB，sku_name 設對是關鍵 |
| TODO 4 | `azurerm_mssql_firewall_rule` allow_azure | 0.0.0.0/0.0.0.0 = 允許 Azure 服務 |
| TODO 5 | `azurerm_mssql_firewall_rule` allow_client | 選填，count 控制 |
| outputs | connection_string、sqlcmd_connect | 組合連線字串 |

## 操作步驟

```bash
# 1. 複製並填寫變數（密碼必填）
cp terraform.tfvars.example terraform.tfvars
# 查詢本機 IP（若要直連）：
curl -s https://api.ipify.org

# 2. 部署（約 5 分鐘）
terraform init
terraform fmt && terraform validate
terraform plan
terraform apply
```

## 驗證

```bash
# 取得連線資訊
terraform output sql_server_fqdn
terraform output -raw sqlcmd_connect   # 複製後直接執行

# 方法 A：sqlcmd（需安裝）
# https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility
sqlcmd -S <fqdn> -U sqladmin -P '<password>' -d <database_name> -Q "SELECT @@VERSION"

# 方法 B：Azure Cloud Shell（免安裝）
# 在 portal.azure.com 開 Cloud Shell，直接跑 sqlcmd

# 方法 C：Azure Data Studio / SSMS（GUI）
# 用 terraform output -raw connection_string 取得連線字串

# 驗證 auto-pause（等 60 分鐘不查詢，DB 狀態變 Paused）
az sql db show \
  --resource-group $(terraform output -raw resource_group_name 2>/dev/null || echo "<rg-name>") \
  --server <sql-server-name> \
  --name <database-name> \
  --query status -o tsv
```

## 清除資源

```bash
terraform destroy -auto-approve
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SQL Server 名稱衝突 | 全域唯一，在 project 名稱後加數字或縮寫 |
| `sku_name` 格式錯誤 | 格式固定：`GP_S_Gen5_<vCore數>`，例如 `GP_S_Gen5_1` |
| `min_capacity` 不合法 | 只能是 0.5、1、2 等，不能任意數字 |
| 密碼被拒絕 | 必須含大寫、小寫、數字、特殊符號，且 ≥ 8 字元 |
| 連線 timeout | 防火牆規則沒加，或 `allowed_client_ip` IP 填錯 |
| auto-pause 無效 | `sku_name` 必須是 Serverless（`GP_S_*`），General Purpose（`GP_*`）沒有此功能 |
