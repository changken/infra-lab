# Lab 24: SNS + SQS Fan-out Pattern（可靠廣播）

> 用 SNS → 多個 SQS 實作 Fan-out，讓一筆訂單事件同時觸發庫存服務和通知服務，且兩者互不影響。

**費用等級**：🟢 安全（< $0.01，SNS / SQS 前 100 萬筆免費）

---

## 學習目標

- 理解 Fan-out 模式：一個 SNS Topic 廣播到多個 SQS Queue
- 理解「可靠廣播」：SNS 直接 → Lambda vs SNS → SQS → Lambda 的差異
- 每個 SQS Queue 有獨立的 DLQ，消費者失敗互不影響
- 解析 SNS → SQS 時的訊息包裝結構（SNS envelope）

---

## 架構

```
你（aws cli）
    │
    │ aws sns publish
    ▼
┌─────────────────────┐
│   SNS Topic         │  orders
│   (一次發布)         │
└──────────┬──────────┘
           │ Fan-out（同一份訊息複製兩份）
     ┌─────┴──────┐
     ▼            ▼
┌─────────────┐  ┌──────────────────┐
│ Inventory   │  │ Notification     │
│ SQS Queue   │  │ SQS Queue        │
│    ↓ DLQ    │  │    ↓ DLQ         │
└──────┬──────┘  └────────┬─────────┘
       │ ESM              │ ESM
       ▼                  ▼
┌─────────────┐  ┌──────────────────┐
│  Lambda     │  │  Lambda          │
│  (庫存扣除) │  │  (寄送確認信)    │
└─────────────┘  └──────────────────┘
```

### Fan-out vs 直接推送的比較

| | SNS → Lambda（直接推送）| SNS → SQS → Lambda（Fan-out）|
|--|---|---|
| 消費者掛掉時 | SNS 最多重試 3 次，之後訊息遺失 | 訊息保留在 SQS，等消費者恢復 |
| 失敗可見性 | 難以追蹤哪些訊息遺失 | DLQ 保留失敗訊息，方便 debug |
| 消費者獨立性 | 共用失敗邏輯 | 各有獨立 DLQ，互不影響 |
| 適合場景 | 簡單通知、可接受少量遺失 | 金融、訂單、需要可靠性的場景 |

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_sns_topic.orders` + 2x DLQ | 為什麼每個 Queue 有獨立 DLQ |
| 2 | `aws_sqs_queue.inventory` + `aws_sqs_queue_policy.inventory` | SNS → SQS 必備 Queue Policy |
| 3 | `aws_sqs_queue.notification` + `aws_sqs_queue_policy.notification` | 同上，結構完全相同 |
| 4 | `aws_sns_topic_subscription.inventory` + `.notification` | 兩個訂閱指向同一個 Topic |
| 5 | 2x Lambda + 2x Event Source Mapping | Pull 模型，消費者各自獨立 |

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

### 1. 發布訂單事件

```bash
TOPIC_ARN=$(terraform output -raw topic_arn)

aws sns publish \
  --topic-arn "$TOPIC_ARN" \
  --subject "order.created" \
  --message '{
    "order_id": "ORD-2024-001",
    "customer_email": "customer@example.com",
    "total": 299.99,
    "items": [
      {"sku": "BOOK-001", "qty": 2},
      {"sku": "PEN-005", "qty": 5}
    ]
  }'
```

### 2. 確認兩個 Lambda 都被觸發

```bash
# 庫存服務 log
aws logs tail "/aws/lambda/fanout-lab-inventory-worker" --follow

# 通知服務 log（開新 terminal）
aws logs tail "/aws/lambda/fanout-lab-notification-worker" --follow
```

預期庫存 log：
```
[庫存] 處理訂單 ORD-2024-001，扣除 2 個品項
  扣庫存: BOOK-001 x 2
  扣庫存: PEN-005 x 5
```

預期通知 log：
```
[通知] 訂單 ORD-2024-001 成立，寄送確認信給 customer@example.com
  金額: $299.99
```

### 3. 確認兩個 Queue 已清空

```bash
INV_Q=$(terraform output -raw inventory_queue_url)
NOT_Q=$(terraform output -raw notification_queue_url)

aws sqs get-queue-attributes --queue-url "$INV_Q" \
  --attribute-names ApproximateNumberOfMessages

aws sqs get-queue-attributes --queue-url "$NOT_Q" \
  --attribute-names ApproximateNumberOfMessages
```

### 4. 模擬其中一個服務失敗（觀察 DLQ 行為）

在 `src/inventory_worker.py` 的 handler 加入 `raise Exception("庫存服務掛了")`，重新 `terraform apply`，再發布訂單事件。

```bash
INV_DLQ=$(terraform output -raw inventory_dlq_url)

# 等待約 1-2 分鐘（重試 3 次後）
aws sqs get-queue-attributes --queue-url "$INV_DLQ" \
  --attribute-names ApproximateNumberOfMessages
```

**關鍵觀察**：庫存 DLQ 有訊息，但通知服務 Lambda 仍然正常執行 — 兩個消費者完全獨立。

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| SNS 前 100 萬筆 publish | 免費 |
| SQS 前 100 萬筆 request（4 個 Queue）| 免費 |
| Lambda 前 100 萬次呼叫 | 免費 |
| **合計** | **< $0.01** |

---

## 核心概念釐清

### SNS → SQS 的訊息包裝（SNS Envelope）

當 SNS 發布訊息到 SQS 時，SQS 收到的 `body` 不是你原始的 Message，而是 SNS 包了一層：

```json
{
  "Type": "Notification",
  "MessageId": "uuid",
  "TopicArn": "arn:aws:sns:...",
  "Subject": "order.created",
  "Message": "{\"order_id\": \"ORD-001\", ...}",  ← 原始訊息（字串）
  "Timestamp": "2026-05-24T...",
  "MessageAttributes": {}
}
```

消費者要先 `json.loads(body)` 拿到 envelope，再 `json.loads(envelope["Message"])` 拿到原始訊息。

SNS → Lambda 直接推送時，event 結構又不一樣（`Records[].Sns.Message`）。
**不同整合方式，訊息結構不同** — 這是實作時最常踩的坑。

### 為什麼每個下游有獨立的 DLQ？

如果兩個 Queue 共用一個 DLQ：
- 庫存失敗的訊息和通知失敗的訊息混在一起
- 無法分辨是哪個服務的問題
- 重新處理 DLQ 訊息時可能會重複觸發錯誤的服務

獨立 DLQ = 獨立的失敗域（Failure Domain）。

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| 兩個 Queue 都沒收到訊息 | `aws_sqs_queue_policy` 沒設定，或 `endpoint` 填了 URL 而非 ARN |
| 只有一個 Queue 收到訊息 | 某個 `aws_sns_topic_subscription` 的 `endpoint` 填錯 |
| Lambda 解析訊息報錯 | 忘記解開 SNS envelope，直接 parse body 而非 `body["Message"]` |
| DLQ 沒有收到失敗訊息 | `redrive_policy` 的 `deadLetterTargetArn` 填錯（DLQ 的 ARN，不是 URL）|
