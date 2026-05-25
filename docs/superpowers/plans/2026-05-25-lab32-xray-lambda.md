# Lab 32: X-Ray + Lambda + API Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `terraform/labs/32-xray-lambda/` 的填空式 lab 骨架，包含 5 個 TODO 資源群組（IAM、Lambda、API GW REST API、API GW Deployment/Stage、Lambda Permission）、Lambda 原始碼、完整 README，以及純 CLI 驗證流程。

**Architecture:** API Gateway REST API（xray_tracing_enabled）→ Lambda（tracing_config Active），X-Ray 自動建立 Segment 並傳遞 Trace ID。resource body 保持空白（`# TODO`），詳細提示寫在 comment 上方。

**Tech Stack:** Terraform >= 1.0, AWS Provider ~> 5.0, Archive Provider ~> 2.0, Python 3.12

---

## 檔案對應表

| 檔案 | 動作 | 說明 |
|------|------|------|
| `terraform/labs/32-xray-lambda/terraform.tf` | 建立 | Provider 設定（aws + archive）|
| `terraform/labs/32-xray-lambda/variables.tf` | 建立 | 輸入變數 |
| `terraform/labs/32-xray-lambda/locals.tf` | 建立 | common_tags |
| `terraform/labs/32-xray-lambda/.gitignore` | 建立 | 含 src/*.zip |
| `terraform/labs/32-xray-lambda/terraform.tfvars.example` | 建立 | 範例值 |
| `terraform/labs/32-xray-lambda/src/handler.py` | 建立 | Lambda 程式碼（已完成）|
| `terraform/labs/32-xray-lambda/main.tf` | 建立 | 5 個 TODO 資源群組骨架 |
| `terraform/labs/32-xray-lambda/outputs.tf` | 建立 | 4 個輸出值 |
| `terraform/labs/32-xray-lambda/README.md` | 建立 | Lab 指南（含完整 CLI 驗證腳本）|
| `terraform/labs/32-xray-lambda/.terraform.lock.hcl` | 產生 | `terraform init` 後提交 |

---

## Task 1：建立基礎設定檔

**Files:**
- Create: `terraform/labs/32-xray-lambda/terraform.tf`
- Create: `terraform/labs/32-xray-lambda/variables.tf`
- Create: `terraform/labs/32-xray-lambda/locals.tf`
- Create: `terraform/labs/32-xray-lambda/.gitignore`
- Create: `terraform/labs/32-xray-lambda/terraform.tfvars.example`

- [ ] **Step 1: 建立 terraform.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 2: 建立 variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "xray-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

- [ ] **Step 3: 建立 locals.tf**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "32-xray-lambda"
    ManagedBy   = "terraform"
  }
}
```

- [ ] **Step 4: 建立 .gitignore**

```
# Terraform
*.tfstate
*.tfstate.backup
*.tfstate.lock.info
.terraform/
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# 敏感設定
*.tfvars
!terraform.tfvars.example

# Lambda 打包
src/*.zip
```

- [ ] **Step 5: 建立 terraform.tfvars.example**

```hcl
region      = "us-east-1"
project     = "xray-lab"
environment = "dev"
```

- [ ] **Step 6: Commit**

```bash
git add terraform/labs/32-xray-lambda/terraform.tf \
        terraform/labs/32-xray-lambda/variables.tf \
        terraform/labs/32-xray-lambda/locals.tf \
        "terraform/labs/32-xray-lambda/.gitignore" \
        terraform/labs/32-xray-lambda/terraform.tfvars.example
git commit -m "feat(labs): add lab 32 base config files"
```

---

## Task 2：建立 Lambda 原始碼

**Files:**
- Create: `terraform/labs/32-xray-lambda/src/handler.py`

- [ ] **Step 1: 建立 src/ 目錄並寫入 handler.py**

```python
import json
import time


def handler(event, context):
    time.sleep(0.1)  # 模擬業務延遲，讓 X-Ray trace 有意義的數字
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from X-Ray lab!",
            "path": event.get("path", "/"),
        }),
    }
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/32-xray-lambda/src/handler.py
git commit -m "feat(labs): add lab 32 lambda handler source"
```

---

## Task 3：建立 main.tf（填空式骨架）

**Files:**
- Create: `terraform/labs/32-xray-lambda/main.tf`

- [ ] **Step 1: 建立 main.tf**

```hcl
#==============================================================
# 學習目標：X-Ray + Lambda + API Gateway 分散式追蹤
#
# 核心問題：如何在無伺服器架構中追蹤跨服務的請求鏈路？
#
# X-Ray 三層概念（面試必考）：
#   Trace     → 一次完整的 end-to-end 請求（包含所有 Segment）
#   Segment   → 一個服務的處理時間（API GW 的轉發、Lambda 的執行）
#   Subsegment → Segment 中更細粒度的操作（AWS SDK 呼叫、DB query）
#              → 需要 aws_xray_sdk 手動建立（本 lab 不使用 SDK）
#
# Lambda Tracing Mode（面試必考）：
#   PassThrough → 只傳遞上游送來的 Trace ID，不主動建立 Segment
#   Active      → Lambda runtime 主動送 Segment 至 X-Ray daemon
#              → 需要 AWSXRayDaemonWriteAccess IAM policy
#              → 本 lab 使用 Active mode
#
# API Gateway X-Ray：
#   xray_tracing_enabled = true 設在 aws_api_gateway_stage（非 Method 層）
#   API GW 自動建立自己的 Segment，並注入 X-Amzn-Trace-Id header 給 Lambda
#
# IAM 需要兩個 Policy（面試常考）：
#   AWSLambdaBasicExecutionRole → CloudWatch Logs 寫入
#   AWSXRayDaemonWriteAccess    → 送 trace 至 X-Ray
#   → 少了 XRayDaemonWriteAccess，Lambda trace 不會出現在 X-Ray
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：打包 Lambda 原始碼
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/src/handler.zip"
}


#--------------------------------------------------------------
# TODO 1: Lambda IAM Role（含 X-Ray 寫入權限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# [IAM Role]
#   name = "${var.project}-lambda-role"
#   tags = local.common_tags
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
# [Policy Attachment 1：CloudWatch Logs]
#   role       = aws_iam_role.lambda.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Policy Attachment 2：X-Ray]
#   role       = aws_iam_role.lambda.name
#   policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
#   # ← 包含 xray:PutTraceSegments、xray:PutTelemetryRecords 等權限

resource "aws_iam_role" "lambda" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Lambda Function（啟用 X-Ray Active Tracing）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
#   function_name    = "${var.project}-handler"
#   runtime          = "python3.12"
#   handler          = "handler.handler"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda.output_path
#   source_code_hash = data.archive_file.lambda.output_base64sha256
#   tags             = local.common_tags
#
#   tracing_config {
#     mode = "Active"
#     # PassThrough → 只傳遞 Trace ID，不送 Segment
#     # Active      → 主動送 Segment（本 lab 用這個）
#   }

resource "aws_lambda_function" "handler" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: API Gateway（REST API + Resource + Method + Integration）
#--------------------------------------------------------------
# 文件 (rest_api):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api
# 文件 (resource):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource
# 文件 (method):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method
# 文件 (integration):https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration
#
# [REST API]
#   name        = "${var.project}-api"
#   description = "X-Ray Lab API"
#   tags        = local.common_tags
#
# [Resource：/hello]
#   rest_api_id = aws_api_gateway_rest_api.main.id
#   parent_id   = aws_api_gateway_rest_api.main.root_resource_id
#   path_part   = "hello"
#
# [Method：POST /hello]
#   rest_api_id   = aws_api_gateway_rest_api.main.id
#   resource_id   = aws_api_gateway_resource.hello.id
#   http_method   = "POST"
#   authorization = "NONE"
#
# [Integration：Lambda Proxy]
#   rest_api_id             = aws_api_gateway_rest_api.main.id
#   resource_id             = aws_api_gateway_resource.hello.id
#   http_method             = aws_api_gateway_method.post.http_method
#   integration_http_method = "POST"   # ← Lambda invoke 固定用 POST
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.handler.invoke_arn

resource "aws_api_gateway_rest_api" "main" {
  # TODO
}

resource "aws_api_gateway_resource" "hello" {
  # TODO
}

resource "aws_api_gateway_method" "post" {
  # TODO
}

resource "aws_api_gateway_integration" "lambda" {
  # TODO
}


#--------------------------------------------------------------
# TODO 4: API Gateway Deployment + Stage（啟用 X-Ray）
#--------------------------------------------------------------
# 文件 (deployment): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment
# 文件 (stage):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage
#
# [Deployment]
#   rest_api_id = aws_api_gateway_rest_api.main.id
#   triggers = {
#     redeployment = sha1(jsonencode([
#       aws_api_gateway_resource.hello.id,
#       aws_api_gateway_method.post.id,
#       aws_api_gateway_integration.lambda.id,
#     ]))
#   }
#   # ← triggers 確保 method/integration 變更時 Terraform 會重新部署 API
#   lifecycle {
#     create_before_destroy = true
#   }
#
# [Stage：dev]
#   rest_api_id          = aws_api_gateway_rest_api.main.id
#   deployment_id        = aws_api_gateway_deployment.main.id
#   stage_name           = var.environment
#   xray_tracing_enabled = true
#   # ← X-Ray 開關在 Stage 層（不是 Method 或 Resource 層！）
#   tags                 = local.common_tags

resource "aws_api_gateway_deployment" "main" {
  # TODO
}

resource "aws_api_gateway_stage" "dev" {
  # TODO
}


#--------------------------------------------------------------
# TODO 5: Lambda Permission（允許 API Gateway 呼叫 Lambda）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.handler.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
#   # ← source_arn 限制只有這個 API GW 的任意 Stage/Method 可呼叫
#   #   格式：arn:aws:execute-api:<region>:<account>:<api-id>/<stage>/<method>
#   #   /*/*  = 所有 stage + 所有 method（適合 lab 環境）

resource "aws_lambda_permission" "apigw" {
  # TODO
}
```

- [ ] **Step 2: 驗證格式**

```bash
terraform -chdir=terraform/labs/32-xray-lambda fmt -check
```

Expected: 無輸出（格式正確）

- [ ] **Step 3: Commit**

```bash
git add terraform/labs/32-xray-lambda/main.tf
git commit -m "feat(labs): add lab 32 main.tf with TODO scaffolds"
```

---

## Task 4：建立 outputs.tf

**Files:**
- Create: `terraform/labs/32-xray-lambda/outputs.tf`

- [ ] **Step 1: 建立 outputs.tf**

```hcl
output "api_endpoint" {
  description = "API Gateway 端點（POST /hello）"
  value       = "${aws_api_gateway_stage.dev.invoke_url}/hello"
}

output "api_stage_arn" {
  description = "API Gateway Stage ARN"
  value       = aws_api_gateway_stage.dev.arn
}

output "lambda_function_name" {
  description = "Lambda 函數名稱"
  value       = aws_lambda_function.handler.function_name
}

output "xray_console_url" {
  description = "X-Ray Console 連結（需登入 AWS Console）"
  value       = "https://${var.region}.console.aws.amazon.com/xray/home#/traces"
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/32-xray-lambda/outputs.tf
git commit -m "feat(labs): add lab 32 outputs.tf"
```

---

## Task 5：建立 README.md

**Files:**
- Create: `terraform/labs/32-xray-lambda/README.md`

- [ ] **Step 1: 建立 README.md**

```markdown
# Lab 32: X-Ray + Lambda + API Gateway 分散式追蹤

> 開啟 API Gateway 和 Lambda 的 X-Ray Active Tracing，透過 AWS CLI 查看 Trace 結構、Service Map 與請求延遲分布。

**費用等級**：🟢 安全（$0，X-Ray 免費額度 100,000 traces/月）

---

## 學習目標

- 理解 X-Ray **Trace / Segment / Subsegment** 三層概念與差異
- 設定 Lambda `tracing_config { mode = "Active" }` 與 `AWSXRayDaemonWriteAccess` 的必要性
- 設定 API Gateway Stage 的 `xray_tracing_enabled = true`（注意：在 Stage 層，非 Method 層）
- 理解 `aws_api_gateway_deployment` 的 `triggers` 為何必要
- 用 AWS CLI 查詢 Trace 摘要、完整 trace 細節與 Service Graph

---

## 架構

```
curl POST /hello
   │
   ▼
API Gateway REST API（xray_tracing_enabled = true）
   │  自動注入 X-Amzn-Trace-Id header
   ▼
Lambda（tracing_config.mode = "Active"）
   │  runtime 送 Segment 至 X-Ray daemon
   ▼
X-Ray Service Map: [Client] → [API Gateway] → [Lambda]
```

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | `aws_iam_role` + 2× policy attachment | BasicExecutionRole + `AWSXRayDaemonWriteAccess` |
| 2 | `aws_lambda_function` | `tracing_config { mode = "Active" }` |
| 3 | `aws_api_gateway_rest_api` + resource + method + integration | `type = "AWS_PROXY"`、`integration_http_method = "POST"` |
| 4 | `aws_api_gateway_deployment` + `aws_api_gateway_stage` | `xray_tracing_enabled = true`、`triggers` 確保重新部署 |
| 5 | `aws_lambda_permission` | `principal = "apigateway.amazonaws.com"` |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate   # 填完所有 TODO 後再執行
terraform plan
terraform apply
```

> **注意**：resource body 空白時 `terraform validate` 會失敗，這是正常的。

---

## 驗證

### 1. 取得 API 端點

```bash
API_URL=$(terraform output -raw api_endpoint)
echo "API URL: $API_URL"
```

### 2. 送出請求（製造 Trace 資料）

```bash
for i in 1 2 3 4 5; do
  echo "=== Request $i ==="
  curl -s -X POST "$API_URL" | python3 -m json.tool
  sleep 1
done
```

**期望輸出**：
```json
{
    "message": "Hello from X-Ray lab!",
    "path": "/hello"
}
```

### 3. 等待 X-Ray 資料就緒

```bash
echo "等待 X-Ray 資料傳播（約 15 秒）..."
sleep 15
```

### 4. 查看 Trace 摘要

```bash
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 300))

aws xray get-trace-summaries \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --query 'TraceSummaries[*].{Id:Id,Duration:Duration,Status:Http.HttpStatus,HasError:HasError}' \
  --output table
```

**期望輸出**：看到 5 筆 trace，Duration 約 0.1-0.2 秒，Status 200，HasError False。

### 5. 查看完整 Trace 詳情

```bash
TRACE_ID=$(aws xray get-trace-summaries \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --query 'TraceSummaries[0].Id' \
  --output text)

echo "Trace ID: $TRACE_ID"

aws xray batch-get-traces \
  --trace-ids "$TRACE_ID" \
  --query 'Traces[0].Segments[*].Document' \
  --output text | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    doc = json.loads(line)
    duration = doc.get('end_time', 0) - doc.get('start_time', 0)
    print(f\"Segment: {doc.get('name'):<30} Duration: {duration:.3f}s\")
"
```

**期望輸出**：
```
Segment: xray-lab-handler               Duration: 0.112s
```

### 6. 查看 Service Graph

```bash
aws xray get-service-graph \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --query 'Services[*].{Name:Name,Type:Type}' \
  --output table
```

**期望輸出**：看到 `AWS::ApiGateway::Stage` 和 `AWS::Lambda::Function` 兩個節點。

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| X-Ray Traces（5 次）| $0（免費額度 100,000/月）|
| Lambda（5 次呼叫）| $0（免費額度 1M/月）|
| API Gateway REST API（5 次請求）| $0（免費額度 1M/月）|
| **合計** | **$0** |

---

## 核心概念釐清

### X-Ray 三層結構

```
Trace（一次完整請求，唯一 Trace ID）
  │
  ├── Segment（API Gateway 的轉發時間）
  │
  └── Segment（Lambda 的執行時間）
        │
        └── Subsegment（需 aws_xray_sdk 手動標記）
              例如：DynamoDB query、外部 HTTP 呼叫
```

### tracing_config mode 差異

| Mode | Lambda 行為 | 何時用 |
|------|------------|--------|
| `PassThrough` | 只轉傳上游 Trace ID，不建立 Segment | 不需追蹤 Lambda 本身 |
| `Active` | 主動建立 Segment，送至 X-Ray daemon | 本 lab，需 `AWSXRayDaemonWriteAccess` |

### API Gateway X-Ray 開關的位置

```hcl
# ❌ 錯誤：Method / Integration 層沒有 xray 設定
resource "aws_api_gateway_method" "post" { ... }

# ✅ 正確：xray_tracing_enabled 在 Stage 層
resource "aws_api_gateway_stage" "dev" {
  xray_tracing_enabled = true
}
```

### Deployment triggers 的必要性

```hcl
resource "aws_api_gateway_deployment" "main" {
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
}
```

沒有 `triggers`，修改 method/integration 後 Terraform 不會重新部署 API，
Stage 仍執行舊設定，curl 會收到錯誤回應。

### X-Ray Sampling Rule（預設）

```
預設 Sampling Rule：
  reservoir = 1 req/sec（固定取樣至少 1 個/秒）
  rate      = 5%（超出 reservoir 後，隨機取 5%）

→ lab 環境每秒 < 1 次請求，全部都會被 trace
```

---

## 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 追蹤跨服務延遲 | X-Ray | 自動傳遞 Trace ID，有 Service Map |
| 只需記錄錯誤日誌 | CloudWatch Logs | X-Ray 是 latency/dependency 分析工具 |
| 需要自訂業務邏輯追蹤 | aws_xray_sdk + Subsegment | 手動標記特定程式碼區塊 |
| 生產環境降低費用 | 自訂 Sampling Rule | 只追蹤部分請求 |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| X-Ray 沒有任何 trace | Lambda 缺少 `AWSXRayDaemonWriteAccess`，或 `tracing_config.mode` 未設為 `Active` |
| X-Ray 只有 API GW segment，沒有 Lambda segment | Lambda `tracing_config` 未設，或 IAM policy 缺少 XRay 權限 |
| `curl` 回傳 `{"message":"Internal Server Error"}` | `aws_lambda_permission` 未設，或 integration `type` 不是 `AWS_PROXY` |
| `curl` 回傳 `{"message":"Missing Authentication Token"}` | URL 路徑錯誤，確認 path_part = "hello"，URL 需打 `/hello` |
| `curl` 回傳 正確但 `get-trace-summaries` 無資料 | X-Ray 有延遲，等待 15-30 秒；或 `--start-time` 時間範圍不對 |
| `api_endpoint` output 是空的 | `aws_api_gateway_stage.dev.invoke_url` 依賴 stage 建立，確認 apply 完成 |
| API GW apply 後 curl 仍 404 | `aws_api_gateway_deployment` 缺少 `triggers`，執行 `terraform taint aws_api_gateway_deployment.main` 強制重建 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/32-xray-lambda/README.md
git commit -m "docs(labs): add lab 32 README with verification guide"
```

---

## Task 6：terraform init + fmt + 提交 lock file

**Files:**
- Generate: `terraform/labs/32-xray-lambda/.terraform.lock.hcl`

- [ ] **Step 1: 執行 terraform init**

```bash
terraform -chdir=terraform/labs/32-xray-lambda init
```

Expected（節錄）：
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/archive versions matching "~> 2.0"...

Terraform has been successfully initialized!
```

- [ ] **Step 2: 執行 terraform fmt**

```bash
terraform -chdir=terraform/labs/32-xray-lambda fmt
```

Expected: 無輸出或列出已修正的檔案。

- [ ] **Step 3: 提交 lock file**

```bash
git add terraform/labs/32-xray-lambda/.terraform.lock.hcl
git commit -m "chore(labs): add lab 32 terraform lock file"
```

---

## Task 7：更新 roadmap-v2.md

**Files:**
- Modify: `terraform/docs/roadmap-v2.md`

- [ ] **Step 1: 找到 lab 32 的行**

在 `terraform/docs/roadmap-v2.md` Phase 1-C 表格找到：

```markdown
| 32 | `32-xray-lambda` | X-Ray + Lambda + API Gateway 分散式追蹤 | $0 | DVA |
```

- [ ] **Step 2: 更新為 scaffolded 標記**

```markdown
| 32 🚧 | `32-xray-lambda` | X-Ray + Lambda + API Gateway 分散式追蹤 | $0 | DVA |
```

- [ ] **Step 3: Commit**

```bash
git add terraform/docs/roadmap-v2.md
git commit -m "docs(roadmap): mark lab 32 as scaffolded"
```

---

## 自我審查清單

完成所有 Task 後確認：

- [ ] `terraform/labs/32-xray-lambda/` 包含全部 9 個檔案 + lock file
- [ ] `main.tf` 的 7 個 resource blocks 均為空 body（只有 `# TODO`）
- [ ] `src/handler.py` 存在且使用標準函式庫（無外部依賴）
- [ ] `outputs.tf` 中 `api_endpoint` 引用 `aws_api_gateway_stage.dev.invoke_url`
- [ ] `.gitignore` 包含 `src/*.zip`
- [ ] `terraform fmt -check` 無報錯
