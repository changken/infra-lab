# Lab 13: App Runner

體驗 AWS App Runner — 全代管容器服務，與 ECS（Lab 11-12）做對比。
**費用等級 🟡 注意** — App Runner 有閒置費，Lab 完成後當天 destroy。

**前置條件**：Lab 10（ECR）必須先完成，且 ECR 中有 `my-app:latest` image。

## 學習目標

- `aws_apprunner_service`：全代管容器服務的設定方式
- `source_configuration.image_repository`：指定 ECR image 和 port
- `authentication_configuration`：App Runner 存取私有 ECR 的 IAM Role
- `instance_configuration`：cpu/memory 使用字串格式（`"0.25 vCPU"`）
- `auto_deployments_enabled`：ECR image 更新時是否自動重新部署
- App Runner vs ECS：理解什麼情況選哪個

## 架構

```
ECR（my-app:latest）
    ↓ App Runner 用 IAM Role 拉取 image
App Runner Service
    ├── 自動 HTTPS（aws 配發憑證，無需設定）
    ├── 自動 Load Balancer（無需 ALB 資源）
    ├── 自動 Health Check
    └── 自動 Auto Scaling
            ↓ HTTPS
        瀏覽器 / curl（固定 URL，類似 Lambda Function URL）
```

**相比 Lab 12（ECS + ALB）少了哪些資源？**
不需要：`aws_ecs_cluster`、`aws_ecs_task_definition`、`aws_ecs_service`、
`aws_lb`、`aws_lb_target_group`、`aws_lb_listener`、`aws_security_group` × 2。

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_role.apprunner_ecr_access` | `Principal.Service = "build.apprunner.amazonaws.com"` |
| 2 | `aws_apprunner_service.app` | `source_configuration` 的 3 層巢狀結構 |

已預先填好：`aws_iam_role_policy_attachment.apprunner_ecr_access`

## App Runner vs ECS 選擇指南

| 需求 | 選 App Runner | 選 ECS Fargate |
|------|--------------|---------------|
| 快速部署 | ✅ | ❌（資源較多）|
| 自訂 VPC / 私有子網 | ❌ | ✅ |
| 連接 RDS / ElastiCache | 需要 VPC Connector | ✅ 原生支援 |
| 精細 Auto Scaling 設定 | 有限 | ✅ |
| 多容器（sidecar）| ❌ | ✅ |
| 費用（低流量）| 略高（有閒置費）| 略低 |

## 指令

### Step 1：取得 ECR Image URL

```bash
cd ../10-ecr-repository
terraform output repository_url
```

### Step 2：建立 App Runner Service

```bash
cd ../13-app-runner
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入 ecr_image_url

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：3 to add
terraform apply
```

### Step 3：等待服務就緒（約 2-3 分鐘）

```bash
# 查看 service 狀態
aws apprunner describe-service \
  --service-arn $(terraform output -raw service_arn) \
  --query 'Service.Status'

# 等到顯示 "RUNNING" 後再測試
```

### Step 4：驗證

```bash
# App Runner 直接輸出 HTTPS URL，不需要手動查 IP
terraform output service_url

curl $(terraform output -raw service_url)
```

**Windows PowerShell 版本：**
```powershell
$URL = terraform output -raw service_url
curl $URL
```

預期看到 `Hello from ECR + ECS!`

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| App Runner（0.25 vCPU，active）| $0.064/vCPU-hr × 0.25 = $0.016/hr |
| App Runner（0.5 GB memory）| $0.007/GB-hr × 0.5 = $0.0035/hr |
| App Runner（閒置 memory）| $0.007/GB-hr（即使沒有請求也計費）|
| **2 小時 Lab 合計** | **~$0.04** |

> 閒置也計 memory 費用，所以請不要讓它過夜。

## cpu / memory 合法組合

| cpu | 合法的 memory |
|-----|-------------|
| `"0.25 vCPU"` | `"0.5 GB"`, `"1 GB"`, `"2 GB"` |
| `"0.5 vCPU"` | `"1 GB"` ~ `"4 GB"` |
| `"1 vCPU"` | `"2 GB"` ~ `"8 GB"` |
| `"2 vCPU"` | `"4 GB"` ~ `"16 GB"` |
| `"4 vCPU"` | `"8 GB"` ~ `"32 GB"` |

注意：App Runner 的 cpu/memory 格式是字串（`"0.25 vCPU"`），
與 ECS 的數字格式（`cpu = 256`）不同。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| apply 後 service 狀態一直是 `CREATE_FAILED` | IAM Role 設定錯誤，Principal 必須是 `build.apprunner.amazonaws.com` |
| `CannotPullImage` / `ImagePullFailure` | ECR image 不存在，或 IAM Role 缺少 `AWSAppRunnerServicePolicyForECRAccess` |
| service 狀態是 `OPERATION_IN_PROGRESS` | 正在部署，等待 2-3 分鐘 |
| curl 回應 `502` / `503` | 容器啟動失敗，`container_port` 設定錯誤（nginx 預設是 80）|
| `InvalidParameterException: cpu is not valid` | cpu/memory 字串格式錯誤，參考上方表格 |
| terraform destroy 後 Console 還顯示 service | App Runner 刪除需要 1-2 分鐘，刷新即可 |
