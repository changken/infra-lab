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
  --output json | python3 -c "
import json, sys
docs = json.load(sys.stdin)
for doc_str in docs:
    doc = json.loads(doc_str)
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
| `curl` 回傳正確但 `get-trace-summaries` 無資料 | X-Ray 有延遲，等待 15-30 秒；或 `--start-time` 時間範圍不對 |
| `api_endpoint` output 是空的 | `aws_api_gateway_stage.dev.invoke_url` 依賴 stage 建立，確認 apply 完成 |
| API GW apply 後 curl 仍 404 | `aws_api_gateway_deployment` 缺少 `triggers`，執行 `terraform taint aws_api_gateway_deployment.main` 強制重建 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
