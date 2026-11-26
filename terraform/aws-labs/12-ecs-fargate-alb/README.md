# Lab 12: ECS Fargate + ALB

在 ECS Fargate 前加入 Application Load Balancer，獲得穩定的 DNS 入口與健康檢查。
**費用等級 🔴 注意** — ALB 按小時計費，**Lab 完成後當天 destroy**。

**前置條件**：Lab 10（ECR）必須先完成，且 ECR 中有 `my-app:latest` image。

## 學習目標

- `aws_lb`：ALB 的基本設定（`internal`, `load_balancer_type`, subnets）
- `aws_lb_target_group`：`target_type = "ip"` 是 Fargate 的關鍵設定
- `aws_lb_listener`：`default_action { type = "forward" }` 轉發規則
- SG-to-SG 參考：ECS SG 的 ingress 只允許來自 ALB SG，而非 0.0.0.0/0
- `load_balancer` block：ECS Service 與 Target Group 的綁定方式
- `depends_on = [aws_lb_listener.http]`：防止 ECS 在 Listener 建好前搶先啟動

## 架構

```
Internet（port 80）
    ↓
ALB Security Group（0.0.0.0/0:80）
    ↓
Application Load Balancer（aws_lb）
    ↓ default_action: forward
ALB Listener（port 80）
    ↓ target_type = "ip"
Target Group（health check: GET /）
    ↓
ECS Service Security Group（只允許來自 ALB SG）
    ↓
Fargate Task（my-app:latest, port 80）
```

## 與 Lab 11 的差異

| | Lab 11（無 ALB）| Lab 12（有 ALB）|
|--|----------------|----------------|
| 入口 | Task Public IP（每次重啟可能改變）| ALB DNS 名稱（固定） |
| 健康檢查 | 無 | ALB 自動剔除不健康 Task |
| 擴縮 | 固定 desired_count | ALB 自動分流給多個 Task |
| 安全 | Task 直接對外 | Task 只接受 ALB 流量 |
| 費用 | 便宜 | +ALB $0.008/hr |

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_security_group.alb` | ALB 的 SG，允許 0.0.0.0/0:80 |
| 2 | `aws_security_group.ecs_service` | ECS 的 SG，只允許來自 `alb.id`（SG-to-SG） |
| 3 | `aws_lb.main` | `internal = false`, `load_balancer_type = "application"` |
| 4 | `aws_lb_target_group.app` | `target_type = "ip"`（Fargate 必填）, `health_check` |
| 5 | `aws_lb_listener.http` | `port = "80"`, `default_action { type = "forward" }` |
| 6 | `aws_ecs_service.app` | `load_balancer` block + `depends_on = [aws_lb_listener.http]` |

已預先填好（不需要修改）：
- Data sources（VPC、Subnets）
- CloudWatch Log Group
- IAM Task Execution Role
- ECS Cluster + Task Definition（已在 Lab 11 學過）

## 指令

### Step 1：取得 ECR Image URL

```bash
cd ../10-ecr-repository
terraform output repository_url
```

### Step 2：建立資源

```bash
cd ../12-ecs-fargate-alb
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入 ecr_image_url

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：11 to add
terraform apply
```

### Step 3：等待 ALB 和 Task 就緒（約 2-3 分鐘）

```bash
# 取得 ALB URL
terraform output alb_dns_name

# 確認 Target Group 健康狀態（等到 healthy 數量 > 0）
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

### Step 4：驗證

```bash
# ALB DNS 名稱是固定的，不像 Lab 11 的 IP 每次都不一樣
ALB_URL=$(terraform output -raw alb_dns_name)
curl $ALB_URL
```

預期看到 `Hello from ECR + ECS!`

**Windows PowerShell 版本：**
```powershell
$ALB_URL = terraform output -raw alb_dns_name
curl $ALB_URL
```

### 結束

```bash
# ⚠️ ALB 按小時計費，務必 destroy！
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| Fargate（0.25 vCPU / 0.5 GB）| ~$0.01/hr |
| ALB | $0.008/hr + LCU（Lab 期間 LCU 約 $0.00）|
| CloudWatch Logs | < $0.01 |
| **2 小時 Lab 合計** | **~$0.04** |

**ALB 費用較 Lambda/DynamoDB 高，請勿讓它過夜運行。**

## SG-to-SG 參考說明

```
傳統做法（較寬鬆）：
  ECS ingress: cidr_blocks = ["0.0.0.0/0"]  ← 任何人都能直接打到 Task

SG-to-SG 做法（本 lab）：
  ECS ingress: security_groups = [aws_security_group.alb.id]  ← 只有 ALB 能打到 Task
```

這讓 ECS task 在 AWS 網路層就被保護，即使有人知道 Task 的私有 IP 也無法直接存取。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `curl: (6) Could not resolve host` | ALB DNS 剛建好需要幾分鐘傳播 |
| ALB 回應 502 Bad Gateway | Task 還沒啟動，或健康檢查失敗（查 CloudWatch Logs）|
| ALB 回應 503 Service Unavailable | Target Group 中沒有 healthy target |
| Target health 顯示 `unhealthy` | Security Group 設定錯誤（ECS SG 沒允許來自 ALB SG 的流量）|
| Task 持續 PENDING | ECR image pull 失敗（ECS SG 的 egress 沒開、或 ECR image 不存在）|
| `depends_on` 移除後 apply 失敗 | ECS 嘗試在 Listener 建好前就向 Target Group 註冊，加回 `depends_on = [aws_lb_listener.http]`|
| destroy 卡住 | ALB 要等 ECS Service 先刪，再等 Target Group draining，等待即可（最多 5 分鐘）|
