# Lab 10: ECR Repository

建立 ECR（Elastic Container Registry）並推送 Docker image。
這個 image 會在 **Lab 11（ECS Fargate）** 中被部署。
**費用極低** — ECR 按儲存空間計費，5 個小 image 約 $0.01。

## 學習目標

- `aws_ecr_repository`：私有 Container Registry 的設定選項
- `image_tag_mutability`：MUTABLE vs IMMUTABLE 的差異
- `scan_on_push`：免費的 image 漏洞掃描
- `aws_ecr_lifecycle_policy`：自動清理舊 image，避免儲存費用累積
- ECR 認證流程：`aws ecr get-login-password | docker login`

## 架構

```
本地電腦
└── docker build（app/Dockerfile）
    └── docker push
        → ECR Repository（my-app）
            → image: my-app:latest
                → Lab 11 的 ECS Fargate 會從這裡拉 image
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_ecr_repository` | `image_tag_mutability`、`scan_on_push` |
| 2 | `aws_ecr_lifecycle_policy` | `jsonencode` 寫 lifecycle rule，保留最近 N 張 image |

再補完 `outputs.tf` 的 1 個 TODO（push_commands）。

## 指令

### Step 1：建立 ECR Repository

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：2 to add
terraform apply
```

### Step 2：Build + Push Docker Image

```bash
# 取得 ECR URL
REPO_URL=$(terraform output -raw repository_url)
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
ACCOUNT_ID=$(terraform output -raw registry_id)

# 認證 ECR（每 12 小時需要重新認證）
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin \
    $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build image
docker build -t my-app ./app

# Tag（格式：repository_url:tag）
docker tag my-app:latest $REPO_URL:latest

# Push
docker push $REPO_URL:latest
```

**Windows PowerShell 版本：**
```powershell
$REPO_URL = terraform output -raw repository_url
$ACCOUNT_ID = terraform output -raw registry_id
$REGION = "us-east-1"

aws ecr get-login-password --region $REGION `
  | docker login --username AWS --password-stdin `
    "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

docker build -t my-app ./app
docker tag my-app:latest "${REPO_URL}:latest"
docker push "${REPO_URL}:latest"
```

### Step 3：驗證

```bash
# 確認 image 已在 ECR 中
aws ecr list-images --repository-name my-app

# 或到 AWS Console → ECR → Repositories → my-app → Images
```

### 結束

```bash
# ⚠️ 先刪除所有 images（ECR 有 image 時 repository 無法直接 destroy）
aws ecr batch-delete-image \
  --repository-name my-app \
  --image-ids imageTag=latest

terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| ECR 儲存 | $0.10/GB/月 |
| 5 個 nginx:alpine image（~10MB 各）| ~$0.01/月 |
| ECR 傳輸（同 region）| 免費 |

**Lab 完成後請 destroy，但 image 不大可以留著給 Lab 11 用。**

## MUTABLE vs IMMUTABLE

| | MUTABLE | IMMUTABLE |
|--|---------|-----------|
| 允許覆蓋同一 tag | ✅ | ❌ |
| 適合 | 開發環境 | 生產環境 |
| 範例 | `latest` 可以一直 push | `v1.0.0` 不能再改 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `docker push` 顯示 `no basic auth credentials` | 認證過期，重新執行 `get-login-password` |
| `docker push` 顯示 403 | IAM 使用者缺少 `ecr:GetAuthorizationToken` 或 `ecr:BatchCheckLayerAvailability` 權限 |
| `terraform destroy` 失敗 | ECR repository 裡還有 image，先刪掉再 destroy |
| lifecycle policy 格式報錯 | policy 是 JSON string，要用 `jsonencode()` 而非直接寫 HCL |
