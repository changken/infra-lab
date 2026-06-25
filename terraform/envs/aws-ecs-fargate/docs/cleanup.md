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

`aws scheduler update-schedule` 需要帶入現有的 target 設定，
最簡單的方式是先讀出再更新（PowerShell）：

```powershell
# PowerShell（Windows）
$schedule = aws scheduler get-schedule --name infra-lab-dev-job --region us-east-1 | ConvertFrom-Json

aws scheduler update-schedule `
  --name infra-lab-dev-job `
  --region us-east-1 `
  --state DISABLED `
  --flexible-time-window '{"Mode":"OFF"}' `
  --schedule-expression "rate(5 minutes)" `
  --target ($schedule.Target | ConvertTo-Json -Compress -Depth 10)
```

> 也可以在 `scheduled_task.tf` 加 `state = "DISABLED"` 後 `terraform apply`，效果相同。

### Step 2：清空 ECR images

⚠️ `--image-ids` 不接受 shell 變數直接傳入，需寫入暫存檔再用 `file://` 讀取。

```powershell
# PowerShell（Windows）
$REPO = "infra-lab-dev-app"

$imageIds = aws ecr list-images `
  --repository-name $REPO `
  --region us-east-1 `
  --query 'imageIds[*]' `
  --output json | ConvertFrom-Json

Write-Output "Images to delete: $($imageIds.Count)"

$imageIds | ConvertTo-Json | Out-File -FilePath "$env:TEMP\ecr-images.json" -Encoding utf8

aws ecr batch-delete-image `
  --repository-name $REPO `
  --region us-east-1 `
  --image-ids "file://$env:TEMP\ecr-images.json" `
  --query '{deleted:imageIds | length(@), failures:failures | length(@)}' `
  --output json
# 預期：{"deleted": N, "failures": 0}
```

```bash
# Bash（macOS/Linux）
REPO="infra-lab-dev-app"
aws ecr list-images --repository-name "$REPO" --region us-east-1 \
  --query 'imageIds[*]' --output json > /tmp/ecr-images.json
aws ecr batch-delete-image --repository-name "$REPO" --region us-east-1 \
  --image-ids file:///tmp/ecr-images.json \
  --query '{deleted:imageIds | length(@), failures:failures | length(@)}' --output json
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

```powershell
# PowerShell（Windows）
Write-Output "=== ECS Cluster ==="
aws ecs describe-clusters --clusters infra-lab-dev-cluster --region us-east-1 `
  --query 'clusters[0].status' --output text
# 預期：INACTIVE

Write-Output "=== ALB ==="
aws elbv2 describe-load-balancers --names infra-lab-dev-alb --region us-east-1 2>&1 | `
  Select-String "LoadBalancerNotFound" | ForEach-Object { "NOT FOUND (OK)" }

Write-Output "=== VPC ==="
aws ec2 describe-vpcs --region us-east-1 `
  --filters Name=tag:Project,Values=infra-lab Name=tag:Environment,Values=dev `
  --query 'Vpcs | length(@)' --output text
# 預期：0

Write-Output "=== ECR Repository ==="
aws ecr describe-repositories --repository-names infra-lab-dev-app --region us-east-1 2>&1 | `
  Select-String "RepositoryNotFoundException" | ForEach-Object { "NOT FOUND (OK)" }

Write-Output "=== Secrets Manager ==="
aws secretsmanager describe-secret --secret-id "infra-lab-dev/ecs/app-config" `
  --region us-east-1 2>&1 | Select-String "ResourceNotFoundException" | `
  ForEach-Object { "NOT FOUND (OK)" }
```

```bash
# Bash（macOS/Linux）
echo "ECS:" && aws ecs describe-clusters --clusters infra-lab-dev-cluster --region us-east-1 --query 'clusters[0].status' --output text
echo "ALB:" && aws elbv2 describe-load-balancers --names infra-lab-dev-alb --region us-east-1 2>&1 | grep -o LoadBalancerNotFound
echo "VPC:" && aws ec2 describe-vpcs --region us-east-1 --filters Name=tag:Project,Values=infra-lab Name=tag:Environment,Values=dev --query 'Vpcs | length(@)' --output text
echo "ECR:" && aws ecr describe-repositories --repository-names infra-lab-dev-app --region us-east-1 2>&1 | grep -o RepositoryNotFoundException
echo "Secret:" && aws secretsmanager describe-secret --secret-id "infra-lab-dev/ecs/app-config" --region us-east-1 2>&1 | grep -o ResourceNotFoundException
```

### Step 6：ecs-app repo 處理（選擇性）

`changken/ecs-app` 的 GitHub Actions workflow 在 push 時會嘗試：
- ECR push（已刪除 → 失敗）
- CodeDeploy deployment（已刪除 → 失敗）

若之後不再重建此 lab，建議停用 workflow。

**方法 A：GitHub UI（最簡單）**

前往：`https://github.com/changken/ecs-app/actions/workflows/deploy.yml`
→ 右上角 `⋯` → **Disable workflow**

**方法 B：gh CLI（需先安裝）**

```bash
gh workflow disable deploy.yml --repo changken/ecs-app
```

> gh CLI 安裝：https://cli.github.com/

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
