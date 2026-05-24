# Lab 23: EventBridge Rules（Schedule + Event Pattern + Custom Bus）

> 用 EventBridge 建立排程觸發和事件路由，理解它與 SNS/SQS 的本質差異。

**費用等級**：🟢 安全（< $0.01，EventBridge 前 100 萬筆自訂事件免費）

---

## 學習目標

- 理解 EventBridge 和 SNS/SQS 的差異：事件路由 vs 訊息傳遞
- 用 `rate()` / `cron()` 建立排程觸發（取代 cron job）
- 建立 Custom Event Bus 隔離自訂事件流
- 用 Event Pattern 過濾特定 source + detail-type + detail 的事件
- 理解 Terraform 資源名稱 `aws_cloudwatch_event_xxx` 的歷史背景

---

## 架構

```
┌─────────────────────────────────────────────────────────┐
│ 排程觸發（Default Bus 特殊機制）                         │
│                                                         │
│  EventBridge Schedule Rule                             │
│  rate(2 minutes)  ──────────────►  Lambda (scheduler) │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 自訂事件流（Custom Event Bus）                           │
│                                                         │
│  aws events put-events                                 │
│       │                                                │
│       ▼                                                │
│  Custom Event Bus                                      │
│       │                                                │
│  Pattern Rule                                          │
│  source=myapp.orders                                   │
│  detail-type=order.created    ──────►  Lambda         │
│  detail.status=pending|confirmed      (processor)     │
└─────────────────────────────────────────────────────────┘
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_lambda_function.scheduler` + `aws_lambda_permission.scheduler` | principal = `events.amazonaws.com` |
| 2 | `aws_cloudwatch_event_rule.schedule` + `aws_cloudwatch_event_target.schedule_lambda` | `schedule_expression` 格式 |
| 3 | `aws_cloudwatch_event_bus.custom` | Default vs Custom Bus 的差異 |
| 4 | `aws_lambda_function.processor` + `aws_lambda_permission.processor` | source_arn 指向 Pattern Rule |
| 5 | `aws_cloudwatch_event_rule.pattern` + `aws_cloudwatch_event_target.pattern_lambda` | `event_pattern` 的 AND/OR 邏輯 |

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

### 1. 確認排程 Lambda 自動被觸發

apply 後等 2 分鐘，排程 Rule 會自動觸發 scheduler Lambda：

```bash
SCHEDULER=$(terraform output -raw scheduler_function_name)

aws logs tail "/aws/lambda/$SCHEDULER" --follow
```

預期看到：
```
排程觸發時間: 2026-05-23T10:00:00+00:00
執行定時工作中...
```

### 2. 發布符合 Pattern 的事件（應觸發 Lambda）

```bash
BUS_NAME=$(terraform output -raw custom_bus_name)

aws events put-events --entries "[
  {
    \"EventBusName\": \"$BUS_NAME\",
    \"Source\": \"myapp.orders\",
    \"DetailType\": \"order.created\",
    \"Detail\": \"{\\\"order_id\\\": \\\"ORD-001\\\", \\\"status\\\": \\\"pending\\\", \\\"amount\\\": 150}\"
  }
]"
```

確認 processor Lambda 被觸發：

```bash
PROCESSOR=$(terraform output -raw processor_function_name)

aws logs tail "/aws/lambda/$PROCESSOR" --follow
```

### 3. 發布不符合 Pattern 的事件（不應觸發）

```bash
# status = "cancelled"，不在 filter 清單中
aws events put-events --entries "[
  {
    \"EventBusName\": \"$BUS_NAME\",
    \"Source\": \"myapp.orders\",
    \"DetailType\": \"order.created\",
    \"Detail\": \"{\\\"order_id\\\": \\\"ORD-002\\\", \\\"status\\\": \\\"cancelled\\\"}\"
  }
]"
```

確認 Lambda **沒有**新的 log（事件被 EventBridge 過濾掉了）。

### 4. 測試 source 不符合的事件（不應觸發）

```bash
aws events put-events --entries "[
  {
    \"EventBusName\": \"$BUS_NAME\",
    \"Source\": \"myapp.payments\",
    \"DetailType\": \"order.created\",
    \"Detail\": \"{\\\"order_id\\\": \\\"ORD-003\\\", \\\"status\\\": \\\"pending\\\"}\"
  }
]"
```

source 是 `myapp.payments`，不符合 Pattern，Lambda 不觸發。

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| EventBridge 自訂事件前 100 萬筆 | 免費 |
| Schedule Rule 前 14,400 次呼叫/月 | 免費 |
| Lambda 前 100 萬次呼叫 | 免費 |
| **合計** | **< $0.01** |

---

## 核心概念釐清

### EventBridge vs SNS vs SQS

| | EventBridge | SNS | SQS |
|--|---|---|---|
| 主要用途 | 事件路由（AWS 服務事件 + 自訂事件）| 廣播通知 | 工作佇列 |
| 過濾能力 | 強（Pattern 可過濾 source/detail-type/detail）| 基本（MessageAttribute Filter）| 無 |
| 觸發來源 | AWS 服務自動發出、或你 put-events | 你 publish | 你 send-message |
| 典型場景 | EC2 狀態變更自動通知、跨帳號事件 | 訂單通知給多個系統 | 非同步任務處理 |

### Default Bus vs Custom Bus

| | Default Event Bus | Custom Event Bus |
|--|---|---|
| 接收什麼 | AWS 服務事件（EC2, S3, RDS...）| 你自己 put-events 的自訂事件 |
| 可以 put-events 嗎 | 可以（但不建議混用）| 是，這是它的主要用途 |
| 建議用途 | 監聽 AWS 服務事件 | 應用程式內部事件流 |

### Event Pattern 的邏輯

```json
{
  "source": ["myapp.orders"],          // OR：source 等於任一個值
  "detail-type": ["order.created"],    // OR：detail-type 等於任一個值
  "detail": {
    "status": ["pending", "confirmed"] // OR：status 等於 pending 或 confirmed
  }
}
```

條件之間是 **AND**，清單內是 **OR**。

### 為什麼 Terraform 資源叫 `aws_cloudwatch_event_xxx`？

EventBridge 在 2019 年之前叫 **CloudWatch Events**，後來改名為 EventBridge 並擴充功能。
Terraform AWS Provider 保留了舊名稱以維持向後相容。功能上是同一個服務。

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| 排程 Lambda 沒被觸發 | `aws_lambda_permission` 的 `source_arn` 填錯，或 Rule `state = "DISABLED"` |
| put-events 回傳 FailedEntryCount: 1 | Event Bus 名稱錯誤，或 `Detail` 不是合法 JSON 字串 |
| Pattern Rule Lambda 沒被觸發 | `event_bus_name` 沒有同時設定在 Rule 和 Target 上 |
| Pattern Rule Lambda 沒被觸發 | `event_pattern` 的欄位名稱錯誤（注意 `detail-type` 有連字號）|
| destroy 後 Rule 仍存在 | CloudWatch Event Rule 有時需要先 disable 才能刪除，重試一次 |
