# ECS Fargate Lab — 清除指南

## 為什麼不能直接 `terraform destroy`

| 資源 | 問題 | 預處理 |
|------|------|--------|
| EventBridge Scheduler | 每 5 分鐘觸發，destroy 途中可能啟動新 task | 先 disable |
| ECR Repository | 有 images，destroy 預設不刪非空 repo | 先清空 images |
| CodeDeploy | 若有 InProgress deployment，destroy 會卡住 | 先確認 / stop |
| ECS Service | 有 running tasks | terraform 自動 drain，但需等待 |
| Secrets Manager | `recovery_window_in_days = 0`，可立即刪除 | 無需預處理 |

---

## 清除步驟

### Step 1：停用 EventBridge Scheduler

```bash
aws scheduler update-schedule \
  --name infra-lab-dev-job \
  --state DISABLED \
  --region us-east-1 \
  --flexible-time-window '{"Mode":"OFF"}' \
  --schedule-expression "rate(5 minutes)" \
  --target '{
    "Arn": "arn:aws:ecs:us-east-1:661515655645:cluster/infra-lab-dev-cluster",
    "RoleArn": "arn:aws:iam::661515655645:role/infra-lab-dev-scheduler-role",
    "EcsParameters": {
      "TaskDefinitionArn": "arn:aws:ecs:us-east-1:661515655645:task-definition/infra-lab-dev-job",
      "LaunchType": "FARGATE",
      "NetworkConfiguration": {
        "AwsvpcConfiguration": {
          "Subnets": ["subnet-0bd00388343c719d2","subnet-035df59fb4c4de89e"],
          "SecurityGroups": ["sg-0088b5ca737ef0e43"],
          "AssignPublicIp": "ENABLED"
        }
      }
    }
  }'
```

> 也可以直接在 `scheduled_task.tf` 加 `state = "DISABLED"` 後 `terraform apply`，效果相同。

### Step 2：清空 ECR images

```bash
REPO="infra-lab-dev-app"

# 列出所有 image IDs
IMAGE_IDS=$(aws ecr list-images \
  --repository-name "$REPO" \
  --region us-east-1 \
  --query 'imageIds[*]' \
  --output json)

echo "Images to delete: $(echo $IMAGE_IDS | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')"

# 批次刪除
aws ecr batch-delete-image \
  --repository-name "$REPO" \
  --region us-east-1 \
  --image-ids "$IMAGE_IDS"
```

### Step 3：確認無 InProgress CodeDeploy deployment

```bash
aws deploy list-deployments \
  --application-name infra-lab-dev-app \
  --deployment-group-name infra-lab-dev-dg \
  --region us-east-1 \
  --include-only-statuses InProgress \
  --query 'deployments' --output json
# 必須回傳 []，若有 deployment 請先 stop：
# aws deploy stop-deployment --deployment-id <ID> --auto-rollback-enabled
```

### Step 4：terraform destroy

```bash
cd terraform/envs/aws-ecs-fargate
terraform destroy -auto-approve
```

預計耗時：3-5 分鐘（ECS Service drain 最久）。

### Step 5：驗證清除完成

```bash
# ECS Cluster
aws ecs describe-clusters \
  --clusters infra-lab-dev-cluster \
  --region us-east-1 \
  --query 'clusters[0].status' --output text
# 預期：INACTIVE 或空結果

# ALB
aws elbv2 describe-load-balancers \
  --names infra-lab-dev-alb \
  --region us-east-1 2>&1 | grep -c LoadBalancerNotFound
# 預期：1

# VPC（用 tag 找）
aws ec2 describe-vpcs \
  --region us-east-1 \
  --filters Name=tag:Project,Values=infra-lab Name=tag:Environment,Values=dev \
  --query 'Vpcs | length(@)' --output text
# 預期：0

# ECR（應已刪除）
aws ecr describe-repositories \
  --repository-names infra-lab-dev-app \
  --region us-east-1 2>&1 | grep -c RepositoryNotFoundException
# 預期：1

# Secrets Manager（recovery_window=0，應立即刪除）
aws secretsmanager describe-secret \
  --secret-id "infra-lab-dev/ecs/app-config" \
  --region us-east-1 2>&1 | grep -c ResourceNotFoundException
# 預期：1
```

### Step 6：ecs-app repo 處理（選擇性）

`changken/ecs-app` 的 GitHub Actions workflow 在 push 時會嘗試：
- ECR push（已刪除 → 失敗）
- CodeDeploy deployment（已刪除 → 失敗）

若之後不再重建此 lab，建議停用 workflow：

```bash
# GitHub CLI
gh workflow disable deploy.yml --repo changken/ecs-app
```

或在 `ecs-app` repo 的 Actions 設定頁面手動停用。

---

## 費用確認

清除後到 **AWS Cost Explorer** 確認次日無額外費用。

主要費用項目與單價：

| 服務 | 計費方式 | 估計 |
|------|---------|------|
| ECS Fargate | vCPU-hr × $0.04048 + GB-hr × $0.004445 | 2 tasks × 0.25 vCPU ≈ $0.02/hr |
| ALB | $0.008/hr + LCU | $0.008/hr 起 |
| CloudWatch Logs | $0.50/GB ingested | 視日誌量 |
| Secrets Manager | $0.40/secret/month | 約 $0.013/day |
| Container Insights | $0.50/GB ingested | 視 metrics 量 |
| EventBridge Scheduler | $1.00/百萬次 | 極低（rate 5m = ~288次/day）|

---

## Troubleshooting

### ECR batch-delete-image 失敗

```bash
# 改用逐一刪除
aws ecr list-images --repository-name infra-lab-dev-app --region us-east-1 \
  --query 'imageIds[*].imageDigest' --output text | \
  tr '\t' '\n' | while read digest; do
    aws ecr batch-delete-image \
      --repository-name infra-lab-dev-app \
      --region us-east-1 \
      --image-ids imageDigest=$digest
  done
```

### terraform destroy 卡在 ECS Service

ECS Service 等 tasks drain 最多 30 分鐘。可加速：

```bash
aws ecs update-service \
  --cluster infra-lab-dev-cluster \
  --service infra-lab-dev-app-service \
  --desired-count 0 \
  --region us-east-1

aws ecs wait services-stable \
  --cluster infra-lab-dev-cluster \
  --services infra-lab-dev-app-service \
  --region us-east-1

terraform destroy -auto-approve
```

### Secrets Manager recovery window 擋住

`recovery_window_in_days = 0` 應可立即刪除，若仍報錯：

```bash
SECRET_ARN=$(terraform output -raw secret_arn)
aws secretsmanager delete-secret \
  --secret-id "$SECRET_ARN" \
  --force-delete-without-recovery \
  --region us-east-1
terraform destroy -auto-approve
```

### ALB 無法刪除（Target Group in use）

Target group 仍有 active connection，等 30 秒後再 destroy：

```bash
terraform destroy -auto-approve
```

### 部署相關問題

**快速連續部署導致 ECS_UPDATE_ERROR**

短時間內多次 push，前一個 CodeDeploy deployment 還沒完全結束，下一個就啟動：

```
"code": "ECS_UPDATE_ERROR",
"message": "TaskSet <ecs-svc/xxx> is behind prod listener..."
```

確認服務正常後，等 DRAINING task set 消失再 push：

```bash
aws deploy list-deployments \
  --application-name infra-lab-dev-app \
  --deployment-group-name infra-lab-dev-dg \
  --include-only-statuses InProgress \
  --query 'deployments' --output json
# 回傳 [] 才 push
```

**切換到 CODE_DEPLOY 後 INVALID_ECS_SERVICE**

ECS Service task set 指向已刪除的舊 TG：

```bash
terraform apply -replace=aws_ecs_service.app
```

詳見 [blue-green-demo.md Troubleshooting](./blue-green-demo.md#troubleshooting)。

**Apply 中途失敗（deposed TG）**

直接再跑一次，Terraform 會清理 deposed 物件：

```bash
terraform apply -auto-approve
```

根本原因：`aws_lb_target_group` 已改用 `name_prefix` + `create_before_destroy`，正常情況不會再發生。
