# Lab 44：Step Functions 工作流程編排

> **場景**：用 AWS Step Functions 實作訂單處理工作流程，包含四個 Lambda 步驟、Retry 自動重試、Catch 錯誤路由，以及 CloudWatch 執行日誌。  
> **費用等級**：🟢 安全（< $0.01；Standard Workflow 前 4000 次狀態轉換免費）

---

## 學習目標

完成本 lab 後，你能夠：

- 用 Terraform 的 `jsonencode()` 寫 ASL（Amazon States Language）狀態機定義，並在其中插入動態 Lambda ARN
- 理解 **Task / Succeed / Fail** 三種基本 State Type
- 配置 **Retry**（重試暫時性錯誤）與 **Catch**（捕捉不同錯誤類型並路由到對應 State）
- 理解 **ResultPath = "$.error"** 如何把例外資訊附加到輸入資料而不覆蓋
- 解釋 **Standard vs Express Workflow** 的取捨
- 在 Console 的執行歷史中看到每個 State 的輸入/輸出

---

## 架構

```
CLI / EventBridge
      │
      ▼ StartExecution（JSON input）
┌─────────────────────────────────────────────┐
│         Step Functions State Machine        │
│                                             │
│  [ValidateOrder]──►[ReserveInventory]       │
│       │                   │                 │
│    Catch                Catch               │
│       │                   │                 │
│  [ProcessPayment] ◄────────┘                │
│       │  Retry(PaymentRetryableError)        │
│    Catch                                    │
│       │                                     │
│  [NotifyCustomer]──►[OrderComplete✓]        │
│                                             │
│       └──────────► [OrderFailed✗]           │
└─────────────────────────────────────────────┘
      │                    │
  Lambda × 4           CloudWatch Logs
  (python3.12)          (ERROR level)
      │
  SNS Topic
  (notify_customer)
```

---

## 狀態機設計

| State | Type | 成功路徑 | 失敗路徑（Catch）| Retry |
|-------|------|---------|----------------|-------|
| ValidateOrder | Task | → ReserveInventory | InvalidOrderError → OrderFailed | Lambda 服務錯誤 × 2 |
| ReserveInventory | Task | → ProcessPayment | InsufficientInventoryError → OrderFailed | — |
| ProcessPayment | Task | → NotifyCustomer | PaymentFailedError → OrderFailed | PaymentRetryableError × 3（backoff 2x）|
| NotifyCustomer | Task | → OrderComplete | — | — |
| OrderComplete | Succeed | — | — | — |
| OrderFailed | Fail | — | — | — |

---

## 目錄結構

```
44-step-functions/
├── src/
│   ├── validate_order.py      ← 已提供（格式驗證）
│   ├── reserve_inventory.py   ← 已提供（庫存模擬）
│   ├── process_payment.py     ← 已提供（付款模擬，含隨機失敗）
│   └── notify_customer.py     ← 已提供（SNS 通知）
├── terraform.tf
├── variables.tf
├── locals.tf
├── main.tf                    ← TODO 1-5
├── outputs.tf
├── terraform.tfvars.example
└── .gitignore
```

---

## 你要做的事

| TODO | 位置 | 說明 |
|------|------|------|
| 1 | `main.tf` | Lambda IAM Role + AWSLambdaBasicExecutionRole + SNS Publish inline policy |
| 2 | `main.tf` | 4x archive_file + 4x aws_lambda_function（notify_customer 需 SNS_TOPIC_ARN env）|
| 3 | `main.tf` | SNS Topic + 條件式 email 訂閱 |
| 4 | `main.tf` | Step Functions IAM Role + inline policy（Lambda invoke + CloudWatch Logs）|
| 5 | `main.tf` | CloudWatch Log Group + aws_sfn_state_machine（ASL 定義 + logging_configuration）|

---

## 指令流程

```bash
# 複製 tfvars
cp terraform.tfvars.example terraform.tfvars

# 初始化
terraform init

# 格式化 + 驗證
terraform fmt
terraform validate

# 預覽（確認 State Machine 定義正確）
terraform plan

# 部署
terraform apply -auto-approve

# 查看輸出
terraform output
```

---

## 驗證方式

### 步驟 1：確認資源已建立

```bash
terraform state list
# 預期看到：
# aws_iam_role.lambda
# aws_iam_role.sfn
# aws_lambda_function.validate_order
# aws_lambda_function.reserve_inventory
# aws_lambda_function.process_payment
# aws_lambda_function.notify_customer
# aws_sns_topic.orders
# aws_cloudwatch_log_group.sfn
# aws_sfn_state_machine.order_workflow
```

### 步驟 2：執行成功案例

```bash
SFN_ARN=$(terraform output -raw state_machine_arn)

# 啟動執行（每次需要唯一的 --name）
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn $SFN_ARN \
  --name "test-success-$(date +%s)" \
  --input '{
    "order_id": "ORD-001",
    "customer_email": "customer@example.com",
    "items": [{"sku": "SKU-A", "quantity": 2, "price": 29.99}],
    "total_amount": 59.98
  }' \
  --query 'executionArn' --output text)

echo "Execution ARN: $EXEC_ARN"

# 等候幾秒後查看結果
sleep 5
aws stepfunctions describe-execution --execution-arn $EXEC_ARN \
  --query '{status: status, output: output}' --output json
# 預期 status: "SUCCEEDED"
```

### 步驟 3：測試庫存不足（Catch 路由）

```bash
# SKU 結尾為 "OOS" 會觸發 InsufficientInventoryError
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn $SFN_ARN \
  --name "test-oos-$(date +%s)" \
  --input '{
    "order_id": "ORD-002",
    "customer_email": "customer@example.com",
    "items": [{"sku": "SKU-OOS", "quantity": 1, "price": 9.99}],
    "total_amount": 9.99
  }' --query 'executionArn' --output text)

sleep 5
aws stepfunctions describe-execution --execution-arn $EXEC_ARN \
  --query 'status' --output text
# 預期: FAILED（在 ReserveInventory 被 Catch 路由到 OrderFailed）
```

### 步驟 4：測試驗證失敗（缺少欄位）

```bash
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn $SFN_ARN \
  --name "test-invalid-$(date +%s)" \
  --input '{"order_id": "ORD-003"}' \
  --query 'executionArn' --output text)

sleep 5
aws stepfunctions describe-execution --execution-arn $EXEC_ARN \
  --query '{status: status, cause: cause}' --output json
# 預期: FAILED（在 ValidateOrder 被 Catch 路由到 OrderFailed）
```

### 步驟 5：查看執行歷史（每個 State 的 I/O）

```bash
aws stepfunctions get-execution-history \
  --execution-arn $EXEC_ARN \
  --query 'events[].{type: type, state: stateEnteredEventDetails.name}' \
  --output table
```

```
# Console 視覺化圖表（推薦）
terraform output console_url
# 進入 Console → 點選 state machine → 點選執行 → 看 Graph Inspector
```

### 步驟 6：查看 CloudWatch 日誌（Error 層級）

```bash
LOG_GROUP="/aws/states/$(terraform output -raw state_machine_name)"
aws logs filter-log-events --log-group-name $LOG_GROUP --limit 20
```

### 步驟 7：批次執行（測試 ProcessPayment Retry）

```bash
# 連續發起 10 次執行，觀察哪些因 PaymentRetryableError 重試後成功
for i in $(seq 1 10); do
  aws stepfunctions start-execution \
    --state-machine-arn $SFN_ARN \
    --name "batch-test-$i-$(date +%s)" \
    --input "{
      \"order_id\": \"ORD-BATCH-$i\",
      \"customer_email\": \"test@example.com\",
      \"items\": [{\"sku\": \"SKU-X\", \"quantity\": 1}],
      \"total_amount\": 9.99
    }" > /dev/null
  sleep 1
done

# 30 秒後查看執行統計
sleep 30
aws stepfunctions list-executions \
  --state-machine-arn $SFN_ARN \
  --max-results 10 \
  --query 'executions[].{name: name, status: status}' \
  --output table
```

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 計費模式 | 費用 |
|------|---------|------|
| Step Functions Standard | 前 4000 次狀態轉換/月免費 | $0.00 |
| Lambda × 4 | 前 1M 次/月免費 | $0.00 |
| CloudWatch Logs | < 10 KB | $0.00 |
| SNS | 前 1M 次免費 | $0.00 |
| **合計** | | **$0.00** |

> **注意**：Express Workflow 前 1M 次狀態轉換免費；Standard 前 4000 次免費。本 lab 做幾十次測試絕對不收費。

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼用 Step Functions 而不是 SQS + Lambda 串接？

**決策**：用 Step Functions Standard Workflow 管理訂單處理流程，而不是 Lab 37 的 SQS + Lambda 串接模式。

**理由**：

| | SQS + Lambda（Lab 37）| Step Functions（Lab 44）|
|-|----------------------|------------------------|
| 執行可見性 | 無（需自行加 DynamoDB 記錄狀態）| ✅ 每個 State 的輸入/輸出一目了然 |
| 錯誤處理 | 需手動實作重試邏輯 + DLQ | ✅ Retry / Catch 宣告式配置 |
| 步驟編排 | 難以追蹤「執行到哪一步了」| ✅ 視覺化流程圖，實時看到當前 State |
| 成本 | 幾乎免費（前 1M 次）| 便宜（前 4000 次轉換免費）|
| 適合場景 | 高吞吐量 fire-and-forget | 需要追蹤每筆業務流程狀態 |

**結論**：
- **SQS**：適合高吞吐量、不需要逐筆追蹤的非同步工作（例如：圖片縮圖批次處理）
- **Step Functions**：適合需要知道「每筆訂單跑到哪一步」的業務流程（訂單、審批、資料遷移）

---

### ADR-2：為什麼選 Standard Workflow 而不是 Express Workflow？

**決策**：使用 Standard Workflow（`type = "STANDARD"`）。

**理由**：

| | Standard Workflow | Express Workflow |
|-|------------------|-----------------|
| 執行保證 | Exactly-once（每個 State 最多執行一次）| At-least-once（可能重複執行）|
| 最長執行時間 | 1 年 | 5 分鐘 |
| 吞吐量 | 2000 executions/s | 100,000 executions/s |
| 成本 | $0.025 / 1000 狀態轉換 | $0.00001 / 狀態轉換 + Duration |
| 執行歷史 | ✅ 90 天可查 | ✗ 需手動送 CloudWatch |
| 訂單處理適合？ | ✅（不能重複扣款！）| ✗（at-least-once 會重複執行）|

**結論**：訂單處理涉及付款，Exactly-once 語義是必要條件，必須選 Standard Workflow。
Express Workflow 適合高頻率、幂等的資料處理（如：日誌轉換、IoT 事件處理）。

---

### ADR-3：為什麼用 `jsonencode()` 而不是 `file()` 定義 ASL？

**決策**：State Machine `definition` 使用 `jsonencode(...)` HCL 物件，而不是 `file("state_machine.json")`。

**理由**：

```hcl
# ✅ jsonencode()：可插入 Terraform 動態值
definition = jsonencode({
  States = {
    ValidateOrder = {
      Resource = aws_lambda_function.validate_order.arn  # ← 直接引用
    }
  }
})

# ❌ file()：是純靜態字串，無法插入 Lambda ARN
definition = file("state_machine.json")
# → 必須手動複製 ARN，或用 templatefile() + 特殊佔位符 → 可讀性差
```

**取捨**：`jsonencode()` 的缺點是 HCL 和 JSON 語法混雜，IDE 無法驗證 ASL。如果 ASL 非常複雜（數十個 State），可考慮用 `templatefile("sfn.json.tpl", { lambda_arn = ... })`，但對本 lab 的規模，`jsonencode()` 更直觀。

**結論**：ASL 包含動態 ARN 時優先用 `jsonencode()`；複雜 ASL 考慮 `templatefile()`。

---

## 常見問題

| 症狀 | 原因 | 解法 |
|------|------|------|
| `InvalidDefinition` apply 失敗 | ASL JSON 語法錯誤（多餘逗號、錯誤鍵名）| `terraform validate`，仔細檢查 `jsonencode` 的括號層級 |
| 執行卡在某個 State | Lambda 內部錯誤未被 Catch 攔截 | 查 Lambda CloudWatch Logs，確認例外類別名稱與 Catch.ErrorEquals 完全一致 |
| `PaymentRetryableError` 未重試 | Retry 的 `ErrorEquals` 名稱拼錯 | Python 例外類名必須完全匹配（大小寫敏感）|
| `logs:CreateLogDelivery` 錯誤 | Step Functions IAM Role 缺少 Logs 權限 | 確認 `aws_iam_role_policy.sfn` 包含所有 logs:* 權限 |
| 無法同名重啟執行 | `--name` 在同一個 state machine 下必須唯一 | 加上時間戳：`--name "test-$(date +%s)"` |
| `$.error` 是空的 | `ResultPath` 配置錯誤 | 確認 Catch 的 `ResultPath = "$.error"` 不是 `"$"` |

---

## 延伸練習

完成基本 5 個 TODO 後，可嘗試：

1. **Wait State**：在 ProcessPayment 前加入 `Wait` State（`Seconds = 5`），模擬非同步付款確認
2. **Choice State**：在 ValidateOrder 後加入 `Choice`，用 `$.total_amount > 1000` 路由到「大額訂單審批」分支
3. **Parallel State**：NotifyCustomer 時同時通知客戶和出貨系統（兩個 Lambda 平行執行）
4. **Map State**：對 `$.items` 陣列的每個品項平行執行庫存檢查
5. **Express Workflow**：新增一個 `type = "EXPRESS"` 的 State Machine，比較執行歷史的差異

---

## 面試故事

> 「我在 Lab 44 做了一個 Step Functions 訂單工作流程。跟 Lab 37 用 SQS 串接 Lambda 的差別是，Step Functions 能讓我在 Console 直接看到每筆訂單跑到哪個步驟——ValidateOrder、ReserveInventory、ProcessPayment，每個 State 的輸入輸出都記錄下來，除錯超方便。
>
> 最有意思的設計是 Retry 和 Catch 的搭配：付款閘道的暫時性超時（PaymentRetryableError）用 Retry 自動重試三次，指數退避；庫存不足（InsufficientInventoryError）則用 Catch 直接路由到 OrderFailed State，不重試。這種宣告式的錯誤處理比自己在 Lambda 裡寫 try/except + SQS DLQ 清晰多了。
>
> 面試官常問 'Step Functions vs SQS 什麼時候用哪個'。我的答案是：需要追蹤每筆業務流程狀態、有複雜的錯誤路由邏輯，用 Step Functions；高吞吐量的 fire-and-forget 非同步工作（不需要知道每筆狀態），用 SQS。」

---

*建立於 2026-05-28*
