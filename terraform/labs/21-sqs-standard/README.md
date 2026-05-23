# Lab 21: SQS Standard Queue + Dead Letter Queue

> 建立 SQS 工作佇列，透過 Event Source Mapping 讓 Lambda 自動消費訊息，失敗訊息自動移入 DLQ。

**費用等級**：🟢 安全（< $0.01，SQS 前 100 萬筆免費）

---

## 學習目標

- 理解 SQS Standard Queue 的核心參數：Visibility Timeout、Long Polling、Message Retention
- 設定 Dead Letter Queue（DLQ）與 redrive policy
- 用 Event Source Mapping 讓 Lambda 自動拉取 SQS 訊息（不需要 Lambda Permission）
- 觀察 batch_size 與失敗重試的行為

---

## 架構

```
你（aws cli）
    │
    │ aws sqs send-message
    ▼
┌─────────────────────────────┐
│  SQS Main Queue             │
│  visibility_timeout = 30s   │◄─── 失敗 3 次後
│  long_polling = 20s         │          │
└──────────┬──────────────────┘          │
           │ Event Source Mapping        ▼
           │ (Lambda 主動輪詢)    ┌──────────────┐
           ▼                     │  DLQ         │
    ┌──────────────┐             │  (14 天保留) │
    │  Lambda      │             └──────────────┘
    │  Consumer    │
    │  batch = 10  │
    └──────┬───────┘
           │
           ▼
    CloudWatch Logs
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_sqs_queue.dlq` | 簡單佇列，14 天保留 |
| 2 | `aws_sqs_queue.main` | 設定 visibility timeout、long polling、redrive policy |
| 3 | `aws_iam_role_policy.lambda_sqs` | 最小權限：ReceiveMessage + DeleteMessage + GetQueueAttributes |
| 4 | `aws_lambda_function.consumer` | timeout 要 < visibility_timeout |
| 5 | `aws_lambda_event_source_mapping.sqs` | batch_size = 10，思考冪等性 |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## 驗證

### 1. 發送測試訊息

```bash
QUEUE_URL=$(terraform output -raw queue_url)

# 發送單筆
aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body '{"order_id": "001", "item": "book", "qty": 2}'

# 發送多筆
for i in 1 2 3 4 5; do
  aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "{\"order_id\": \"00$i\", \"item\": \"item-$i\"}"
done
```

### 2. 確認 Lambda 有處理

```bash
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# 查看最近 log
aws logs tail "/aws/lambda/$FUNCTION_NAME" --follow
```

預期看到類似：
```
收到 5 筆訊息
[abc123] 處理訊息: {'order_id': '001', 'item': 'book', 'qty': 2}
...
```

### 3. 確認 Queue 已清空

```bash
# 正常處理後 queue 應該是空的
aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages
```

### 4. 觀察 DLQ（模擬失敗）

在 `src/consumer.py` 的 handler 中加入 `raise Exception("模擬失敗")`，重新 apply，發訊息後等待：

```bash
DLQ_URL=$(terraform output -raw dlq_url)

# 觀察 DLQ 是否有訊息進來（重試 3 次後約 1-2 分鐘）
aws sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages
```

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| SQS 前 100 萬筆 request | 免費 |
| Lambda 前 100 萬次呼叫 | 免費 |
| CloudWatch Logs | < $0.01 |
| **合計** | **< $0.01** |

---

## 核心概念釐清

### Visibility Timeout vs Message Retention

| 參數 | 作用 | 錯誤設定的後果 |
|------|------|-------------|
| `visibility_timeout_seconds` | 消費者拿走訊息後，其他人看不到它的時間 | 太短 → Lambda 還沒處理完，訊息重新出現，造成重複處理 |
| `message_retention_seconds` | 訊息在 Queue 裡最多存活多久 | 太短 → 消費者來不及處理就消失了 |

**原則**：`visibility_timeout >= Lambda timeout + buffer`

### 為什麼不需要 Lambda Permission？

S3 觸發 Lambda 是 S3「推送」事件給 Lambda，所以需要 `aws_lambda_permission` 授權 S3 呼叫 Lambda。

SQS + Event Source Mapping 是 Lambda「主動輪詢」SQS，所以只需要給 Lambda 讀取 SQS 的 IAM 權限，不需要 Permission resource。

### 冪等性（Idempotency）

batch_size = 10 時，若第 5 筆訊息處理失敗，整批 10 筆都會重試。
設計消費者時要確保「同一筆訊息被處理兩次，結果也相同」。

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Event Source Mapping 狀態是 `Disabled` | Lambda IAM Policy 缺少 `sqs:GetQueueAttributes` |
| 訊息一直在 Queue 裡不被消費 | Event Source Mapping `enabled = false` 或 Lambda timeout 設太短 |
| DLQ 沒有收到失敗訊息 | `redrive_policy` 沒設，或 `maxReceiveCount` 設太大 |
| Lambda 一直重複收到同一筆訊息 | `visibility_timeout_seconds < Lambda timeout`，訊息提前重新出現 |
