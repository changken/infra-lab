# Lab 41：可觀測性全棧

> **場景**：為一個刻意「有好有壞」的 Lambda API，建立完整的可觀測性基礎設施。  
> **費用等級**：🟡 注意（< $1，主要是 Synthetics Canary，務必練完即 destroy）

---

## 學習目標

完成本 lab 後，你能夠：

- 啟用 Lambda X-Ray 主動追蹤（`tracing_config { mode = "Active" }`），在 Service Map 中看到請求鏈路
- 設定 API Gateway HTTP API 的 Access Log 到 CloudWatch Logs，並理解 HTTP API vs REST API 在 logging 設定上的差異
- 建立 **CloudWatch Log Metric Filter**，把 Log 中的 ERROR 字串轉成可告警的 Metric
- 設計 **CloudWatch Dashboard**，用 `jsonencode` 將動態資源名稱嵌入 Dashboard JSON
- 設定 **Synthetics Canary** 主動探測 API，理解黑盒監控（外部視角）vs 白盒監控（內部指標）的差異
- 使用 **CloudWatch Logs Insights** 查詢結構化 JSON 日誌

---

## 架構

```
使用者                     CloudWatch Synthetics
  │                              │ 每 5 分鐘 GET /
  │ curl                         │
  ▼                              ▼
API Gateway HTTP API（access_log → CloudWatch Logs /aws/apigateway/obs-lab）
  │
  ▼
Lambda: app（tracing_config = Active）
  ├── GET /        → 200 正常
  ├── GET /slow    → sleep(2s) 後回 200（可見 Duration P99 上升）
  ├── GET /error   → raise Exception → 500（觸發 Lambda Errors Alarm）
  └── GET /random  → 30% 機率 500（觀察 Error Rate 變化）
  │
  ├── X-Ray Trace → X-Ray Service Map / Trace 分析
  └── CloudWatch Logs /aws/lambda/obs-lab-app
            │
            ├── Log Metric Filter "ERROR" → AppErrorCount（自訂 Metric）
            └── Logs Insights 查詢（結構化 JSON 分析）

CloudWatch Dashboard（4 個 Widget）
  ├── Lambda Invocations & Errors（Sum）
  ├── Lambda Duration P99
  ├── API GW Requests & 5XX（Sum）
  └── Custom Error Count（ObservabilityLab namespace）

CloudWatch Alarms → SNS Topic → Email（optional）
  ├── lambda-errors: Lambda Errors ≥ 3/min
  ├── apigw-5xx: API GW 5XXError ≥ 5/min
  └── custom-errors: AppErrorCount ≥ 5/min
```

---

## 可觀測性三支柱對應

| 支柱 | 工具 | 本 lab 對應 |
|------|------|-----------|
| **Logs（日誌）** | CloudWatch Logs | Lambda JSON 日誌 + API GW Access Log |
| **Metrics（指標）** | CloudWatch Metrics | Lambda/API GW 原生指標 + 自訂 Metric Filter |
| **Traces（追蹤）** | X-Ray | Lambda Active Tracing → Service Map |
| **（黑盒）** | Synthetics Canary | 從外部視角主動探測 |
| **（告警）** | CloudWatch Alarms + SNS | 自動通知（Alarm → SNS → Email） |

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | Lambda IAM Role + Lambda Function | `tracing_config { mode = "Active" }` + `AWSXRayDaemonWriteAccess` |
| 2 | API GW + Access Log | `access_log_settings.destination_arn` + `$default` route |
| 3 | SNS Topic + Alarms | `treat_missing_data = "notBreaching"` + `ok_actions` |
| 4 | Log Metric Filter + Custom Alarm | `pattern = "ERROR"` + custom namespace |
| 5 | CloudWatch Dashboard | `jsonencode` 嵌入 4 個 metric widget |
| 6 | Synthetics Canary | S3 + IAM + `zip_file = filebase64(...)` + `run_config.environment_variables` |

---

## 指令

```bash
# 1. 複製 tfvars（如需 alarm email 通知，填入 notification_email）
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化
terraform fmt

# 4. 驗證
terraform validate

# 5. 預覽
terraform plan

# 6. 部署
terraform apply -auto-approve
```

---

## 驗證方式

### 步驟 1：取得 API Endpoint

```bash
API=$(terraform output -raw api_endpoint)
echo "API: $API"
```

### 步驟 2：產生各種流量類型

```bash
# 正常流量（20 次，給 Dashboard 有資料顯示）
for i in $(seq 1 20); do curl -s $API/ > /dev/null; echo -n "."; done; echo

# 慢速流量（5 次，讓 Duration P99 上升到 ~2 秒）
for i in $(seq 1 5); do curl -s $API/slow > /dev/null; echo "slow $i done"; done

# 錯誤流量（10 次，觸發 Lambda Errors Alarm）
for i in $(seq 1 10); do curl -s $API/error > /dev/null; echo -n "!"; done; echo

# 隨機錯誤流量（30 次，觀察 30% Error Rate）
for i in $(seq 1 30); do curl -s $API/random > /dev/null; echo -n "?"; done; echo
```

### 步驟 3：觀察 X-Ray Traces

```bash
# 列出最近 5 分鐘的 X-Ray traces（需要 IAM 權限）
aws xray get-trace-summaries \
  --start-time $(date -u -d '5 minutes ago' +%s 2>/dev/null || date -u -v-5M +%s) \
  --end-time $(date -u +%s) \
  --query 'TraceSummaries[*].{Id:Id,Duration:Duration,HasError:HasError,HasFault:HasFault}' \
  --output table
```

在 AWS Console → X-Ray → Traces 中可以看到：
- 每個 `/slow` 請求約 2 秒
- `/error` 和 `/random` 請求標記為 Fault（紅色）
- Service Map 顯示 Lambda 和 API GW 的健康狀態

### 步驟 4：查看 CloudWatch Dashboard

```bash
echo "Dashboard URL:"
terraform output -raw dashboard_url
```

開啟 URL 後，應看到 4 個 Widget：
- **Lambda Invocations & Errors**：Errors 在發送錯誤流量後上升
- **Lambda Duration P99**：發送 /slow 後 P99 超過 2000ms
- **API GW Requests & 5XX**：5XX 和 Error 流量對應
- **Custom Error Count**：Log Metric Filter 統計的 ERROR 次數

### 步驟 5：CloudWatch Logs Insights

在 AWS Console → CloudWatch → Logs Insights，選擇 Log Group `/aws/lambda/obs-lab-app`，執行：

```sql
-- 各路徑的請求數和錯誤數
fields @timestamp, path, event, error
| filter ispresent(path)
| stats count() as requests, count(error) as errors by path
| sort requests desc
```

```sql
-- 最近的 ERROR 事件
fields @timestamp, path, error, request_id
| filter level = "ERROR"
| sort @timestamp desc
| limit 20
```

### 步驟 6：確認 Alarm 狀態

```bash
# 查詢所有 Alarm 狀態
aws cloudwatch describe-alarms \
  --alarm-name-prefix obs-lab \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
  --output table
```

發送 10 次 `/error` 後，約 1-2 分鐘後 `obs-lab-lambda-errors` alarm 應變為 `ALARM` 狀態。

### 步驟 7：確認 Synthetics Canary

```bash
# 查看 Canary 最近執行結果
aws synthetics describe-canaries \
  --query 'Canaries[?Name==`obs-lab-heartbeat`].{Name:Name,State:Status.State,LastRun:Timeline.LastStarted}' \
  --output table

# 查看 Canary 執行歷史
aws synthetics get-canary-runs \
  --name obs-lab-heartbeat \
  --query 'CanaryRuns[*].{Status:Status.State,StartedAt:Timeline.Started,CompletedAt:Timeline.Completed}' \
  --output table
```

---

## 結束

```bash
# 清空 S3 Canary Artifact Bucket
CANARY_BUCKET=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `obs-lab-canary`)].Name' --output text)
aws s3 rm s3://$CANARY_BUCKET --recursive

# 銷毀所有資源
terraform destroy -auto-approve
```

> **重要**：Synthetics Canary 每分鐘有費用，務必記得 destroy！

---

## 成本估算

| 資源 | 計費模式 | 2 小時費用 |
|------|---------|-----------|
| Lambda | 前 1M 次免費 | $0.00 |
| API Gateway HTTP API | 前 1M 次/月免費 | $0.00 |
| CloudWatch Logs | 前 5GB/月免費 | $0.00 |
| CloudWatch Alarms | $0.10/alarm/月 × 3 | $0.00 |
| CloudWatch Dashboard | $3/月 × 2hr/720hr | $0.01 |
| X-Ray Traces | 前 100,000 traces/月免費 | $0.00 |
| **Synthetics Canary** | **$0.0012/run × 24 runs** | **$0.03** |
| S3 (Canary Artifacts) | 幾 KB，近乎免費 | $0.00 |
| **合計** | | **~$0.04** |

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼用 X-Ray Active Tracing 而不是 CloudWatch Metrics 加自訂追蹤？

**決策**：Lambda 設定 `tracing_config { mode = "Active" }`，使用 X-Ray 做分散式追蹤。

**理由**：
- **因果鏈路**：CloudWatch Metrics 只能知道「Lambda 有 X 次 Error」，X-Ray 能看到「哪個具體請求觸發了哪個 exception，花了多少時間在哪個階段」。
- **零程式碼成本**：`mode = "Active"` 讓 Lambda runtime 自動追蹤所有 boto3 呼叫（DynamoDB, S3, SNS 等），不需要 import xray SDK。
- **Service Map**：多個 Lambda 組成的系統可以看到整條呼叫鏈的健康狀態和延遲分布。

**代價**：前 100,000 traces/月免費，超過後 $5/1M traces。對高流量服務需評估成本。

**進階**：需要追蹤自訂 subsegment（如「query DB 花了多久」）才需要 import `aws-xray-sdk`。

---

### ADR-2：為什麼用 CloudWatch Dashboard 而不是 Grafana 或 Datadog？

**決策**：使用 `aws_cloudwatch_dashboard` 建立原生 CloudWatch Dashboard。

**理由**：
- **零設定成本**：AWS 原生指標直接可用，不需要設定 CloudWatch → Grafana 的資料源（data source）和 IAM 權限。
- **Terraform 友善**：`dashboard_body = jsonencode({...})` 可以直接引用 Terraform 資源名稱（`aws_lambda_function.app.function_name`），比 hardcode 更安全。
- **成本**：$3/month/dashboard；Datadog 約 $15-40/host/month。

**代價**：CloudWatch Dashboard 的視覺化和查詢彈性不如 Grafana / Datadog，跨帳號資料聚合能力較弱。

**結論**：純 AWS 環境，CloudWatch Dashboard 是最低運維成本的選擇；多雲或需要進階視覺化時，Grafana 更合適。

---

### ADR-3：為什麼需要 Synthetics Canary（外部黑盒監控）？

**決策**：建立 Synthetics Canary 每 5 分鐘主動呼叫 API，而不只依賴 Lambda Metrics。

**理由**：
- **盲區覆蓋**：Lambda Error Metric 只在有流量時才有資料（`treat_missing_data = notBreaching`）。若 API GW 本身掛掉（quota exceeded, deployment failure），Lambda 根本不會被呼叫，Lambda Metrics 不會顯示任何異常。Canary 能偵測到這類「無流量型故障」。
- **用戶視角**：Canary 從 AWS 外部節點發起請求，測試的是真實用戶能否存取 API，而不是 Lambda 內部是否健康。
- **SLA 計算**：`SuccessPercent` metric 可以直接用於 SLA 計算（如 99.9% uptime 對應每月最多 43 分鐘 downtime）。

**代價**：$0.0012/run，每 5 分鐘一次約 $0.52/月。需要評估是否值得。

---

## 可觀測性設計（觀察自己的 Observability Stack）

| 觀測點 | 工具 | 查詢方式 |
|--------|------|---------|
| Canary 探測結果 | Synthetics Console | `aws synthetics get-canary-runs --name obs-lab-heartbeat` |
| Alarm 觸發紀錄 | CloudWatch Alarm History | `aws cloudwatch describe-alarm-history --alarm-name obs-lab-lambda-errors` |
| Lambda 冷啟動 | X-Ray → Initialization Segment | X-Ray Console → Trace 詳細頁 |
| Log Metric Filter 計數 | CloudWatch Metrics Custom | namespace=ObservabilityLab, metric=AppErrorCount |
| SNS 訊息成功發送 | CloudWatch Metrics | namespace=AWS/SNS, metric=NumberOfMessagesPublished |

---

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| X-Ray 沒有 Trace | Lambda 的 `tracing_config.mode` 未設 "Active" | 確認 `mode = "Active"`（不是 "PassThrough"）；確認 IAM Role 有 `AWSXRayDaemonWriteAccess` |
| Dashboard Widget 顯示 "No data" | 還沒有流量 | 先執行 load test，再等 1-2 分鐘讓 metric 更新 |
| Alarm 一直是 INSUFFICIENT_DATA | `treat_missing_data` 設定問題 | 先執行 load test 產生資料；INSUFFICIENT_DATA 是正常初始狀態 |
| Log Metric Filter 沒有計數 | pattern 不匹配或 log group 名稱錯誤 | 確認 `log_group_name` 和 Lambda 實際 log group 一致；確認有觸發 /error 路徑 |
| Canary apply 失敗 | `zip_file` 路徑問題 | 確認 `data.archive_file.canary.output_path` 已被 Terraform 評估（加 depends_on 或重跑 plan） |
| Canary 執行失敗（Status: FAILED）| IAM Role 缺少 S3 寫入權限 | 確認 IAM Policy 有 `s3:PutObject` 和 `s3:GetBucketLocation` 在 canary bucket |
| HTTP API access log 沒有資料 | HTTP API 不需要 `aws_api_gateway_account`，但 log group ARN 可能錯誤 | 確認 `destination_arn` 指向正確的 log group ARN |
| SNS email 沒收到通知 | Email subscription 需要手動確認 | 到 SNS Console 確認訂閱（或到 email 收件箱點確認連結） |

---

## 面試故事

> 「我在 Lab 41 建了一個完整的可觀測性系統。應用層用 Lambda X-Ray Active Tracing，不需要改任何程式碼就能看到請求的完整鏈路；API GW 的 Access Log 輸出到 CloudWatch Logs，用 Logs Insights 的結構化查詢找出各路徑的錯誤率。
>
> 監控層有兩種：白盒（CloudWatch Log Metric Filter 把 log 中的 ERROR 轉成 Metric 並 Alarm）和黑盒（Synthetics Canary 每 5 分鐘從外部探測 API 是否健康）。黑盒的好處是能偵測到 API GW 本身掛掉的情況——這時 Lambda 根本不會被呼叫，白盒指標完全看不到異常。
>
> Dashboard 用 Terraform `jsonencode` 直接把資源名稱嵌入 JSON，不用 hardcode，重新 apply 後 Dashboard 自動更新。
>
> 面試時我說：可觀測性的核心是——你不知道系統壞了比系統壞了更危險。Canary 解決的是「你以為系統正常但其實用戶進不來」的盲區。」

---

*建立於 2026-05-28*
