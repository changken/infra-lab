# Lab 42：安全合規架構

> **場景**：為 AWS 帳號建立三層安全監控：API 稽核（CloudTrail）、資源合規（Config）、威脅偵測（GuardDuty），全部透過 EventBridge 路由到統一通知管道。  
> **費用等級**：🟡 注意（~$1，主要是 AWS Config 計費，練完即 destroy）

---

## 學習目標

完成本 lab 後，你能夠：

- 設定 CloudTrail multi-region trail，啟用 Log File Integrity Validation，理解為何需要
- 掌握 AWS Config 的三資源依賴鏈（Recorder → Channel → Status），以及為何不能亂序
- 使用 AWS Managed Config Rules 檢查 CIS Benchmark 合規項目
- 啟用 GuardDuty，理解其與 CloudTrail 的差異（事後稽核 vs 即時 ML 威脅偵測）
- 用 EventBridge 統一路由多個安全服務的事件到 SNS，設計 SNS Topic Policy 允許多 Principal
- 實作 CIS Benchmark CloudWatch Metric Filters（Root 使用、未授權 API、IAM 變更）

---

## 架構

```
┌─────────────────────────────────────────────────────────────────────┐
│ 安全監控三層架構                                                     │
│                                                                     │
│ Layer 1: 稽核（CloudTrail）                                         │
│   所有 AWS API 呼叫 ─────────────────────► S3 Bucket（留存）        │
│                    └───────────────────► CloudWatch Logs            │
│                                              │                      │
│                                         Metric Filters（CIS）       │
│                                    ┌─── Root 帳號使用               │
│                                    ├─── 未授權 API 呼叫             │
│                                    └─── IAM 政策變更                │
│                                              │ Alarm               │
│                                              ▼                      │
│ Layer 2: 合規（AWS Config）                                         │
│   資源快照 + 持續評估 ─────────────────────► S3 Bucket（快照）      │
│                      Config Rules（CIS）:                           │
│                      ├─ S3 禁止公開讀取                             │
│                      ├─ Root MFA 啟用                               │
│                      └─ IAM 密碼政策                                │
│                          NON_COMPLIANT │                            │
│                                       ▼                             │
│                              EventBridge Rule ──────────────────────┤
│                                                                     │
│ Layer 3: 威脅偵測（GuardDuty）                                      │
│   ML 分析（VPC Flow, DNS, CloudTrail） ──────────────────────────── │
│   Finding (severity ≥ Medium=4) ──► EventBridge Rule ───────────────┤
│                                                                     │
│                                              ▼                      │
│                                   SNS Topic: security-alerts        │
│                                        └──► Email（optional）       │
└─────────────────────────────────────────────────────────────────────┘
```

### 與 Lab 35 的差異

| 比較項目 | Lab 35 | Lab 42 |
|---------|--------|--------|
| 範疇 | CloudTrail + Config 基礎 | 加入 GuardDuty + EventBridge + CIS Benchmark |
| 通知架構 | Config → SNS（直接） | Config/GuardDuty → EventBridge → SNS（統一路由） |
| 威脅偵測 | 無 | GuardDuty（ML 分析） |
| 稽核深度 | 基礎 | CIS Metric Filters（Root, 未授權 API, IAM 變更） |

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | CloudTrail + S3 + IAM + CW Logs | `is_multi_region_trail = true`, `enable_log_file_validation = true` |
| 2 | AWS Config（S3 + IAM + Recorder + Channel + Status）| 三資源依賴順序：Recorder → Channel → Status |
| 3 | AWS Config Rules × 3 | `depends_on [recorder_status]`, `source_identifier` 全大寫格式 |
| 4 | GuardDuty + SNS + SNS Topic Policy | `Principal.Service` 允許 `events.amazonaws.com` |
| 5 | EventBridge Rules（Config + GuardDuty → SNS）| `severity >= 4` 過濾 Medium/High |
| 6 | CloudWatch Metric Filters + Alarms（CIS）| `namespace = "SecurityMetrics/{project}"` |

---

## 指令

```bash
# 1. 複製 tfvars（選填 notification_email）
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化
terraform fmt

# 4. 驗證
terraform validate

# 5. 預覽（注意：Config 一旦 apply 就開始計費）
terraform plan

# 6. 部署
terraform apply -auto-approve
```

---

## 驗證方式

### 步驟 1：確認 CloudTrail 已啟動

```bash
# 確認 Trail 狀態
aws cloudtrail get-trail-status --name sec-lab-trail \
  --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime}'

# 查詢最近 10 筆 API 事件
aws cloudtrail lookup-events --max-results 10 \
  --query 'Events[*].{Time:EventTime,User:Username,Event:EventName}' \
  --output table
```

### 步驟 2：查詢 Config Rules 合規狀態

```bash
# 等待 5-10 分鐘讓初始評估完成
aws configservice get-compliance-summary-by-config-rule \
  --query 'ComplianceSummariesByConfigRule[*].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}' \
  --output table
```

**預期結果（未達到 CIS Benchmark 的新帳號）：**
- `root-account-mfa-enabled` → `NON_COMPLIANT`（若 Root 帳號未啟用 MFA）
- `iam-password-policy` → `NON_COMPLIANT`（若未設定嚴格密碼政策）
- `s3-bucket-public-read-prohibited` → `COMPLIANT`（若無公開 S3 bucket）

### 步驟 3：模擬 Config 合規違規

```bash
# 建立一個（臨時）公開讀取的 S3 Bucket，觸發 s3-bucket-public-read-prohibited
TEST_BUCKET="test-public-$(date +%s)"
aws s3api create-bucket --bucket $TEST_BUCKET --region us-east-1
aws s3api put-bucket-acl --bucket $TEST_BUCKET --acl public-read

echo "等待 5-10 分鐘讓 Config 偵測到違規..."
echo "若有設定 notification_email，應會收到 SNS 告警"

# 查詢違規清單
aws configservice describe-compliance-by-config-rule \
  --compliance-types NON_COMPLIANT \
  --query 'ComplianceByConfigRules[*].{Rule:ConfigRuleName}' \
  --output table

# 清理測試 bucket
aws s3api delete-bucket --bucket $TEST_BUCKET --region us-east-1
```

### 步驟 4：查詢 GuardDuty

```bash
DETECTOR_ID=$(terraform output -raw guardduty_detector_id)

# 查詢 Detector 狀態
aws guardduty get-detector --detector-id $DETECTOR_ID \
  --query '{Status:Status,UpdatedAt:UpdatedAt}'

# 列出 Findings（新帳號通常為空）
aws guardduty list-findings --detector-id $DETECTOR_ID --output text
```

> **注意**：GuardDuty 需要時間分析行為基線，新帳號短時間內通常不會有 Findings。可查看 [GuardDuty Sample Findings](https://docs.aws.amazon.com/guardduty/latest/ug/sample_findings.html) 瞭解 Finding 格式。

### 步驟 5：確認 CloudWatch Alarms 狀態

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix sec-lab \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' \
  --output table
```

初始狀態應為 `INSUFFICIENT_DATA`（尚無流量資料）。

### 步驟 6：確認 Metric Filter 正在運作

```bash
# 確認 CloudTrail 有寫入 CloudWatch Logs
aws logs describe-log-streams \
  --log-group-name /aws/cloudtrail/sec-lab \
  --query 'logStreams[0].{Name:logStreamName,LastEvent:lastEventTime}' \
  --output table

# 查詢最近的 CloudTrail JSON Log（確認格式）
aws logs tail /aws/cloudtrail/sec-lab --since 10m
```

### 步驟 7：查看 Console

```bash
echo "Config Console:      $(terraform output -raw config_console_url)"
echo "GuardDuty Console:   $(terraform output -raw guardduty_console_url)"
echo "CloudTrail Console:  $(terraform output -raw cloudtrail_console_url)"
```

---

## 結束

```bash
# 清空 S3 Buckets（非空 bucket 無法 destroy）
CLOUDTRAIL_BUCKET=$(terraform output -raw cloudtrail_bucket)
CONFIG_BUCKET=$(terraform output -raw config_bucket)
aws s3 rm s3://$CLOUDTRAIL_BUCKET --recursive
aws s3 rm s3://$CONFIG_BUCKET --recursive

# 銷毀所有資源
terraform destroy -auto-approve
```

> **重要**：AWS Config 的計費從 `recorder_status.is_enabled = true` 開始。務必確認 destroy 成功。  
> **重要**：GuardDuty 免費試用 30 天，之後收費，也要確認 destroy。

---

## 成本估算

| 資源 | 計費模式 | 2 小時費用 |
|------|---------|-----------|
| CloudTrail（Management Events）| 第一條 Trail 免費 | $0.00 |
| CloudTrail S3 Storage | $0.023/GB，幾 KB | $0.00 |
| **AWS Config（Configuration Items）** | **$0.003/CI** | **~$0.10** |
| AWS Config Rules | 前 100,000 evaluations/月免費 | $0.00 |
| **GuardDuty（首 30 天試用）** | **$0** | **$0.00** |
| CloudWatch Logs（MetricFilter）| 前 5GB/月免費 | $0.00 |
| CloudWatch Alarms × 3 | $0.10/alarm/month | $0.00 |
| SNS | 前 1M publishes/月免費 | $0.00 |
| EventBridge | 前 1M events/月免費 | $0.00 |
| **合計** | | **~$0.10** |

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼要 CloudTrail + GuardDuty 兩者並用？

**決策**：同時啟用 CloudTrail（稽核日誌）和 GuardDuty（威脅偵測），而不是只用其中一個。

**理由**：

| | CloudTrail | GuardDuty |
|-|-----------|----------|
| 性質 | 被動記錄（事後查） | 主動偵測（即時告警） |
| 輸入 | 所有 API 呼叫 | CloudTrail + VPC Flow Log + DNS Query |
| 告警方式 | 靠 Metric Filter + Alarm（需手動設規則） | ML 自動識別異常行為 |
| 典型用途 | 取證、合規稽核、變更追蹤 | 即時威脅響應（帳號盜用、加密挖礦、等）|

GuardDuty 能偵測「帳號被盜後的橫向移動行為」——即使攻擊者使用合法 IAM 憑證，GuardDuty 也能從行為模式（異常時間、異常地區 IP、異常 API 呼叫頻率）判斷威脅。CloudTrail 只記錄事實，不判斷異常。

**結論**：兩者互補，生產環境應同時開啟。

---

### ADR-2：為什麼用 EventBridge 路由而不是直接讓 Config/GuardDuty 通知 SNS？

**決策**：透過 EventBridge Rules 將安全事件路由到 SNS，而非讓 Config 和 GuardDuty 各自直接通知 SNS。

**理由**：
- **統一過濾**：GuardDuty 有 Low/Medium/High/Critical 四個嚴重等級，直接通知會把所有等級都送出去，造成告警疲勞。EventBridge Rule 可以設 `severity >= 4`，只通知值得關注的。
- **統一目標**：多個安全服務的事件都路由到同一個 SNS Topic，接收方（人、Lambda、Slack webhook）只需訂閱一個 Topic。
- **可擴展**：未來加入 Security Hub 或 Inspector，只需再加 EventBridge Rule，不需改動 SNS 訂閱者。

**代價**：多一層 EventBridge，需要正確設定 SNS Topic Policy 允許 `events.amazonaws.com` 發布。

**結論**：EventBridge 作為安全事件匯流排，是 AWS 官方推薦的最佳實踐（Well-Architected Security Pillar）。

---

### ADR-3：為什麼要 CIS Benchmark Metric Filters？Config Rules 還不夠嗎？

**決策**：在 CloudTrail → CloudWatch Logs 管線上設定 CIS Benchmark 的三個 Metric Filter（Root 使用、未授權 API、IAM 變更）。

**理由**：Config Rules 檢查的是「資源的靜態狀態」（e.g., S3 bucket 是否公開），而 Metric Filters 監控的是「誰在做什麼」（行為事件）。

| | Config Rules | CloudTrail Metric Filters |
|-|-------------|--------------------------|
| 監控對象 | 資源配置（是否合規） | API 呼叫行為（誰在做什麼） |
| 典型場景 | S3 被設為公開、安全群組開放 0.0.0.0 | Root 帳號登入、連續 AccessDenied |
| 評估時機 | 資源變更時或定時觸發 | 實時（log 到 CloudWatch 的延遲約 15 秒） |

Root 帳號被使用是最高優先級的安全事件——Config 無法偵測這個，因為 Root 使用不改變任何資源配置，但 CloudTrail 會記錄 API 呼叫，Metric Filter 能即時偵測。

**結論**：兩者監控不同維度，需要同時部署。

---

## 可觀測性設計（觀察安全監控本身）

| 觀測點 | 工具 | 查詢方式 |
|--------|------|---------|
| CloudTrail 是否在記錄 | CloudTrail GetTrailStatus | `aws cloudtrail get-trail-status --name sec-lab-trail` |
| Config Recorder 是否啟動 | Config DescribeConfigurationRecorderStatus | `aws configservice describe-configuration-recorder-status` |
| GuardDuty 是否啟用 | GuardDuty GetDetector | `aws guardduty get-detector --detector-id <id>` |
| Metric Filter 是否接收 log | CloudWatch Logs | `aws logs tail /aws/cloudtrail/sec-lab` |
| SNS Topic Policy 是否正確 | SNS GetTopicAttributes | `aws sns get-topic-attributes --topic-arn <arn>` |
| EventBridge Rule 是否啟用 | EventBridge ListRules | `aws events list-rules --name-prefix sec-lab` |

---

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| `apply` 報 "there is no delivery channel" | Config resources 順序錯誤 | 確認 `delivery_channel.depends_on = [recorder]`，`recorder_status.depends_on = [delivery_channel]` |
| CloudTrail S3 PutObject 403 | S3 Bucket Policy 的 `AWS:SourceArn` 條件與 trail name 不符 | 確認 `trail/${var.project}-trail` 與 `aws_cloudtrail.main.name` 一致 |
| CloudTrail 的 CloudWatch Logs 沒有資料 | `cloud_watch_logs_group_arn` 結尾未加 `:*` | 改為 `"${aws_cloudwatch_log_group.cloudtrail.arn}:*"` |
| Config Rules 報 "recorder is not running" | Config Rules 在 recorder status 之前建立 | 加 `depends_on = [aws_config_configuration_recorder_status.main]` |
| EventBridge → SNS 沒有收到訊息 | SNS Topic Policy 未允許 `events.amazonaws.com` | 確認 Policy 有 `Principal.Service = "events.amazonaws.com"`, `Action = "sns:Publish"` |
| GuardDuty Findings 為空 | 正常，新帳號沒有歷史行為基線 | GuardDuty 需要時間建立 baseline；可用 `generate-sample-findings` 產生測試 Finding |
| Metric Filter Alarm 一直是 INSUFFICIENT_DATA | CloudTrail 日誌未到 CloudWatch Logs | 確認 CloudTrail 的 `cloud_watch_logs_group_arn` 和 `cloud_watch_logs_role_arn` 設定正確 |
| Config 計費超預期 | `all_supported = true` 記錄太多資源類型 | 設定 `recording_mode` 只記錄特定資源（進階設定）；或縮短 lab 時間 |

---

## 面試故事

> 「我在 Lab 42 建了一個符合 CIS AWS Foundations Benchmark 的安全合規架構。
>
> 三層防護：CloudTrail 記錄所有 API 呼叫（稽核用），AWS Config 持續評估資源配置是否符合策略（合規用），GuardDuty 用 ML 即時偵測威脅行為（安全用）。
>
> 所有安全事件統一透過 EventBridge 路由到同一個 SNS Topic——Config 的 NON_COMPLIANT 事件和 GuardDuty 的 Medium 以上 Finding，都能即時通知到 Email 或 Slack。EventBridge 的好處是可以設嚴重等級過濾，GuardDuty Low severity 不通知，避免告警疲勞。
>
> 面試時我說：Config 和 GuardDuty 監控的是不同維度。Config 問的是『資源現在的狀態是否安全』（S3 是否公開），GuardDuty 問的是『有沒有人在做可疑的事』（Root 帳號在凌晨從未知 IP 登入）。兩者缺一不可。」

---

*建立於 2026-05-28*
