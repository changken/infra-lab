# AWS Aurora PostgreSQL Module 🚀
### 帶有 Serverless v2 支援的高彈性、高可用資料庫模組 | 🔴 成本等級：危險 (請當天刪除)

本模組封裝了 **AWS Aurora PostgreSQL** 的核心資源。它不僅支援傳統 Provisioned 的實例類型，更原生支援 **Aurora Serverless v2**。在開發階段，它能自動縮容至最小 `0.5 ACU` (每小時僅約 $0.06 USD)，兼顧高效能與成本控制。

---

## 🎯 學習目標
- 了解 Aurora 叢集 (Cluster) 與實例 (Instance) 分離的運作架構。
- 掌握 **Serverless v2** 的資源配置（最小 ACU 與最大 ACU）與伸縮機制。
- 學習如何建立自訂的 Parameter Group 以管理資料庫引擎配置。
- 建立安全防禦（Security Group、Storage Encryption），只允許指定網路來源或主機連線。

---

## 📐 系統架構圖
```text
[ Client (ECS/EC2/Bastion) ] ── (Port 5432) ──► [ Security Group ]
                                                     │
┌────────────────────────────────────────────────────┼────────────────┐
│ AWS VPC (var.vpc_id)                               ▼                │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ DB Subnet Group (var.subnet_ids)                                │ │
│ │  ┌─────────────────────────────┬──────────────────────────────┐  │ │
│ │  │ Subnet AZ-A                 │ Subnet AZ-B                  │  │ │
│ │  │                             │                              │  │ │
│ │  │ ┌─────────────────────────┐ │ ┌──────────────────────────┐ │  │ │
│ │  │ │ Cluster Instance 1      │ │ │ Cluster Instance 2       │ │  │ │
│ │  │ │ (Writer / Primary)      │ │ │ (Reader / Replica)       │ │  │ │
│ │  │ └────────────┬────────────┘ │ └─────────────┬────────────┘ │  │ │
│ │  └──────────────┼──────────────┴───────────────┼──────────────┘  │ │
│ └─────────────────┼──────────────────────────────┼────────────────┘ │
│                   └──────────────┬───────────────┘                  │
│                                  ▼                                  │
│                      [ Aurora Storage Volume ]                      │
│                        (6-way Replication)                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ 模組使用說明 (Usage)

在您獨立的 Lab（例如 `labs/xx-aurora-lab/`）中的 `main.tf` 呼叫此模組：

```hcl
module "aurora_postgres" {
  source = "../../modules/aws-aurora-postgresql"

  project     = "my-aurora-project"
  environment = "dev"
  
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-11111111", "subnet-22222222"]

  # 規格與容量
  instance_class          = "db.serverless"
  serverless_min_capacity = 0.5
  serverless_max_capacity = 2.0
  cluster_size            = 1  # 僅建立 1 台 Writer 節點省錢

  # 認證與防護
  db_name     = "mydb"
  db_username = "postgres"
  db_password = var.db_password # 密碼定義於變數，不 commit

  # 限制連線來源
  allowed_cidr_blocks = ["10.0.0.0/16"]
}
```

---

## 💻 指令操作流程

請依循以下標準 Terraform 流程操作：

```bash
# 1. 複製 tfvars 範本，並修改成您的實際 VPC / Subnet ID / 密碼
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化專案 (下載 Provider 與 Module 核心元件)
terraform init

# 3. 程式碼排版美化 (請維持良好工程標準)
terraform fmt -recursive

# 4. 進行語法與架構驗證
terraform validate

# 5. 檢視執行計畫 (仔細檢查有哪些資源將被建立)
terraform plan

# 6. 部署資源
terraform apply -auto-approve
```

---

## 🔍 動態驗證方式 (Verification)

部署成功後，Terraform 會輸出 `cluster_endpoint` 與 `port`。您可以透過部署於同一 VPC 內（或連線允許範圍內）的 EC2 跳板機來驗證連線。

### 1. 連線至資料庫
在 Linux 終端機安裝 PostgreSQL 客戶端並嘗試連線：
```bash
# 安裝 pgsql 客戶端 (適用於 Amazon Linux 2023)
sudo dnf install postgresql15 -y

# 執行連線指令 (請用您的實際 Endpoint 與資料庫名稱替換)
psql -h <cluster_endpoint_from_outputs> -U postgres -d mydb
```

### 2. 測試資料庫基本操作
成功連線後，可執行以下 SQL 進行測試：
```sql
-- 1. 查看資料庫版本與時區設定 (TimeZone 應為我們在 Parameter Group 設定的 Asia/Taipei)
SELECT version();
SHOW timezone;

-- 2. 建立測試資料表並插入一筆資料
CREATE TABLE test_table (id SERIAL PRIMARY KEY, name VARCHAR(50));
INSERT INTO test_table (name) VALUES ('Infra-Lab Aurora PGSQL Test');
SELECT * FROM test_table;

-- 3. 離開終端機
\q
```

---

## 🧹 結束實驗 (Clean up)

由於 Aurora 為計費資源，完成練習後請**務必立刻刪除**，以免產生不必要的帳單！

```bash
terraform destroy -auto-approve
```

---

## 💰 成本估算 (Cost Estimation)

本模組在設計上極度注重成本控制。
- **Aurora Serverless v2 費用 ($0.12 / ACU-小時)**：
  - 當設定 `serverless_min_capacity = 0.5` 時，資料庫無流量下會維持在 `0.5 ACU`。
  - **單台節點費用**：`0.5 ACU * $0.12 = $0.06 USD / 小時`（非常適合學生與自學練習）。
- **儲存與備份費用**：
  - 儲存費按實際使用量計費，Lab 期間基本上為微量；
  - 自動備份保留期已設為最小 `1` 天，且設定 `skip_final_snapshot = true` 以確保 `destroy` 時立刻關閉不留任何付費殘存。

> ⚠️ **高額費用警告**：
> 雖然本模組提供了 Serverless 的極省模式，但**絕對不要將其實例維持開啟狀態超過 24 小時**。請在每次學習結束後，確實執行 `terraform destroy`！

---

## ❓ 卡關與排除提示 (Troubleshooting)

| 症狀 (Symptom) | 常見原因 (Cause) | 解決對策 (Remedy) |
| :--- | :--- | :--- |
| **`DB Subnet Group` 建立時報錯：`must contain subnets from at least two Availability Zones`** | Aurora 儲存系統要求資料庫 Subnet 組至少必須包含 2 個不同 AZ 的 Subnet。 | 在 `subnet_ids` 中，提供位於兩個不同 AWS 可用區（如 `us-east-1a` 與 `us-east-1b`）的 Subnet ID。 |
| **`terraform apply` 卡在 Instance 建立階段 (超過 5-10 分鐘)** | 這是正常現象，AWS 建立與佈署一個新的 Aurora 資料庫叢集通常需要 6-12 分鐘。 | 請耐心等候，切勿強制中斷程式，以免產生孤立資源或造成 state 異常。 |
| **執行連線 `psql` 時，連線逾時 (Timeout)** | 1. Security Group 沒開。<br>2. 您的連線來源與設定的 `allowed_cidr_blocks` 不符。<br>3. Aurora 沒有公開存取權限且您沒從 VPC 內連線。 | 1. 檢查 Security Group 是否綁定對應的來源。<br>2. 推薦在同個 VPC 的 Public Subnet 建立一台 EC2 (Bastion) 來進行內網連線，而非從網際網路直接連入。 |
| **`terraform destroy` 報錯或卡住，表示無法刪除** | 開啟了 `deletion_protection = true`。 | 先在 `terraform.tfvars` 中修改 `deletion_protection = false`，執行 `terraform apply` 更新配置，再執行 `terraform destroy`。 |
