# Lab 22: SNS Topic + 三種訂閱類型

> 建立 SNS Topic，同時設定 Email、SQS、Lambda 三種訂閱者，並用 Filter Policy 讓 SQS 只接收高優先訊息。

**費用等級**：🟢 安全（< $0.01，SNS 前 100 萬筆免費）

---

## 學習目標

- 理解 SNS 推送（Push）模型與 SQS 拉取（Pull）模型的根本差異
- 設定三種訂閱 protocol：`email`、`sqs`、`lambda`
- 理解 SNS → SQS 需要 **SQS Queue Policy**、SNS → Lambda 需要 **Lambda Permission**
- 用 Filter Policy 讓特定訂閱者只接收符合條件的訊息

---

## 架構

```
你（aws cli）
    │
    │ aws sns publish --message-attributes priority=high
    ▼
┌─────────────────────────────────────┐
│  SNS Topic                          │
│  (發布後立即推送給所有訂閱者)        │
└─────┬──────────────┬────────────────┘
      │              │              │
      ▼              ▼              ▼
  Email 訂閱      SQS 訂閱       Lambda 訂閱
  (所有訊息)    (僅 priority=high)  (所有訊息)
      │              │              │
      ▼              ▼              ▼
   信箱收信     SQS Queue     CloudWatch Logs
```

**關鍵差異（和 Lab 21 相比）**：

| | Lab 21 SQS + Lambda | Lab 22 SNS → Lambda |
|--|---|---|
| 觸發模型 | Pull（Lambda 主動輪詢 SQS）| Push（SNS 推送給 Lambda）|
| 需要 Lambda Permission? | 否 | **是** |
| 需要 Queue Policy? | 否 | **是**（SNS → SQS）|

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_sns_topic.main` | 最簡單的資源 |
| 2 | `aws_sns_topic_subscription.email` | apply 後要去信箱點確認 |
| 3 | `aws_sqs_queue.subscriber` + `aws_sqs_queue_policy.subscriber` | Queue Policy 是必要的，不是可選的 |
| 4 | `aws_sns_topic_subscription.sqs` | 加上 filter_policy，只收 priority=high |
| 5 | `aws_lambda_function.handler` + `aws_lambda_permission.sns` + `aws_sns_topic_subscription.lambda` | Lambda Permission 不能省 |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars
# 填入你的 email

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

**apply 後**：去信箱找一封主旨為 `AWS Notification - Subscription Confirmation` 的信並點擊確認連結。

---

## 驗證

### 1. 發布一般訊息（無 priority attribute）

```bash
TOPIC_ARN=$(terraform output -raw topic_arn)

aws sns publish \
  --topic-arn "$TOPIC_ARN" \
  --subject "一般通知" \
  --message '{"event": "user_signup", "user_id": "u001"}'
```

預期結果：
- Email：收到（若已確認訂閱）
- SQS：**不會收到**（無 priority 屬性，被 Filter Policy 過濾掉）
- Lambda：收到（CloudWatch 有 log）

### 2. 發布高優先訊息（priority=high）

```bash
aws sns publish \
  --topic-arn "$TOPIC_ARN" \
  --subject "高優先警告" \
  --message '{"event": "payment_failed", "user_id": "u002"}' \
  --message-attributes '{"priority": {"DataType": "String", "StringValue": "high"}}'
```

預期結果：
- Email：收到
- SQS：**收到**（符合 Filter Policy）
- Lambda：收到

### 3. 確認 SQS 收到訊息

```bash
QUEUE_URL=$(terraform output -raw sqs_queue_url)

aws sqs receive-message \
  --queue-url "$QUEUE_URL" \
  --max-number-of-messages 10
```

### 4. 確認 Lambda log

```bash
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

aws logs tail "/aws/lambda/$FUNCTION_NAME" --follow
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
| SNS 前 100 萬筆 publish | 免費 |
| SNS Email 通知前 1,000 封 | 免費 |
| Lambda 前 100 萬次呼叫 | 免費 |
| SQS 前 100 萬筆 request | 免費 |
| **合計** | **< $0.01** |

---

## 核心概念釐清

### Push vs Pull

| | SNS（Push）| SQS（Pull）|
|--|---|---|
| 訊息流向 | SNS 主動推送給訂閱者 | 消費者主動去 SQS 拉取 |
| 失敗處理 | 訂閱者掛掉 → 訊息遺失（需搭配 SQS 做緩衝）| 訊息保留在 Queue，等消費者回來 |
| 適合場景 | 廣播給多個訂閱者 | 工作佇列、確保訊息被處理 |

### 為什麼 SNS → SQS 需要 Queue Policy？

SNS 和 SQS 是不同的 AWS 服務，跨服務寫入需要明確授權。
SQS Queue Policy 是「資源型 Policy」（Resource-based Policy），定義誰可以對這個 Queue 做什麼。
沒有它，SNS 會因為沒有權限而無法寫入，apply 不會報錯但訊息就是不會進 Queue。

### Filter Policy 的運作

Filter Policy 在 SNS 層面過濾，符合條件才投遞給該訂閱者。
不符合的訊息直接在 SNS 丟棄，訂閱者完全不知道有這筆訊息。
和 SQS DLQ（訊息到了但處理失敗）是完全不同的概念。

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Email 訂閱一直是 PendingConfirmation | 沒有點確認信連結（Terraform 不會等待確認）|
| SQS 沒收到任何訊息 | 忘記設定 `aws_sqs_queue_policy` |
| SQS 收不到 priority=high 的訊息 | `filter_policy_scope` 設定錯誤，或發布時 `--message-attributes` 格式有誤 |
| Lambda 沒被觸發 | 忘記設定 `aws_lambda_permission`，SNS 沒有呼叫 Lambda 的權限 |
| Lambda 被觸發但 event 結構看不懂 | SNS 包了一層 `Records[].Sns`，不像 SQS 直接在 `Records[].body` |
