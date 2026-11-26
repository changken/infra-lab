# Lab 37: 電商訂單後端（事件驅動整合場景）

> API Gateway 接收訂單 → Validator Lambda 驗證並送入 SQS → Processor Lambda 非同步寫入 DynamoDB + SNS Email 通知。綜合運用 Labs 06-09、21-22 的知識，組合成可展示的完整後端場景。

**費用等級**：🟢 安全（< $0.50，全部 AWS Free Tier 範圍，練完當天 destroy）

---

## 學習目標

- 整合 API GW + Lambda + SQS + DynamoDB + SNS，理解**事件驅動架構**的完整資料流
- 實作 **SQS Dead Letter Queue（DLQ）**，隔離失敗訊息
- 掌握兩個 Lambda 各自的 **最小權限 IAM Policy**（Validator vs Processor 不同）
- 理解 **Lambda Event Source Mapping**（SQS 自動觸發 Processor 的機制）
- 能用 **面試故事** 解釋為什麼用 SQS 解耦而不是 Validator 直接呼叫 Processor

---

## 架構

```
用戶
  │ POST /orders
  │ { customer_id, items, total_amount }
  ▼
┌───────────────────────────────────────┐
│  API Gateway HTTP API                 │
│  route: POST /orders                  │
└──────────────────┬────────────────────┘
                   │ Lambda Proxy
                   ▼
┌───────────────────────────────────────┐
│  Lambda: validator                    │
│  - 驗證必要欄位                       │
│  - 產生 order_id（UUID）              │
│  - status = "PENDING"                 │
│  - 回傳 201 { order_id, status }      │
└──────────────────┬────────────────────┘
                   │ sqs:SendMessage
                   ▼
┌───────────────────────────────────────┐
│  SQS Queue: orders                    │
│  visibility_timeout = 180s            │
│  redrive → DLQ（失敗 3 次）           │
└──────────────────┬────────────────────┘
                   │ Event Source Mapping（自動觸發）
                   ▼
┌───────────────────────────────────────┐
│  Lambda: processor                    │
│  - status = "PROCESSED"               │
│  - dynamodb:PutItem                   │
│  - sns:Publish（Email 通知）          │
└──────┬───────────────────┬────────────┘
       │                   │
       ▼                   ▼
┌──────────────┐  ┌────────────────────┐
│  DynamoDB    │  │  SNS Topic         │
│  orders      │  │  → Email           │
└──────────────┘  └────────────────────┘
```

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼 Validator 不直接呼叫 Processor？

| | 直接呼叫（同步）| SQS 解耦（非同步）|
|--|--------------|-----------------|
| Processor 掛掉時 | Validator 也失敗，訂單遺失 | 訊息留在 SQS，Processor 恢復後自動重試 |
| 高峰流量 | Processor 被打爆 | SQS 緩衝，Processor 按自己的速度消費 |
| 除錯 | 難以重送失敗訂單 | DLQ 保存失敗訊息，可手動重送 |
| **結論** | 不適合生產環境 | **選擇此方案** |

### ADR-2：為什麼用 HTTP API Gateway 而不是 REST API？

| | HTTP API（v2）| REST API（v1）|
|--|-------------|--------------|
| 費用 | $1/百萬請求 | $3.5/百萬請求 |
| 設定複雜度 | 低（適合 Lambda Proxy）| 高（資源、方法、部署）|
| 功能 | JWT 授權、Lambda Proxy | 完整功能（Request Validation、Mapping）|
| **結論** | **選擇此方案**（本 lab 不需要進階功能）| 需要 Authorizer / Mapping 時選 |

### ADR-3：為什麼用 DynamoDB 而不是 RDS？

| | DynamoDB | RDS PostgreSQL |
|--|---------|----------------|
| 費用 | PAY_PER_REQUEST，零請求零費用 | 最少 $0.017/hr（閒置照計費）|
| 連線管理 | 無（HTTP API）| 需要 VPC、Connection Pool |
| Schema | 彈性（新增欄位不需 Migration）| 固定（需要 Migration）|
| **結論** | **選擇此方案**（訂單讀取模式簡單，by order_id）| 需要複雜 JOIN 或事務時選 |

---

## 你要做的事

| TODO | 資源 | 關鍵概念 |
|------|------|---------|
| 1 | `aws_dynamodb_table` | Schema-less：只需宣告 hash_key 的 attribute |
| 2 | `aws_sqs_queue` × 2 | `redrive_policy` + `visibility_timeout_seconds = 180` |
| 3 | `aws_sns_topic` + `aws_sns_topic_subscription` | apply 後立即確認訂閱信 |
| 4 | `aws_iam_role` × 2 + `aws_iam_role_policy` × 2 | Validator vs Processor 權限不同 |
| 5 | `aws_lambda_function` × 2 | `handler = "{檔名}.{函數名}"` + environment variables |
| 6 | `aws_apigatewayv2_api` + integration + route + stage + `aws_lambda_permission` | `source_arn` 格式 |
| 7 | `aws_lambda_event_source_mapping` | SQS 自動觸發 Processor 的核心資源 |

---

## 指令

```bash
# 1. 複製變數範例並填入 notification_email
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化（下載 aws + archive providers）
terraform init

# 3. 格式化（填完所有 TODO 後執行）
terraform fmt

# 4. 語法驗證
terraform validate

# 5. 預覽（確認將建立約 20 個資源）
terraform plan

# 6. 部署
terraform apply
```

> **注意**：apply 後立即查收 `notification_email` 的確認信，點擊「Confirm subscription」。

---

## 驗證

### 1. 建立訂單（測試整條流程）

```bash
API_URL=$(terraform output -raw api_endpoint)

curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-001","items":[{"sku":"ITEM-A","qty":2}],"total_amount":59.90}' \
  | jq .
```

**期望輸出**：
```json
{ "order_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "status": "PENDING" }
```

### 2. 確認訂單寫入 DynamoDB（等待約 10-20 秒）

```bash
eval "$(terraform output -raw dynamodb_scan_command)"
```

**期望輸出**：一筆 `Status = PROCESSED` 的訂單

### 3. 驗證欄位驗證（測試錯誤處理）

```bash
# 缺少必要欄位 → 應回 400
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"cust-001"}' \
  | jq .
```

**期望輸出**：`{"error": "Missing required fields: ['items', 'total_amount']"}`

### 4. 批量建立訂單（測試 SQS batch_size）

```bash
for i in {1..5}; do
  curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"customer_id\":\"cust-00$i\",\"items\":[{\"sku\":\"ITEM-$i\",\"qty\":1}],\"total_amount\":$((i*10)).00}" \
    | jq -r .order_id
done
```

### 5. 監控 DLQ（確認沒有失敗訊息）

```bash
eval "$(terraform output -raw dlq_message_count_command)"
```

**期望輸出**：`ApproximateNumberOfMessages = 0`（若非 0，表示 Processor 有錯誤）

---

## 可觀測性設計

| 問題 | 如何知道？| 指令 |
|------|---------|------|
| Validator 出錯 | CloudWatch Logs `/aws/lambda/order-backend-validator` | `aws logs tail /aws/lambda/order-backend-validator --follow` |
| Processor 出錯 | CloudWatch Logs `/aws/lambda/order-backend-processor` | `aws logs tail /aws/lambda/order-backend-processor --follow` |
| 訂單處理失敗 | DLQ 有訊息 | `terraform output dlq_message_count_command` |
| 系統整體健康 | DynamoDB `SuccessfulRequestLatency` metric | AWS Console → DynamoDB → Monitor |

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`。

---

## 成本估算

| 資源 | Free Tier | 超出費用 |
|------|-----------|---------|
| Lambda（兩個函數）| 1M 請求/月免費 | $0.20/百萬請求 |
| API Gateway HTTP API | 1M 請求/月免費（12 個月）| $1.00/百萬請求 |
| SQS（2 個 queue）| 1M 請求/月免費 | $0.40/百萬請求 |
| DynamoDB | 25 WCU 免費 | PAY_PER_REQUEST |
| SNS | 1000 email/月免費 | $2/10萬 email |
| **合計（lab 期間）** | **~$0（全在 Free Tier）** | |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 後 POST /orders 回 403 | `aws_lambda_permission.apigw_validator` 沒設，或 `source_arn` 格式錯誤 |
| POST /orders 回 502 Bad Gateway | Validator Lambda 有錯誤，查 CloudWatch Logs |
| 訂單建立後 DynamoDB 沒有資料 | Event Source Mapping 沒建（TODO 7），或 Processor IAM 缺少 SQS 權限 |
| DLQ 有訊息 | Processor 執行失敗，查 `/aws/lambda/order-backend-processor` 的 CloudWatch Logs |
| SNS Email 沒收到 | 未點擊確認信；確認 `notification_email` 輸入正確 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完後再執行 |
| Event Source Mapping 建立失敗 | Processor IAM Role 缺少 `sqs:ReceiveMessage` / `sqs:GetQueueAttributes` |
| Lambda timeout 後訊息被重新可見 | SQS `visibility_timeout_seconds` 需設為 Lambda timeout × 6（= 180s）|

---

## 面試故事

> 「我設計過一個訂單系統，前端打 API Gateway，Validator Lambda 做輸入驗證後把訂單丟進 SQS。這樣做有幾個好處：第一，即使後端 Processor 暫時掛了，訂單還是安全地躺在 SQS 裡，服務恢復後自動重試；第二，高峰時 SQS 幫我緩衝流量，Processor 按照自己的速度消費；第三，失敗的訂單會進 DLQ，我可以事後排查原因再手動重送，不會有訂單遺失。整個系統的基礎設施用 Terraform 管理，一個 `terraform apply` 就能把環境建起來。」
