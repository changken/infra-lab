# Scheduled Task Demo（EventBridge Scheduler）

## 架構

```
EventBridge Scheduler（rate 5 minutes）
    │
    │  scheduler role：ecs:RunTask + iam:PassRole
    ▼
ECS RunTask
    └── Task Definition: infra-lab-dev-job
          ├── 同一個 ECR image（infra-lab-dev-app）
          ├── command = ["/app/job"]   ← CMD override，不啟動 HTTP server
          ├── Secrets Manager 注入（API_KEY）
          └── CloudWatch Logs（stream prefix: job）
```

Task 跑完後自動終止，不佔常駐費用。

## 對比 Kubernetes CronJob

| 概念 | K8s CronJob | ECS Scheduled Task |
|------|------------|-------------------|
| 排程定義 | CronJob YAML（`spec.schedule`）| EventBridge Scheduler |
| 執行單元 | Pod（跑完 controller 刪除）| ECS Task（跑完自動終止）|
| 同 image 執行不同邏輯 | command/args override | `command` override in task def |
| 失敗重試 | `spec.backoffLimit` | `retry_policy.maximum_retry_attempts` |
| 日誌 | `kubectl logs job/<name>` | CloudWatch Logs |
| 費用 | 佔 Node CPU/Memory | 按 Task vCPU-sec + GB-sec 計費 |

## 設計重點

### 同一個 image，兩個用途

`infra-lab-dev-app` image 同時包含兩個 binary：

```
/app/server  ← ECS Service 用（HTTP server，持續跑）
/app/job     ← Scheduled Task 用（跑完 exit 0）
```

Task Definition 用 `command` 欄位切換：
```hcl
# Server Task Definition（ecs.tf）
# command 未設定 → Dockerfile CMD: ["./server"]

# Job Task Definition（scheduled_task.tf）
command = ["/app/job"]
```

### 不需要 portMappings 和 healthCheck

Job Task 沒有 HTTP server，不需要對外暴露 port，
也不需要 ALB health check。Task Definition 只設 logging。

### Secrets Manager 注入同樣有效

Job Task 使用相同的 `secrets` block，ECS Agent 在 task 啟動時自動注入：
```json
{
  "secret_injected": true   // 驗證 API_KEY 環境變數已注入
}
```

## 手動觸發

```bash
# 方法一：使用 terraform output 的指令
terraform output -raw job_run_command | bash

# 方法二：直接下指令
TASK_ARN=$(aws ecs run-task \
  --cluster infra-lab-dev-cluster \
  --task-definition infra-lab-dev-job \
  --launch-type FARGATE \
  --region us-east-1 \
  --network-configuration 'awsvpcConfiguration={
    subnets=[subnet-xxx,subnet-yyy],
    securityGroups=[sg-xxx],
    assignPublicIp=ENABLED
  }' \
  --query 'tasks[0].taskArn' --output text)

echo "Task: $TASK_ARN"
```

## 觀察執行結果

```bash
# 等 task 結束
aws ecs wait tasks-stopped \
  --cluster infra-lab-dev-cluster \
  --tasks $TASK_ARN \
  --region us-east-1

# 確認 exit code
aws ecs describe-tasks \
  --cluster infra-lab-dev-cluster \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --query 'tasks[0].{StopCode:stopCode,ExitCode:containers[0].exitCode}' \
  --output json
# 預期：{"StopCode": "EssentialContainerExited", "ExitCode": 0}
```

## 查看 Job 日誌

```bash
# PowerShell
$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToUnixTimeMilliseconds()
aws logs filter-log-events `
  --log-group-name "/ecs/infra-lab-dev/app" `
  --log-stream-name-prefix "job" `
  --region us-east-1 `
  --start-time $startTime `
  --query 'events[].message' `
  --output text
```

**預期輸出：**
```
2026/06/25 05:15:50 Scheduled job starting...
{
  "job": "scheduled-report",
  "region": "us-east-1",
  "secret_injected": true,
  "timestamp": "2026-06-25T05:15:50Z",
  "version": "1.0.0"
}
2026/06/25 05:15:50 Job completed successfully, exiting 0
```

## 調整排程

修改 `scheduled_task.tf` 的 `schedule_expression`：

```hcl
# rate 語法
schedule_expression = "rate(5 minutes)"   # 每 5 分鐘（lab 觀察用）
schedule_expression = "rate(1 hour)"      # 每小時
schedule_expression = "rate(1 day)"       # 每天

# cron 語法（UTC）
schedule_expression = "cron(0 2 * * ? *)"   # 每天 UTC 02:00（台灣 10:00）
schedule_expression = "cron(0 9 ? * MON *)" # 每週一 09:00 UTC
```

套用後：
```bash
terraform apply -target=aws_scheduler_schedule.job
```

## 暫停 / 停用排程

```bash
# 暫停（不刪除資源）
aws scheduler update-schedule \
  --name infra-lab-dev-job \
  --state DISABLED \
  --region us-east-1 \
  # ... 其他必要參數

# 建議：在 Terraform 加 state = "DISABLED"
```

或在 `scheduled_task.tf` 加：
```hcl
resource "aws_scheduler_schedule" "job" {
  state = "DISABLED"  # 新增此行暫停排程
  ...
}
```

## Troubleshooting

### Task 立即 STOPPED，exit code 非 0

```bash
aws ecs describe-tasks \
  --cluster infra-lab-dev-cluster \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --query 'tasks[0].{Reason:stoppedReason,ExitCode:containers[0].exitCode,Log:containers[0].reason}' \
  --output json
```

常見原因：
- `CannotPullContainerError`：ECR image 不存在或 task execution role 缺少 ECR 權限
- `ResourceInitializationError`：Secrets Manager 取值失敗（確認 secret ARN 和 task execution role 的 `secretsmanager:GetSecretValue` 權限）
- Exit code 1：job binary 本身 panic（看 CloudWatch Logs）

### EventBridge 沒有觸發 Task

```bash
# 查看 Scheduler 執行記錄
aws scheduler get-schedule \
  --name infra-lab-dev-job \
  --region us-east-1 \
  --query '{State:state,Expression:scheduleExpression,Target:target.arn}'
```

確認：
- `State: ENABLED`
- Scheduler role 有 `ecs:RunTask` 和 `iam:PassRole` 權限
- Task Definition ARN 與 Scheduler target 一致
