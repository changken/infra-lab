# Lab 11: ECS Fargate

從 ECR 拉取 Docker image，在 ECS Fargate 上執行容器服務。
**費用等級 🟡 注意** — Fargate 按 vCPU/Memory 計費，Lab 完成後請立即 destroy。

**前置條件**：Lab 10（ECR）必須先完成，且 ECR 中有 `my-app:latest` image。

## 學習目標

- `aws_ecs_cluster`：ECS 的邏輯容器，Fargate 模式下不需要管 EC2
- `aws_ecs_task_definition`：定義容器規格（image、cpu、memory、port）
- `network_mode = "awsvpc"`：Fargate 必須使用的網路模式
- `aws_ecs_service`：維持 desired_count 個 Task 持續執行
- `assign_public_ip = true`：無 ALB 時直接給 Task 公開 IP（Lab 12 改用 ALB）
- ECS Task Execution Role：拉 ECR image + 寫 CloudWatch Logs 的 IAM 權限

## 架構

```
本地 / Lab 10
└── ECR Repository（my-app:latest）
        ↓ ECS 拉取 image
    Task Definition（256 CPU / 512 MB）
        ↓ ECS Service 維持 1 個 Task
    Fargate Task
        ├── Public IP（直接對外）
        └── Security Group（允許 port 80）
                ↓ HTTP
            瀏覽器 / curl
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_ecs_cluster` | ECS 叢集，Fargate 模式 |
| 2 | `aws_ecs_task_definition` | `requires_compatibilities`, `network_mode`, `execution_role_arn`, `container_definitions` |
| 3 | `aws_security_group` | 允許 port 80 ingress |
| 4 | `aws_ecs_service` | `launch_type`, `network_configuration`, `assign_public_ip = true` |

已預先填好（不需要修改）：
- `data "aws_vpc" "default"` + `data "aws_subnets" "default"`
- IAM Task Execution Role + Policy Attachment
- CloudWatch Log Group（container logs 輸出目的地）
- `locals.container_definitions`（container JSON，在 locals.tf）

## 指令

### Step 1：取得 Lab 10 的 ECR Image URL

```bash
# 在 Lab 10 目錄執行
cd ../10-ecr-repository
terraform output repository_url
# 記下輸出的 URL，格式如：123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app
```

### Step 2：建立 ECS Fargate Service

```bash
cd ../11-ecs-fargate
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，把 ecr_image_url 換成上面取得的 URL + :latest
```

```bash
terraform init
terraform fmt
terraform validate
terraform plan    # 預期：7 to add
terraform apply
```

### Step 3：等待 Task 啟動（約 1-2 分鐘）

```bash
# 確認 Task 狀態（等到 lastStatus 變成 RUNNING）
aws ecs list-tasks \
  --cluster ecs-lab \
  --service-name ecs-lab-service

# 查看 Task 詳細狀態
aws ecs describe-tasks \
  --cluster ecs-lab \
  --tasks $(aws ecs list-tasks --cluster ecs-lab --service-name ecs-lab-service --query 'taskArns[0]' --output text)
```

### Step 4：取得 Public IP 並驗證

```bash
# 用 terraform output 取得完整指令
terraform output get_public_ip_commands

# 或用以下一行指令（bash）取得 IP
TASK_ARN=$(aws ecs list-tasks --cluster ecs-lab --service-name ecs-lab-service --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster ecs-lab --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "http://$PUBLIC_IP"
curl http://$PUBLIC_IP
```

**Windows PowerShell 版本：**
```powershell
$TASK_ARN = aws ecs list-tasks --cluster ecs-lab --service-name ecs-lab-service --query 'taskArns[0]' --output text
$ENI_ID = aws ecs describe-tasks --cluster ecs-lab --tasks $TASK_ARN `
  --query 'tasks[0].attachments[0].details[?name==``networkInterfaceId``].value' --output text
$PUBLIC_IP = aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID `
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text

Write-Host "http://$PUBLIC_IP"
curl "http://$PUBLIC_IP"
```

預期看到 Lab 10 的 `app/index.html` 內容：`Hello from ECR + ECS!`

### 結束

```bash
terraform destroy -auto-approve
```

> **注意**：ECR repository 在 Lab 10 目錄管理，這裡只 destroy ECS 資源。
> Lab 10 的 ECR repository 可以留著給 Lab 12/14 用。

## 成本

| 資源 | 費用 |
|------|------|
| Fargate（0.25 vCPU / 0.5 GB）| ~$0.01/hr（≈ $0.01 per lab session） |
| CloudWatch Logs | < $0.01（7 天 retention，少量 log） |
| ECR 傳輸（同 region）| 免費 |
| **一次 Lab 合計** | **< $0.10** |

**Lab 完成後請 destroy，Fargate 任務持續執行才計費。**

## MUTABLE vs IMMUTABLE / assign_public_ip vs ALB

| 方式 | 適合場景 | 缺點 |
|------|---------|------|
| `assign_public_ip = true`（本 lab）| 開發 / 測試 | IP 每次重啟可能變動，不適合生產 |
| ALB（Lab 12）| 生產環境 | 多一個 ALB 費用（$0.008/hr） |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Task 持續 PENDING / STOPPED | 通常是 image pull 失敗或 IAM 權限問題，看 CloudWatch Logs |
| `exec /docker-entrypoint.sh: exec format error` | image 架構不符（mac M1 build 的 arm64 image push 到 x86 環境），需重新 build 指定 `--platform linux/amd64` |
| `CannotPullContainerError` | ECR 認證過期 或 Security Group 的 egress 沒開（Task 需要對外拉 image） |
| `no basic auth credentials` | 在 Lab 10 重新執行 `aws ecr get-login-password | docker login` |
| curl 沒回應 | Task 還在啟動中（等 1-2 分鐘），或 Security Group ingress 規則錯誤 |
| `InvalidParameterException: cpu is not valid for Fargate` | cpu/memory 組合不合法，參考 task_size 文件 |
| terraform destroy 卡住 | ECS Service 正在 drain task，等待即可（最多 2-3 分鐘） |
