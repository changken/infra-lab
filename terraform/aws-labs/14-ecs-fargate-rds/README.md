# Lab 14: ECS Fargate + RDS

將容器應用連接到 RDS PostgreSQL，體驗三層架構（ALB → ECS → RDS）。
**費用等級 🔴 危險** — RDS + ALB 同時運行，**同一天完成後立刻 destroy**。

**前置條件**：需要先 build + push 本 lab 的 Flask image 到 ECR（使用 Lab 10 的 ECR repository）。

## 學習目標

- **三層 Security Group 鏈**：Internet → ALB → ECS → RDS，每層只允許上一層的 SG
- `aws_db_subnet_group`：RDS 必須指定跨 AZ 的 Subnet Group
- `aws_db_instance`：`publicly_accessible = false`，透過 SG 控制存取
- Task Definition 的 `environment` block：把 RDS endpoint 注入容器環境變數
- 明文 vs 加密（`environment` vs `secrets` + Secrets Manager）的差異

## 架構

```
Internet（port 80）
    ↓
ALB Security Group（0.0.0.0/0:80）
    ↓
Application Load Balancer
    ↓ forward
Target Group（health check: GET /health, port 5000）
    ↓
ECS Security Group（ingress: ALB SG / egress: 全開 + RDS SG:5432）
    ↓
Fargate Task（Flask app, port 5000）
    ↓ PostgreSQL:5432
RDS Security Group（ingress: ECS SG:5432 only）
    ↓
RDS PostgreSQL（publicly_accessible = false）
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_security_group.ecs` | ingress from ALB SG + **egress to RDS SG on 5432** |
| 2 | `aws_security_group.rds` | ingress from ECS SG on 5432 **only** |
| 3 | `aws_db_subnet_group.main` | `subnet_ids = data.aws_subnets.default.ids` |
| 4 | `aws_db_instance.postgres` | `publicly_accessible = false`, `skip_final_snapshot = true` |
| 5 | `aws_ecs_task_definition.app` | `environment` block：把 RDS address 注入容器 |

已預先填好：data sources、CloudWatch、IAM、ECS cluster、ALB SG、ALB + TG + Listener、ECS service

## 指令

### Step 0：Build + Push Flask Image

本 Lab 需要一個能連 PostgreSQL 的 Flask app，使用 `app/` 目錄中的程式碼：

```bash
# 取得 ECR URL（使用 Lab 10 的 repository）
cd ../10-ecr-repository
REPO_URL=$(terraform output -raw repository_url)
ACCOUNT_ID=$(terraform output -raw registry_id)
REGION="us-east-1"

# ECR 認證
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin \
    $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build + Tag + Push（注意：指定 linux/amd64 以相容 Fargate）
cd ../14-ecs-fargate-rds
docker build --platform linux/amd64 -t flask-app ./app
docker tag flask-app:latest $REPO_URL:latest
docker push $REPO_URL:latest
```

**Windows PowerShell 版本：**
```powershell
cd ../10-ecr-repository
$REPO_URL = terraform output -raw repository_url
$ACCOUNT_ID = terraform output -raw registry_id
$REGION = "us-east-1"

aws ecr get-login-password --region $REGION `
  | docker login --username AWS --password-stdin `
    "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

cd ../14-ecs-fargate-rds
docker build --platform linux/amd64 -t flask-app ./app
docker tag flask-app:latest "${REPO_URL}:latest"
docker push "${REPO_URL}:latest"
```

### Step 1：填寫 TODOs 並建立資源

```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars：
#   ecr_image_url = <Lab 10 的 repository_url>:latest
#   db_password   = <自訂密碼>

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：14 to add
terraform apply   # RDS 啟動需 5-10 分鐘，請耐心等候
```

### Step 2：驗證

```bash
# 取得 ALB URL
terraform output alb_url

# 健康檢查
curl http://<ALB_DNS>/health
# 預期：{"status": "ok"}

# 資料庫連線測試
curl http://<ALB_DNS>/
# 預期：{"db_time": "...", "db_version": "PostgreSQL 16...", "status": "ok"}
```

### 結束

```bash
# ⚠️ RDS + ALB 都在計費，務必立刻 destroy！
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| Fargate（0.25 vCPU / 0.5 GB）| ~$0.01/hr |
| ALB | $0.008/hr + LCU |
| RDS db.t3.micro（PostgreSQL）| $0.017/hr |
| EBS（20 GB）| $0.0023/hr |
| **2 小時 Lab 合計** | **~$0.08** |

**RDS 是這個 Lab 最貴的資源，絕對不能讓它過夜（$0.017 × 24 = $0.41/天）。**

## environment vs secrets（生產環境注意）

本 Lab 使用 `environment` block 傳遞 DB 密碼（明文）：

```json
{ "name": "DB_PASSWORD", "value": "YourPassword" }
```

**問題**：密碼會出現在 ECS Console、CloudWatch Logs，以及 Terraform state 中。

生產環境應改用 `secrets` block + AWS Secrets Manager：

```json
{ "name": "DB_PASSWORD", "valueFrom": "arn:aws:secretsmanager:..." }
```

這樣密碼在傳輸和儲存時都是加密的，不會出現在 Log 中。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `curl /` 回應 `{"status": "error", "error": "..."}` | ECS SG 的 egress 沒有開放 TCP 5432 到 RDS SG |
| RDS apply 卡住（等 5-10 分鐘）| 正常，RDS 啟動需要時間 |
| Task 一直重啟（STOPPED）| 通常是 DB 連線失敗，先確認 SG 設定，查 CloudWatch Logs |
| `exec format error` | image build 時忘了加 `--platform linux/amd64`（Mac M1 用戶常見）|
| ALB 回應 502 | Flask app 還在啟動（等 1-2 分鐘），或 container_port 設錯（應為 5000）|
| `password authentication failed` | `db_password` 包含特殊字元（`@`, `#`, `/`），請改用字母+數字 |
| Target health `unhealthy` | health check path 應為 `/health`（Flask app 有此路由）|
| destroy 失敗 | 通常是 RDS 的 final snapshot 問題，確認 `skip_final_snapshot = true` |
