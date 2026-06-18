# aws-oracle-rds

在 Default VPC 上建立 RDS Oracle SE2（License Included）。  
用於練習 Oracle on AWS，搭配前公司 11g → 19c 升版背景熟悉雲端託管版本。

---

## 架構

```
Default VPC
└── Default Subnets (多 AZ)
    └── DB Subnet Group
        └── RDS Oracle SE2 (19c, License Included)
            └── Security Group (port 1521, 限制來源 IP)
```

---

## 費用提醒

| Instance | 時薪 (約) | $43 能跑 |
|---|---|---|
| db.t3.medium | ~$0.17/hr | ~10 天 |
| db.m5.large  | ~$0.475/hr | ~3.5 天 |
| db.r5.large  | ~$0.60/hr | ~2.5 天 |

> ⚠️ **用完立刻 `terraform destroy`！** Oracle SE2 LI 含授權費，比 MySQL/Postgres 貴 3-5x。

---

## 快速開始

```bash
cd terraform/modules/aws-oracle-rds

cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars：填入 db_password

terraform init
terraform plan
terraform apply
```

連線（apply 完會輸出）：

```bash
# SQL*Plus
sqlplus admin@//your-rds-endpoint:1521/ORCL

# JDBC Thin (DBeaver / IntelliJ)
jdbc:oracle:thin:@//your-rds-endpoint:1521/ORCL
```

---

## 變數

| 變數 | 預設 | 說明 |
|---|---|---|
| `region` | `us-east-1` | AWS Region |
| `project` | `oracle-rds-lab` | 資源命名前綴 |
| `instance_class` | `db.m5.large` | RDS instance 類型 |
| `allocated_storage` | `20` | 儲存空間 (GB) |
| `engine_version` | `19` | Oracle 19c |
| `license_model` | `license-included` | SE2 LI，不需自帶授權 |
| `db_name` | `ORCL` | Oracle SID（大寫，≤ 8 字）|
| `db_username` | `admin` | Master username |
| `db_password` | — | **必填，設在 tfvars** |
| `allowed_cidr` | `118.150.143.171/32` | 允許連入的 IP |
| `publicly_accessible` | `true` | Lab 開放外部連線 |
| `multi_az` | `false` | Lab 關閉，省費用 |
| `skip_final_snapshot` | `true` | destroy 時不建 snapshot |
| `deletion_protection` | `false` | 允許 destroy |

---

## Outputs

| Output | 說明 |
|---|---|
| `endpoint` | `host:port` |
| `address` | hostname only |
| `port` | `1521` |
| `db_name` | Oracle SID |
| `jdbc_url` | JDBC Thin URL |
| `sqlplus_command` | SQL*Plus 連線指令 |
| `security_group_id` | SG ID |

---

## 清理

```bash
terraform destroy
```
