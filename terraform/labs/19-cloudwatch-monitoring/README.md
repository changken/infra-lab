# Lab 19: CloudWatch Monitoring

建立完整的 AWS 監控鏈：Lambda 產生指標 → CloudWatch Alarm → SNS Email 通知 → Dashboard 視覺化。
**費用等級 🟢 安全** — CloudWatch Alarm $0.10/月，Dashboard $3/月，Lambda 免費。整個 Lab < $0.01，可觀察幾天再 destroy。

## 學習目標

- `aws_sns_topic` + `aws_sns_topic_subscription`：建立通知頻道，alarm 觸發時寄 Email
- `aws_cloudwatch_metric_alarm`：監控 AWS 內建 Metric（Lambda Errors），理解 `comparison_operator / evaluation_periods / threshold` 三個核心參數
- `aws_cloudwatch_log_metric_filter`：從 Log 文字中擷取自訂 Metric（pattern → metric_transformation）
- `aws_cloudwatch_dashboard`：用 `jsonencode` 定義 Widget 佈局，理解 metric/alarm Widget 結構

## 架構

```
                   ┌─────────────────────────┐
Lambda 執行（30% 錯誤率）               │
    ↓                                   │
CloudWatch Logs                         │  Dashboard
    │                                   │  ├── Widget: Lambda Invocations & Errors（折線圖）
    ├─→ Log Metric Filter               │  └── Widget: Active Alarms（狀態燈）
    │   （pattern="ERROR" → ErrorCount）│
    │                                   └─────────────────────────┘
    ↓
CloudWatch Metric Alarm（Errors > 0）
    ↓
SNS Topic
    ↓
Email 通知
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_sns_topic.alerts` | 最簡單的資源，就一個 name |
| 2 | `aws_sns_topic_subscription.email` | `protocol = "email"`，apply 後需點信箱確認 |
| 3 | `aws_cloudwatch_metric_alarm.lambda_errors` | `namespace/metric_name/dimensions` 三件套，`threshold = 0` |
| 4 | `aws_cloudwatch_log_metric_filter.error_count` | `pattern = "ERROR"`，`metric_transformation` 計數 |
| 5 | `aws_cloudwatch_dashboard.main` | `jsonencode` 的 widgets 陣列，metric Widget + alarm Widget |

已預填：`archive_file`（Lambda zip 打包）、CloudWatch Log Group、Lambda IAM Role、Lambda Function

## 指令

### Step 1：填寫 TODOs 並建立資源

```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入你的 Email

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：9 to add
terraform apply
```

### Step 2：確認 Email 訂閱

**重要**：apply 後立刻到信箱，找一封來自 `no-reply@sns.amazonaws.com` 的信，點「Confirm subscription」。  
沒確認就不會收到 alarm 通知。

### Step 3：觸發 Alarm

```bash
# 取得 Lambda 呼叫指令
terraform output invoke_command

# 執行 10-20 次（30% 錯誤率，應有 3-6 次 ERROR）
# Linux/Mac：
for i in {1..15}; do
  aws lambda invoke --function-name cw-lab-function --region us-east-1 /dev/null
done

# Windows PowerShell：
1..15 | ForEach-Object {
  aws lambda invoke --function-name cw-lab-function --region us-east-1 $null
}
```

### Step 4：驗證監控

```bash
# 查看 Alarm 狀態（ALARM / OK / INSUFFICIENT_DATA）
aws cloudwatch describe-alarms --alarm-names "cw-lab-lambda-errors" \
  --query "MetricAlarms[0].StateValue"

# 查看 Lambda Logs
aws logs tail /aws/lambda/cw-lab-function --follow

# 查看自訂 Metric（Log Metric Filter 產生的）
aws cloudwatch get-metric-statistics \
  --namespace "cw-lab/Custom" \
  --metric-name "ErrorCount" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --region us-east-1
```

**開啟 Dashboard（用瀏覽器）：**
```bash
terraform output dashboard_url
# 複製 URL 到瀏覽器，應看到折線圖和 Alarm 狀態燈
```

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| CloudWatch Alarm（1 個）| $0.10/月 |
| CloudWatch Dashboard（1 個）| $3/月 |
| Log Metric Filter | 免費 |
| Lambda 執行 | 免費（Free Tier）|
| SNS Email 通知 | 免費（1M 次/月）|
| **1 天 Lab 合計** | **< $0.01** |

## CloudWatch Alarm 三個核心參數

```
comparison_operator = "GreaterThanThreshold"
evaluation_periods  = 1       ← 連續幾個 period 超過才算 alarm
period              = 60      ← 每個 period 的秒數
threshold           = 0       ← 超過這個值就 alarm
```

**組合邏輯**：每 60 秒評估一次，連續 1 個週期的 Errors 總和 > 0 → 進入 ALARM 狀態。

## Log Metric Filter Pattern 語法

| Pattern 範例 | 匹配對象 |
|-------------|---------|
| `"ERROR"` | 包含 ERROR 字串的行 |
| `"?ERROR ?WARN"` | 包含 ERROR 或 WARN 的行 |
| `"[level=ERROR, ...]"` | 空格分隔格式的欄位匹配 |
| `{ $.level = "ERROR" }` | JSON 格式 log 的欄位匹配 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Alarm 一直是 `INSUFFICIENT_DATA` | Lambda 還沒被 invoke，或 evaluation_periods 太大 |
| 沒收到 Email | 沒點信箱確認連結（找 `AWS Notification - Subscription Confirmation`）|
| Dashboard 開啟後 Widget 空白 | Lambda 剛 invoke，CloudWatch Metrics 有 1-2 分鐘延遲 |
| `terraform plan` 顯示 `archive_file` 每次都有 diff | 正常，`archive_file` 在 plan 時重新計算 hash |
| Log Metric Filter Metric 沒出現 | CloudWatch 只在 log 匹配時才建立 Metric，需先有 invoke 且發生 ERROR |
