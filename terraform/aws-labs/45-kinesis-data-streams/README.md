# Lab 45：Kinesis Data Streams 即時資料管道

> **場景**：用 API Gateway + Lambda 把用戶事件寫入 Kinesis Data Stream，另一個 Lambda 消費 Stream 並把 event_type 計數聚合到 DynamoDB，同時用 CloudWatch Alarm 監控消費者延遲。  
> **費用等級**：🟡 注意（Kinesis Shard 約 $0.015/hr；練完請立即 destroy）

---

## 學習目標

完成本 lab 後，你能夠：

- 建立 **Kinesis Data Stream**（Provisioned 模式），理解 Shard、Partition Key、Sequence Number 的關係
- 用 **Producer Lambda** 透過 `PutRecords` API 批次寫入事件到 Stream
- 配置 **Event Source Mapping**（ESM）讓 Lambda 以「拉取（pull）」模式消費 Kinesis
- 理解 `starting_position`（LATEST vs TRIM_HORIZON）與 `bisect_batch_on_function_error`（毒藥訊息隔離）的用途
- 用 DynamoDB `UpdateItem + ADD` 實作原子計數聚合（無鎖競態條件）
- 透過 `GetRecords.IteratorAgeMilliseconds` CloudWatch 指標監控消費者落後狀況

---

## 架構

```
POST /events
     │
     ▼
API Gateway (HTTP API)
     │
     ▼
Producer Lambda ──── kinesis:PutRecords ───► Kinesis Data Stream
                                                    │ (1 shard)
                                         Event Source Mapping
                                           (batch_size=100)
                                                    │
                                                    ▼
                                          Consumer Lambda
                                                    │
                                          dynamodb:UpdateItem
                                                    │
                                                    ▼
                                          DynamoDB Table
                                      (event_type → count)

CloudWatch Alarm
  GetRecords.IteratorAgeMilliseconds
  ↑ > 60,000 ms → SNS Topic → Email（選填）
```

---

## 核心概念

### Kinesis Shard 模型

```
Producer PutRecords
  └─ PartitionKey (user_id) → hash → Shard 0
                                         │
                                    Shard Iterator
                                         │ (Consumer 輪詢)
                                    GetRecords（最多 2 MB/s）
                                         │
                                    Consumer Lambda
```

| 指標 | 說明 |
|------|------|
| Shard 寫入上限 | 1 MB/s 或 1000 records/s |
| Shard 讀取上限 | 2 MB/s |
| 預設保留期 | 24 小時（最長 365 天）|
| `IteratorAgeMilliseconds = 0` | 消費者即時跟上 |
| `IteratorAgeMilliseconds >> 0` | 消費者落後，需擴充 shard 或 Lambda |

---

## 目錄結構

```
45-kinesis-data-streams/
├── src/
│   ├── producer.py    ← 已提供（PutRecords 批次寫入）
│   └── consumer.py    ← 已提供（base64 decode + DynamoDB ADD）
├── terraform.tf
├── variables.tf
├── locals.tf
├── main.tf            ← TODO 1-5
├── outputs.tf
├── terraform.tfvars.example
└── .gitignore
```

---

## 你要做的事

| TODO | 位置 | 說明 |
|------|------|------|
| 1 | `main.tf` | `aws_kinesis_stream.events`（shard_count=1, retention_period=24）|
| 2 | `main.tf` | `aws_dynamodb_table.aggregation`（PAY_PER_REQUEST, hash_key="event_type"）|
| 3 | `main.tf` | Producer IAM Role + AWSLambdaBasicExecutionRole + kinesis:PutRecord/PutRecords Inline Policy + archive_file + Lambda + API GW HTTP API + Permission |
| 4 | `main.tf` | Consumer IAM Role + AWSLambdaKinesisExecutionRole + dynamodb:UpdateItem Inline Policy + archive_file + Lambda + **Event Source Mapping** |
| 5 | `main.tf` | SNS Topic + 條件式 email 訂閱 + CloudWatch Alarm（IteratorAgeMilliseconds > 60000）|

---

## 指令流程

```bash
# 複製 tfvars
cp terraform.tfvars.example terraform.tfvars

# （選填）填入 email 以接收延遲告警
# vim terraform.tfvars

# 初始化
terraform init

# 格式化 + 驗證
terraform fmt
terraform validate

# 預覽
terraform plan

# 部署
terraform apply -auto-approve

# 查看輸出（含驗證指令）
terraform output
```

---

## 驗證方式

### 步驟 1：確認資源已建立

```bash
terraform state list
# 預期看到：
# aws_kinesis_stream.events
# aws_dynamodb_table.aggregation
# aws_iam_role.producer
# aws_iam_role.consumer
# aws_lambda_function.producer
# aws_lambda_function.consumer
# aws_lambda_event_source_mapping.kinesis
# aws_apigatewayv2_api.producer
# aws_sns_topic.alarms
# aws_cloudwatch_metric_alarm.iterator_age
```

### 步驟 2：發送隨機事件批次

```bash
API_URL=$(terraform output -raw api_endpoint)

# 發送 50 筆隨機事件（page_view / button_click / purchase / search / logout）
curl -s -X POST ${API_URL}/events \
  -H 'Content-Type: application/json' \
  -d '{"count": 50}' | jq .

# 預期輸出：
# { "sent": 50, "failed": 0 }
```

### 步驟 3：發送單筆自訂事件

```bash
curl -s -X POST ${API_URL}/events \
  -H 'Content-Type: application/json' \
  -d '{"event_type": "purchase", "user_id": "user-99", "amount": 199.9}' | jq .
```

### 步驟 4：等候 Consumer 處理後查看 DynamoDB 聚合結果

```bash
# Consumer Lambda 是 Event Source Mapping 輪詢，通常 < 1 秒到幾秒內觸發
sleep 5

TABLE=$(terraform output -raw dynamodb_table)
aws dynamodb scan \
  --table-name $TABLE \
  --query 'Items[*].{type: event_type.S, count: count.N, updated: last_updated.S}' \
  --output table

# 預期看到各 event_type 的累計計數：
# -----------------------------------------------
# | type         | count | updated               |
# |--------------+-------+-----------------------|
# | page_view    | 18    | 2026-01-01T00:00:00+00:00 |
# | purchase     | 8     | ...                   |
# | button_click | 12    | ...                   |
# -----------------------------------------------
```

### 步驟 5：查看 Kinesis Stream 詳細資訊

```bash
STREAM=$(terraform output -raw stream_name)

# Stream 基本資訊
aws kinesis describe-stream-summary --stream-name $STREAM

# 查看 shard 清單
aws kinesis list-shards --stream-name $STREAM --output table
```

### 步驟 6：查看消費者延遲指標

```bash
STREAM=$(terraform output -raw stream_name)

aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name GetRecords.IteratorAgeMilliseconds \
  --dimensions Name=StreamName,Value=$STREAM \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-5M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --output table

# IteratorAgeMilliseconds ≈ 0 → 消費者即時跟上 ✅
```

### 步驟 7：壓力測試（觀察 IteratorAge 上升）

```bash
API_URL=$(terraform output -raw api_endpoint)

# 快速發送 500 筆事件 × 5 次
for i in $(seq 1 5); do
  curl -s -X POST ${API_URL}/events \
    -H 'Content-Type: application/json' \
    -d '{"count": 500}' > /dev/null
  echo "Batch $i sent"
done

# 觀察 Consumer Lambda 的 CloudWatch Logs
FUNC=$(terraform output -raw consumer_function_name)
aws logs tail /aws/lambda/$FUNC --follow
```

### 步驟 8：查看 Consumer Lambda Log（驗證 base64 decode）

```bash
FUNC=$(terraform output -raw consumer_function_name)
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNC \
  --filter-pattern "Aggregated" \
  --limit 5 \
  --query 'events[].message' \
  --output text

# 預期看到：
# Aggregated: {'page_view': 12, 'purchase': 3, ...}
```

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 計費模式 | 預估費用 |
|------|---------|---------|
| Kinesis Data Stream（1 shard）| $0.015/hr | **主要費用**；2 小時練習 ≈ $0.03 |
| Lambda（Producer + Consumer）| 前 1M 次/月免費 | $0.00 |
| API Gateway（HTTP API）| 前 1M 次/月免費 | $0.00 |
| DynamoDB | PAY_PER_REQUEST，練習量很小 | < $0.01 |
| CloudWatch Alarm | 前 10 個 Alarm 免費 | $0.00 |
| SNS | 前 1M 次免費 | $0.00 |
| **合計** | | **≈ $0.03（2 小時）** |

> ⚠️ **提醒**：Kinesis Shard 按時計費（即使沒有資料）。練習完請立即執行 `terraform destroy`！

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼用 Kinesis 而不是 SQS？

**決策**：使用 Kinesis Data Streams，而不是 Lab 21 的 SQS。

**理由**：

| | SQS（Lab 21）| Kinesis Data Streams（Lab 45）|
|-|-------------|-------------------------------|
| 消費模式 | Push（SQS 推送到 Lambda）| Pull（Lambda Service 輪詢 Shard）|
| 訊息順序 | FIFO Queue 才保序 | 同一 Partition Key 的記錄在 Shard 內保序 |
| 多消費者 | 一筆訊息只能被一個消費者取走 | 多個消費者可各自獨立讀取（Enhanced Fan-Out）|
| 重播能力 | 訊息消費後即刪除 | 保留 24 小時～365 天，可重播 |
| 適合場景 | 任務佇列、解耦微服務 | 即時日誌流、事件溯源、IoT 資料流 |
| 費用 | 幾乎免費（按請求計費）| **Shard 按時計費**（$0.015/hr/shard）|

**結論**：高吞吐量且需要重播或多消費者的即時流，選 Kinesis；簡單非同步解耦工作佇列，選 SQS。

---

### ADR-2：`bisect_batch_on_function_error = true` 有什麼作用？

**決策**：Event Source Mapping 啟用 `bisect_batch_on_function_error`。

**問題場景**：
```
batch = [record-1, record-2, 💀 poison-pill, record-4, ..., record-100]
```
若 `poison-pill` 導致 Consumer Lambda 拋出例外，整個 batch 都會重試，進入無窮迴圈。

**解法**：
```
bisect_batch_on_function_error = true
→ Lambda 失敗時，把 batch 切成兩半分別重試
→ 逐漸縮小範圍，最終隔離到只含毒藥訊息的 batch
→ 超過 retry 次數後，該 batch 進入 Kinesis 過期（或配合 destination on failure）
```

**取捨**：啟用後單次失敗會產生 log(N) 次額外呼叫，但能防止一筆壞資料阻塞整個 Stream。

---

### ADR-3：為什麼 Consumer 不需要 `aws_lambda_permission`？

**決策**：Event Source Mapping 模式不需要設定 `aws_lambda_permission`。

**原因**：
```
Push 模式（API GW / S3 / SNS → Lambda）
  → 外部服務「呼叫」Lambda → 需要 aws_lambda_permission 授權來源

Pull 模式（Kinesis / SQS / DynamoDB Streams → Lambda）
  → Lambda Service 代表 Lambda 「拉取」資料 → IAM Role 本身就是憑據
  → 不需要 aws_lambda_permission
```

**記憶口訣**：誰來呼叫 Lambda？  
- 外部服務呼叫 → 加 `aws_lambda_permission`  
- Lambda 自己去拉 → 只需 IAM Role 有讀取 Stream 的權限

---

## 常見問題

| 症狀 | 原因 | 解法 |
|------|------|------|
| Consumer Lambda 沒有觸發 | Event Source Mapping 狀態不是 Enabled | `aws lambda list-event-source-mappings --function-name <func>` 確認 State |
| `ResourceNotFoundException` in Consumer | TABLE_NAME 環境變數錯誤 | 確認 Lambda env var `TABLE_NAME` 與 DynamoDB table name 一致 |
| `KMSDisabledException` | Stream 加密設定問題 | 本 lab 不使用 KMS，確認 `encryption_type` 未設定 |
| DynamoDB `count` 沒有增加 | Consumer Lambda 拋出例外 | 查看 `/aws/lambda/<consumer-func>` CloudWatch Logs |
| `PutRecords` 部分失敗（`failed > 0`）| 單一 Shard 吞吐量超限 | 降低 count 或等待 Shard 恢復；生產環境考慮增加 shard 數 |
| `IteratorAgeMilliseconds` 持續上升 | Consumer 處理速度跟不上 Producer | 增加 `batch_size` 或增加 Kinesis shard 數 |
| `InvalidArgumentException: Cannot create event source mapping` | Kinesis Stream 尚未 ACTIVE | 等候 Stream 狀態變為 `ACTIVE` 後再 apply |

---

## 延伸練習

完成基本 5 個 TODO 後，可嘗試：

1. **增加 Shard**：把 `shard_count` 從 1 改為 2，觀察 `terraform apply` 的 in-place update 行為
2. **Enhanced Fan-Out**：新增第二個 Consumer Lambda，使用 `aws_kinesis_stream_consumer`（專用吞吐量，不與其他消費者共用）
3. **延長保留期**：把 `retention_period` 改為 48 小時，再用 `TRIM_HORIZON` 重播所有歷史記錄
4. **On-Demand 模式**：把 `shard_count` 移除，改用 `stream_mode_details { stream_mode = "ON_DEMAND" }`，比較計費差異
5. **Destination on Failure**：配置 `destination_config` 把失敗的 batch 送到 SQS DLQ，避免毒藥訊息靜默消失

---

## 面試故事

> 「在 Lab 45，我建了一個 Kinesis 即時事件管道。用戶行為事件（page_view、purchase）透過 API Gateway + Producer Lambda 用 PutRecords 批次寫入 Kinesis Stream；Consumer Lambda 透過 Event Source Mapping 拉取，用 DynamoDB atomic ADD 聚合各 event_type 的計數。
>
> 跟 Lab 21 SQS 最大的差別是消費模式：SQS 是 push（SQS 推送到 Lambda），Kinesis 是 pull（Lambda Service 輪詢 shard iterator）。因為 Kinesis 保留資料，所以支援多消費者獨立讀取、支援重播——這是 SQS 做不到的。
>
> 我還設了 `bisect_batch_on_function_error = true`，面試官問這是什麼。我解釋：當 batch 裡有一筆壞資料（poison pill）讓 Lambda 失敗，如果整個 batch 無限重試會阻塞整條 stream；啟用這個選項後，Lambda 失敗時 ESM 會把 batch 對半切再分別重試，直到把壞資料隔離到最小單位為止。
>
> 監控方面，我用 `GetRecords.IteratorAgeMilliseconds` 指標——這個值代表『最舊未處理記錄距現在多久』，接近 0 表示消費者即時追上，持續上升則代表需要增加 shard 或提高 Lambda 並發。」

---

*建立於 2026-05-28*
