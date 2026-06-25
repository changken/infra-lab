# ECS Exec Demo（類比 kubectl exec）

## 對比 kubectl exec

```bash
# kubectl（EKS）
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# ECS Exec（ECS Fargate）
aws ecs execute-command \
  --cluster infra-lab-dev-cluster \
  --task <task-id> \
  --container app \
  --interactive \
  --command "/bin/sh"
```

底層機制不同：
- `kubectl exec`：走 Kubernetes API Server → kubelet → container runtime
- `ECS Exec`：走 AWS Systems Manager Session Manager（SSM）→ task 內的 SSM agent

## 前置條件

### 1. Task Role 有 SSM 權限（`iam.tf`）

```hcl
resource "aws_iam_policy" "task_exec_command" {
  policy = jsonencode({
    Statement = [{
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}
```

### 2. ECS Service 開啟 execute_command（`ecs.tf`）

```hcl
resource "aws_ecs_service" "app" {
  enable_execute_command = true
  ...
}
```

### 3. 本機安裝 Session Manager Plugin

```bash
# macOS
brew install --cask session-manager-plugin

# Windows（已裝）
session-manager-plugin --version
# → 1.2.814.0
```

## 找到 Running Task

```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster infra-lab-dev-cluster \
  --service-name infra-lab-dev-app-service \
  --region us-east-1 \
  --query 'taskArns[0]' --output text)

TASK_ID=$(basename $TASK_ARN)
echo "Task: $TASK_ID"

# 確認 ECS Exec 已啟用
aws ecs describe-tasks \
  --cluster infra-lab-dev-cluster \
  --tasks $TASK_ARN \
  --region us-east-1 \
  --query 'tasks[0].{ExecuteCommand:enableExecuteCommand,Status:lastStatus}' \
  --output json
# 預期：{"ExecuteCommand": true, "Status": "RUNNING"}
```

## 互動式 Shell

```bash
aws ecs execute-command \
  --cluster infra-lab-dev-cluster \
  --task $TASK_ID \
  --container app \
  --region us-east-1 \
  --interactive \
  --command "/bin/sh"
```

## 非互動式（直接執行指令）

```bash
# 查看環境變數（確認 Secrets Manager 注入）
aws ecs execute-command \
  --cluster infra-lab-dev-cluster \
  --task $TASK_ID \
  --container app \
  --region us-east-1 \
  --interactive \
  --command "sh -c 'env | grep -E \"APP_|AWS_|API_KEY|GIT_\" | sort'"
```

## 容器內部驗證結果

```
=== 環境變數 ===
API_KEY=changeme-replace-with-real-secret   ← Secrets Manager 注入成功
APP_VERSION=1.0.0                           ← Task Definition 設定
AWS_DEFAULT_REGION=us-east-1               ← ECS 自動注入
AWS_EXECUTION_ENV=AWS_ECS_FARGATE           ← 確認跑在 Fargate
AWS_REGION=us-east-1
GIT_COMMIT=d79bd4f                          ← Docker build-arg（CI/CD 注入）

=== Process List ===
PID 1   ./server                            ← 直接是 app（無 init process）
PID 9   amazon-ssm-agent                   ← ECS Exec 的 SSM agent
PID 34  ssm-agent-worker

=== 對外 IP ===
3.86.196.162                                ← Public subnet，直接出外網（無 NAT）
```

### 關鍵觀察

**PID 1 是 app 本身**，不是 init（如 tini、dumb-init）。
ECS Fargate 的 SSM agent 是由 ECS agent 以 sidecar 形式注入，不佔用 PID 1。

**`AWS_EXECUTION_ENV=AWS_ECS_FARGATE`** 可用於在程式碼中判斷執行環境：
```go
if os.Getenv("AWS_EXECUTION_ENV") == "AWS_ECS_FARGATE" {
    // ECS-specific logic
}
```

## ECS Task Metadata v4

容器內可查詢自身 task 資訊（不需要 IAM 權限，link-local address）：

```bash
# 在容器內執行
wget -qO- $ECS_CONTAINER_METADATA_URI_V4/task | jq '{
  Cluster, Family, Revision, TaskARN,
  CPU: .Limits.CPU,
  Memory: .Limits.Memory
}'
```

輸出：
```json
{
  "Cluster": "arn:aws:ecs:us-east-1:.../infra-lab-dev-cluster",
  "Family": "infra-lab-dev-app",
  "Revision": "8",
  "TaskARN": "arn:aws:ecs:us-east-1:.../task/...",
  "CPU": 0.25,
  "Memory": 512
}
```

對比 EKS 的 Downward API（`fieldRef: fieldPath: metadata.name`），
ECS 用的是 HTTP metadata endpoint，不需要 YAML 宣告。

## Troubleshooting

### `ExecuteCommandError: execute command failed`

```bash
# 確認 task 有 ECS Exec 功能
aws ecs describe-tasks \
  --cluster infra-lab-dev-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].enableExecuteCommand'
# 必須是 true，否則需重新部署 service（enable_execute_command 是 immutable）
```

### Session Manager Plugin 未安裝

```
SessionManagerPlugin is not found
```

```bash
# macOS
brew install --cask session-manager-plugin

# Windows — 下載安裝包
# https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

### Task Role 缺少 ssmmessages 權限

```
An error occurred (TargetNotConnected) when calling the ExecuteCommand operation
```

確認 Task Role 有 `ssmmessages:*` 四個 action，且 task 已重新啟動（新 task 才會套用新 role）。
