# AWS ECS Fargate Lab

> 🟡 **費用等級：注意** — ~$0.032/hr，練完當天 destroy

EKS 學完之後的對比實驗：同樣跑 container，但完全不管 Node。
理解「什麼時候用 ECS Fargate，什麼時候用 EKS」。

## 學習目標

- 理解 ECS 核心概念：Cluster、Task Definition、Service、Task
- 體驗 Fargate「serverless container」：不用選 instance type，不用管 node
- 對比 EKS vs ECS 密鑰管理：Secrets Manager 原生注入 vs ESO
- 對比 HPA + Karpenter vs ECS Application Auto Scaling
- 建立 GitHub Actions OIDC + ECS rolling deploy 流程
- 理解 awsvpc 網路模式（每個 Task 有獨立 ENI）

## 架構圖

```
                              ┌─────────────────────────────────┐
                              │  VPC 10.1.0.0/16                │
Internet                      │                                 │
   │                          │  Public Subnet A    Public Subnet B
   ▼                          │  10.1.1.0/24       10.1.2.0/24  │
 ┌─────┐                      │       │                  │       │
 │ ALB │──────────────────────┤       ▼                  ▼       │
 └─────┘                      │  ┌─────────┐      ┌─────────┐   │
   :80                        │  │ Fargate │      │ Fargate │   │
   ▼                          │  │  Task   │      │  Task   │   │
 Target Group (ip mode)       │  │ :8080   │      │ :8080   │   │
                              │  └────┬────┘      └────┬────┘   │
                              │       │                  │       │
                              └───────┼──────────────────┼───────┘
                                      │ assign_public_ip  │
                                      ▼                   ▼
                                  ECR / Secrets Manager / CloudWatch
                                  （無 NAT Gateway，直接出外網）

EKS 對比：Node 在 private subnet，需 NAT GW ($0.045/hr = $32/月)
ECS Fargate：Task 在 public subnet + assign_public_ip = true，省 $32/月
```

## EKS vs ECS 快速對比

| 概念 | EKS | ECS Fargate |
|------|-----|-------------|
| 部署單元 | Deployment → Pod | Service → Task |
| 節點管理 | Karpenter 自動擴縮 | 無（Fargate 托管）|
| 水平擴縮 | HPA + Karpenter | Application Auto Scaling |
| 密鑰注入 | ESO → K8s Secret | secrets block（原生）|
| 日誌 | Fluent Bit DaemonSet | awslogs driver（零設定）|
| 費用 | ~$0.181/hr | ~$0.032/hr |

完整對比見 [docs/ecs-vs-eks.md](./docs/ecs-vs-eks.md)

## Terraform 資源總覽

| 檔案 | 資源 |
|------|------|
| `vpc.tf` | VPC、Public Subnets × 2、IGW、Route Table |
| `ecr.tf` | ECR Repository + Lifecycle Policy |
| `iam.tf` | Task Execution Role、Task Role、ECS Exec Policy |
| `ecs.tf` | ECS Cluster、Task Definition、ECS Service |
| `alb.tf` | ALB、Target Group（ip）、Listener、Security Groups × 2 |
| `autoscaling.tf` | Application Auto Scaling（CPU + Memory）|
| `secrets.tf` | Secrets Manager Secret |
| `cloudwatch.tf` | CloudWatch Log Group |
| `github_oidc.tf` | GitHub OIDC Provider、IAM Role |

## 操作步驟

### 1. 初始化

```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，至少確認 github_repo 正確

terraform init
terraform fmt
terraform validate
terraform plan
```

### 2. Apply（第一次：nginx 佔位，驗證 ALB 通）

`terraform.tfvars.example` 預設用 `public.ecr.aws/nginx/nginx:stable-alpine` + port 80 作佔位，
讓你先確認網路、ALB、ECS Service 都正常，再換上自己的 app。

```bash
terraform apply
```

驗證 ALB：
```bash
curl $(terraform output -raw alb_dns_name)
# 回傳 nginx 歡迎頁面即可
```

### 3. Build & Push Go App 到 ECR

```bash
ECR_URL=$(terraform output -raw ecr_repository_url)

# 登入 ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin "$ECR_URL"

# Build & Push
docker build -t "$ECR_URL:latest" ./app
docker push "$ECR_URL:latest"
```

### 4. 切換到 Go App

更新 `terraform.tfvars`：

```hcl
container_image   = "<ECR_URL>:latest"  # 填入上面的 ECR URL
container_port    = 8080
health_check_path = "/health"
```

```bash
terraform apply
```

等 task 重啟後（約 30 秒），驗證：
```bash
curl $(terraform output -raw alb_dns_name)/health
```

## 驗證

### 基本健康檢查

```bash
ALB=$(terraform output -raw alb_dns_name)

# 健康檢查（ALB health check 也用此路徑）
curl $ALB/health

# 完整回應（含 ECS task 資訊）
curl -s $ALB | jq .
```

預期輸出（Go app 實際回應）：
```json
{
    "status": "ok",
    "version": "1.0.0",
    "hostname": "ip-10-1-1-173.ec2.internal",
    "region": "us-east-1",
    "timestamp": "2026-06-24T12:18:48Z",
    "ecs": {
        "cluster": "arn:aws:ecs:us-east-1:123456789..:cluster/infra-lab-dev-cluster",
        "family": "infra-lab-dev-app",
        "revision": "3",
        "task_arn": "arn:aws:ecs:us-east-1:123456789..:task/infra-lab-dev-cluster/889eeb79b95e..."
    }
}
```

> `hostname` 是 Fargate task ENI 的 private DNS（`ip-<private-ip>.ec2.internal`）
> `ecs.cluster` 是完整 ARN（ECS Task Metadata v4 回傳格式），非 short name
> 多次 `curl` 打，`hostname` 不同代表兩個 task 都在 load balancing

### 查看 ECS Service 狀態

```bash
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)

aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}'
```

### 進入容器（ECS Exec，類似 kubectl exec）

```bash
# 取得 running task ID
TASK_ID=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
  --query 'taskArns[0]' --output text | cut -d/ -f3)

# exec 進入（需要 ECS Exec 已啟用）
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$TASK_ID" \
  --container app \
  --interactive \
  --command /bin/sh
```

### 查看容器日誌（CloudWatch）

```bash
LOG_GROUP=$(terraform output -raw cloudwatch_log_group)

# 即時 tail
aws logs tail "$LOG_GROUP" --follow
```

### 驗證 Secrets Manager 注入

```bash
# exec 進容器後
echo $API_KEY  # 應顯示 Secrets Manager 中的值（不是 ARN）
```

### 測試 Auto Scaling

```bash
# 用 Apache Bench 打壓力（需先安裝 ab）
ALB=$(terraform output -raw alb_dns_name)
ab -n 10000 -c 100 $ALB/

# 監看 task 數量變化
watch -n 5 "aws ecs describe-services \
  --cluster $CLUSTER --services $SERVICE \
  --query 'services[0].{Running:runningCount,Desired:desiredCount}'"
```

### GitHub Actions CI/CD 設定

1. 取得 Role ARN：`terraform output github_actions_role_arn`
2. 在 GitHub repo 加入 Secret：`AWS_ROLE_ARN = <上面的 ARN>`
3. 在 GitHub repo 加入 Variable：`ECR_REPOSITORY = <ecr_repository_url>`

GitHub Actions workflow 範例（`.github/workflows/deploy.yml`）：
```yaml
name: Deploy to ECS
on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1

      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push image
        env:
          IMAGE_URI: ${{ vars.ECR_REPOSITORY }}:${{ github.sha }}
        run: |
          docker build -t $IMAGE_URI ./app
          docker push $IMAGE_URI

      - name: Deploy to ECS
        env:
          IMAGE_URI: ${{ vars.ECR_REPOSITORY }}:${{ github.sha }}
        run: |
          # 取得現有 task definition 並更新 image
          TASK_DEF=$(aws ecs describe-task-definition \
            --task-definition infra-lab-dev-app \
            --query 'taskDefinition' --output json)

          NEW_TASK_DEF=$(echo "$TASK_DEF" | \
            jq --arg IMAGE "$IMAGE_URI" \
            '.containerDefinitions[0].image = $IMAGE | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

          NEW_ARN=$(aws ecs register-task-definition \
            --cli-input-json "$NEW_TASK_DEF" \
            --query 'taskDefinition.taskDefinitionArn' --output text)

          aws ecs update-service \
            --cluster infra-lab-dev-cluster \
            --service infra-lab-dev-app-service \
            --task-definition "$NEW_ARN"
```

## 清除

```bash
terraform destroy -auto-approve
```

如果卡住，見 [docs/cleanup.md](./docs/cleanup.md)

## 費用估算

| 資源 | 費用 | 說明 |
|------|------|------|
| ECS Fargate (2 tasks) | ~$0.024/hr | 0.25 vCPU + 0.5GB × 2 |
| ALB | ~$0.008/hr | + LCU（lab 流量忽略不計）|
| CloudWatch Logs | < $0.01 | 少量日誌 |
| Secrets Manager | ~$0.001 | $0.40/月 prorated |
| ECR | < $0.01 | 小 image |
| **總計** | **~$0.033/hr** | **~$0.80/天** |

EKS Lab 對比：~$0.181/hr（~$4.34/天）

> 用完立刻 `terraform destroy`，避免 ALB 長時間收費

## 切換到 Go App

> 如果你照操作步驟走，這段已在步驟 3-4 完成，可跳過。

nginx 驗完後快速換 Go app：

```bash
# 1. Build & Push
ECR=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR
docker build -t $ECR:latest ./app && docker push $ECR:latest

# 2. 更新 tfvars（3 個值）
#    container_image   = "<ECR_URL>:latest"
#    container_port    = 8080
#    health_check_path = "/health"

# 3. Apply — ECS 滾動更新，ALB 全程不中斷
terraform apply
```

驗證（等 task 重啟後）：
```bash
curl -s $(terraform output -raw alb_dns_name) | python3 -m json.tool
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Task 一直 PENDING | image pull 失敗（ECR 沒有 image 或 SG 擋出口）|
| Health check 失敗 | container port 不對，或 health check path 不存在（nginx 用 `/`，Go app 用 `/health`）|
| `execute-command` 失敗 | 需要 `enable_execute_command = true`（已設定）|
| Secrets 注入失敗 | Task execution role 缺少 `secretsmanager:GetSecretValue` |
| ECS Exec 403 | Task role 缺少 `ssmmessages:*` 權限 |
| Auto Scaling 不動 | 需等 3-5 分鐘讓 metrics 累積 |
| 改 `container_port` 後 apply 報 `Target group already exists` | TG 需要用 `name_prefix`（非 `name`）才能 `create_before_destroy`，已修正 |
| 改 `container_port` 後 ECS Service 報 `container port N not defined` | `ignore_changes` 不能包含 `task_definition`，否則 Service 切新 port 時 task def 不同步 |
