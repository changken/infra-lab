# Lab 13b: ECS Express Gateway Service

> **暫停使用**：目前 AWS Provider `aws_ecs_express_gateway_service` 建立出的 service
> 會卡在 `CANARY 5%` deployment，單一 task lab 會停在 `requestedTaskCount=0`，
> 最後 `terraform apply` timeout。請先改做 Lab 12（ECS + ALB）或 Lab 13（App Runner）。

體驗 AWS ECS Express Gateway Service — 2025 年底推出的全代管容器部署方式。
**費用等級 🟡 注意** — 底層使用 ALB，Lab 完成後當天 destroy。

**前置條件**：Lab 10（ECR）必須先完成，且 ECR 中有 `my-app:latest` image。

> **⚠️ Provider 版本注意**：`aws_ecs_express_gateway_service` 在 v6.23.0（2025/11/26）才加入。
> 本 Lab 使用 `>= 6.23.0`，與其他 lab 的 `~> 5.0` 不同，`terraform init` 時會下載新 Provider。

## 學習目標

- `aws_ecs_express_gateway_service`：新一代全代管容器服務
- **Infrastructure Role**：ECS Express 特有，讓 ECS 代替你建 ALB/SG/Auto Scaling
- Execution Role vs Infrastructure Role 的差異（principal 不同）
- `primary_container` block：極簡的容器設定（vs Lab 12 的 Task Definition JSON）
- `ingress_paths[0].endpoint`：服務的公開 HTTPS endpoint

## 架構

```
ECR（my-app:latest）
    ↓ Execution Role 拉取 image
ECS Express Gateway Service
    ├── Infrastructure Role 自動建立：
    │   ├── ALB
    │   ├── Target Group（target_type=ip）
    │   ├── Security Group（ALB + ECS）
    │   └── Auto Scaling Policy
    └── HTTPS endpoint（ingress_paths[0].endpoint）
            ↓
        瀏覽器 / curl
```

**相比 Lab 12（手動 ECS+ALB）省掉了哪些資源？**

| Lab 12（手動）| 本 Lab（Express）|
|--------------|----------------|
| `aws_ecs_cluster` | ❌ 不需要 |
| `aws_ecs_task_definition` | ❌ 不需要 |
| `aws_ecs_service` | ❌ 不需要 |
| `aws_lb` + `aws_lb_target_group` + `aws_lb_listener` | ❌ 不需要 |
| `aws_security_group` × 2 | ❌ 不需要 |
| `aws_iam_role` × 1 | ✅ 需要 **2 個** Role |
| **合計 11 個資源** | **合計 5 個資源** |

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_role.infrastructure` | `Principal.Service = "ecs.amazonaws.com"`（不同於 execution role）|
| 2 | `aws_iam_role_policy_attachment.infrastructure` | Express Gateway 專用的 managed policy |
| 3 | `aws_ecs_express_gateway_service.app` | `primary_container` block + 兩個 role ARN |

已預先填好：`aws_cloudwatch_log_group`、Execution Role + Policy Attachment

## 指令

### Step 1：取得 ECR Image URL

```bash
cd ../10-ecr-repository
terraform output repository_url
```

### Step 2：建立 Express Gateway Service

```bash
cd ../13-ecs-express-gateway
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入 ecr_image_url

terraform init      # 會下載 Provider v6.x，需要一點時間
terraform fmt
terraform validate
terraform plan      # 預期：5 to add
terraform apply     # ALB 建立需要時間，create timeout 預設 30 分鐘
```

> 目前 Provider 無法設定 Express Gateway 的 deployment strategy；AWS 預設使用 Canary。
> 本 lab 已設定 `wait_for_steady_state = true`，避免 service 尚未真正啟動時就輸出不可用 URL。

### Step 3：驗證

```bash
# 取得服務 URL（自動 HTTPS，不需要手動查 IP）
terraform output service_url

curl $(terraform output -raw service_url)
```

**Windows PowerShell 版本：**
```powershell
$URL = terraform output -raw service_url
curl $URL
```

預期看到 `Hello from ECR + ECS!`

### Step 4：查看 Console 對照

到 AWS Console → ECS → Express Gateway Services，
可以看到 AWS 自動建立的 ALB、Target Group、Auto Scaling Policy。
這些資源由 ECS 代管，不會出現在你的 Terraform state 中。

### 結束

```bash
# ECS Express 會先清理 ALB 等資源再刪除 Service，約需 5-10 分鐘
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| Fargate（0.25 vCPU / 0.5 GB）| ~$0.01/hr |
| ALB（自動建立）| $0.008/hr + LCU |
| CloudWatch Logs | < $0.01 |
| **2 小時 Lab 合計** | **~$0.04** |

> ALB 是 ECS 自動建立的，destroy 時 ECS 也會自動清除，不會留下孤立費用。

## Infrastructure Role 說明

ECS Express 需要兩個 IAM Role，職責完全不同：

| | Execution Role | Infrastructure Role |
|--|---------------|-------------------|
| **由誰使用** | ECS Task（container agent）| ECS 控制平面 |
| **使用時機** | Task 啟動時（拉 image、寫 log）| Service 建立/更新/刪除時 |
| **Trust Principal** | `ecs-tasks.amazonaws.com` | `ecs.amazonaws.com` |
| **Managed Policy** | `AmazonECSTaskExecutionRolePolicy` | `AmazonECSInfrastructureRolePolicyForExpressGatewayService` |
| **建立後可修改** | ✅ | ❌ 不可修改，需重建 Service |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `NoSuchEntity` on policy_arn | Infrastructure Policy 名稱錯誤，執行 `aws iam list-policies --query 'Policies[?contains(PolicyName, \`ExpressGateway\`)]'` 確認正確名稱 |
| apply 卡在 `aws_ecs_express_gateway_service` | 正常，ALB 建立需要時間，等候即可（最多 30 分鐘）|
| `infrastructure_role_arn` 錯誤 | Principal 必須是 `ecs.amazonaws.com`，不是 `ecs-tasks` 也不是 `build.apprunner` |
| 服務建立成功但 curl 502 | 容器啟動中，等 1-2 分鐘後再試 |
| URL 連線被拒、`runningCount=0`、`requestedTaskCount=0` | Express Gateway 預設 Canary deployment 可能卡住，先用下方指令確認；若持續不動，改做 Lab 12（ECS + ALB）或 Lab 13（App Runner）較穩定 |
| destroy 卡住 | ECS 正在清理 ALB 等資源，等候即可（最多 10 分鐘）|
| `An argument named "aws_ecs_express_gateway_service" is not expected` | Provider 版本太舊，需要 `>= 6.23.0`，執行 `terraform init -upgrade` |

```bash
aws ecs describe-services \
  --cluster default \
  --services ecs-express-lab \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,revisions:currentServiceRevisions}' \
  --output json
```
