# Lab 04: RDS PostgreSQL

建立受管的 PostgreSQL 資料庫，理解 RDS 和自建 DB 的差別。
**⚠️ 最貴的一個 lab — 跑完立刻 destroy！**

## 學習目標

- `aws_db_instance`：RDS 核心資源
- DB Subnet Group：RDS 需要指定放在哪些 subnet
- Security Group：控制資料庫 port 的訪問
- `skip_final_snapshot`：為什麼練習環境必設
- `sensitive = true`：Terraform 如何保護密碼輸出

## 架構

```
Default VPC
└── Default Subnets (us-east-1a / 1b / 1c)
    └── DB Subnet Group
        └── RDS PostgreSQL db.t3.micro
            ← Security Group: 允許 port 5432
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_security_group` | ingress port 5432，egress all |
| 2 | `aws_db_subnet_group` | 把 default subnets 包起來 |
| 3 | `aws_db_instance` | 主體：engine/版本/規格/網路/密碼 |

再補完 `outputs.tf` 的 1 個 TODO（psql_command）。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，改掉 db_password

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：3 to add
terraform apply   # ⚠️ RDS 啟動約需 5-10 分鐘
```

**預期 plan：3 個 to add**（Security Group + Subnet Group + RDS Instance）

### 驗證

```bash
terraform output
```

用 psql_command 的輸出連線（需要本地裝 psql）：

```bash
psql -h <address> -p 5432 -U labadmin -d labdb
# 輸入 terraform.tfvars 裡的 db_password
```

### 結束（立刻做！）

```bash
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| db.t3.micro | ~$0.017/小時 |
| Storage 20GB | ~$0.002/小時 |
| 合計 | ~$0.02/小時 |

**跑 1 小時 ≈ $0.02，但忘記 destroy 放整天 = $0.48。**

## RDS vs 自建 DB 對比

| 面向 | 自建（EC2 + PostgreSQL） | RDS |
|------|--------------------------|-----|
| 備份 | 自己寫 script | 自動（可設 retention） |
| 版本升級 | 自己處理 | AWS 管理 |
| Failover | 自己設定 | Multi-AZ 自動 |
| 費用 | EC2 費用 | RDS 約貴 2-3x |
| 彈性 | 完全控制 | 受限於 AWS 選項 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `InvalidParameterValue: At least two subnets in two different AZs` | subnet group 需要至少 2 個不同 AZ 的 subnet |
| `apply` 卡住很久 | 正常！RDS 啟動需 5-10 分鐘 |
| `Error: db_password required` | 忘記建 terraform.tfvars |
| psql 連不到 | 確認 Security Group ingress 設好，`publicly_accessible = true` |
