# ECS Fargate Lab — 清除步驟

## 快速清除

```bash
terraform destroy -auto-approve
```

## 如果 destroy 卡住

### ECR 有 images
```bash
# 清空 ECR repository 再 destroy
REPO=$(terraform output -raw ecr_repository_url | cut -d/ -f2-)
aws ecr list-images --repository-name "$REPO" --query 'imageIds[*]' --output json | \
  xargs -I{} aws ecr batch-delete-image --repository-name "$REPO" --image-ids '{}'
```

### ECS Service 還有 running tasks
```bash
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)

# 先縮到 0，讓 tasks drain
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 0

# 等 tasks 停止後再 destroy
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
terraform destroy -auto-approve
```

### Secrets Manager recovery window 擋住
`aws_secretsmanager_secret` 設定了 `recovery_window_in_days = 0`，應可立即刪除。
如果仍報錯：
```bash
SECRET_ARN=$(terraform output -raw secret_arn)
aws secretsmanager delete-secret --secret-id "$SECRET_ARN" --force-delete-without-recovery
terraform destroy -auto-approve
```

### ALB 有連線無法刪除
通常是 target group 還有 connections，稍等 30 秒後再 `terraform destroy`。

## Apply 中途失敗（partially-failed replacement）

### 症狀
`terraform apply` 途中失敗，下次 apply 出現 `deposed object` 或 `already exists`。

### 原因
`aws_lb_target_group` 是 ForceNew 資源（改 port/protocol 就得重建）。
若刪除舊 TG 失敗（Listener 還在使用），Terraform 會把舊 TG 標記為 `deposed`，
等下次 apply 完成清理。

### 解法
直接再跑一次 `terraform apply`，Terraform 會：
1. 識別 deposed 物件
2. 完成剩餘的 update（ECS Service、Listener）
3. 刪除 deposed 的舊 TG

```bash
terraform apply -auto-approve
```

### 為什麼這次沒問題？
`aws_lb_target_group` 已改用：
- `name_prefix`（非固定 `name`）→ create_before_destroy 時名稱不衝突
- `lifecycle { create_before_destroy = true }` → 先建新 TG，Listener 切換後再刪舊 TG

### 快速連續部署導致 ECS_UPDATE_ERROR

**症狀**

短時間內多次 push，前一個 CodeDeploy deployment 還沒完全結束，
下一個就啟動，出現：

```
"code": "ECS_UPDATE_ERROR",
"message": "TaskSet <ecs-svc/xxx> is behind prod listener ... Verify that the TaskSet is still serving production traffic."
```

**原因**

CodeDeploy 在 deployment 結束後需要時間更新 task set 狀態（PRIMARY/DRAINING swap）。
若此期間新 deployment 啟動，CodeDeploy 的 prod listener 紀錄與實際 ALB 狀態短暫不一致。

**影響**

服務不中斷（前一個 deployment 已成功，task 仍在跑）。
只有那次 deployment 標記為 Failed，服務本身健康。

**確認服務正常**

```bash
ALB="http://<alb-dns>"
curl $ALB/health  # 應回傳 ok

aws ecs describe-services \
  --cluster infra-lab-dev-cluster \
  --services infra-lab-dev-app-service \
  --query 'services[0].{Running:runningCount,TaskSets:taskSets[].{Status:status,TG:loadBalancers[0].targetGroupArn}}' \
  --output json
# PRIMARY task set 正常即可
```

**解法**

等前一個 deployment 完全結束（DRAINING task set 消失）後再觸發新的：
```bash
# 確認沒有 InProgress deployment 再 push
aws deploy list-deployments \
  --application-name infra-lab-dev-app \
  --deployment-group-name infra-lab-dev-dg \
  --include-only-statuses InProgress \
  --query 'deployments' --output json
# 回傳 [] 才 push
```

### 切換到 CODE_DEPLOY 後 task 起不來（INVALID_ECS_SERVICE）

**症狀**

切換 `deployment_controller = "CODE_DEPLOY"` 並 apply 後，ECS Service running count 變 0，
觸發 CodeDeploy 部署立即失敗：

```
"code": "INVALID_ECS_SERVICE",
"message": "The target ECS service must be configured using one of those two target groups."
```

**原因**

`deployment_controller` 改變會讓 Terraform 標記 ECS Service 為 ForceNew，
但實際上 AWS 有時不會完整清除舊 task set。
舊 PRIMARY task set 可能仍指向切換前的 TG（已被 Terraform 刪除）。
CodeDeploy 要求 service 的 current TG 必須是 Blue 或 Green 其中之一，兩者都不是就報錯。

**診斷**

```bash
aws ecs describe-services \
  --cluster infra-lab-dev-cluster \
  --services infra-lab-dev-app-service \
  --query 'services[0].taskSets[].{ID:id,Status:status,TG:loadBalancers[0].targetGroupArn}' \
  --output json
# 如果 TG ARN 不是 blue 或 green，就是這個問題
```

**解法：強制重建 ECS Service**

```bash
terraform apply -replace=aws_ecs_service.app
```

此指令：
1. 刪除舊 service（含所有 task sets）
2. 重建 service，新 PRIMARY task set 正確指向 `blue` TG
3. 完成後 2 tasks 正常 running，CodeDeploy 可正常部署

## 清除後驗證

```bash
# 確認 ECS cluster 已刪除
aws ecs describe-clusters --clusters infra-lab-dev-cluster --query 'clusters[0].status'
# 預期：空結果或 "INACTIVE"

# 確認 ALB 已刪除
aws elbv2 describe-load-balancers --names infra-lab-dev-alb 2>&1 | grep -c LoadBalancerNotFound
# 預期：1

# 確認 VPC 已刪除
aws ec2 describe-vpcs --filters Name=tag:Project,Values=infra-lab | jq '.Vpcs | length'
# 預期：0
```

## 費用驗證

清除後到 AWS Cost Explorer 確認次日無額外費用。
主要費用項目：
- ECS Fargate（按 vCPU-hr 和 GB-hr 計費）
- ALB（$0.008/hr + LCU）
- CloudWatch Logs Ingestion
- Secrets Manager（按 secret 數量計費）
