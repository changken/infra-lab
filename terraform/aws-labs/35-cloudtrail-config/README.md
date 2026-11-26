# Lab 35: CloudTrail + Config Rules + SNS 合規告警

> 建立 Multi-region CloudTrail，透過 CloudWatch Metric Filter 偵測安全事件（root login / SG 變更），觸發 SNS Email 告警；同時以 AWS Config Managed Rules 持續評估合規狀態。

**費用等級**：🟡 注意（< $0.50，CloudWatch Alarms ~$0.20，Config 錄製 ~$0.10，練完當天 destroy）

---

## 學習目標

- 理解 **CloudTrail** 和 **AWS Config** 的根本差異（事後稽核 vs 即時合規）
- 建立 **Multi-region Trail**，整合 S3 長期保存 + CloudWatch Logs 即時分析
- 撰寫 **CloudWatch Metric Filter** 的 JSON Pattern 語法（root login、SG 變更）
- 設定 **CloudWatch Alarm → SNS Email** 完整告警鏈路
- 啟動 **AWS Config Recorder + Delivery Channel**，部署 2 個 Managed Rules
- 理解 **CloudTrail Bucket Policy** 的必要格式（兩個服務共用 S3）

---

## 架構

```
┌───────────────────────────────────────────────────────────────┐
│  AWS Account                                                  │
│                                                               │
│  CloudTrail (Multi-region Trail)                              │
│    ├── S3 Bucket: {project}-logs-{account_id}                │
│    │     ├── AWSLogs/{account_id}/         (CloudTrail logs) │
│    │     └── AWSLogs/{account_id}/Config/  (Config snapshots)│
│    └── CloudWatch Log Group: /aws/cloudtrail/{project}        │
│          ├── Metric Filter: root-login-count                  │
│          │     └── Alarm → SNS Topic → Email                  │
│          └── Metric Filter: sg-change-count                   │
│                └── Alarm → SNS Topic → Email                  │
│                                                               │
│  AWS Config                                                   │
│    ├── Configuration Recorder (all supported resources)       │
│    ├── Delivery Channel → 同上 S3 Bucket                     │
│    ├── Rule 1: s3-bucket-public-write-prohibited              │
│    └── Rule 2: cloud-trail-enabled                           │
└───────────────────────────────────────────────────────────────┘
```

---

## 你要做的事

| TODO | 資源 | 關鍵概念 |
|------|------|---------|
| 1 | `aws_s3_bucket` + `aws_s3_bucket_public_access_block` + `aws_s3_bucket_policy` | Bucket Policy 格式固定，CloudTrail 和 Config 各需 GetBucketAcl + PutObject |
| 2 | `aws_cloudwatch_log_group` + `aws_iam_role` + `aws_iam_role_policy` + `aws_cloudtrail` | `cloud_watch_logs_group_arn` 必須加 `:*` 後綴 |
| 3 | `aws_cloudwatch_log_metric_filter` × 2 | JSON pattern 語法 `{ $.field = "value" }`，大小寫敏感 |
| 4 | `aws_cloudwatch_metric_alarm` × 2 | metric_name 和 namespace 必須和 Filter 完全一致 |
| 5 | `aws_sns_topic` + `aws_sns_topic_subscription` | apply 後立即確認訂閱信 |
| 6 | `aws_iam_role` + `aws_iam_role_policy_attachment` + `aws_config_configuration_recorder` + `aws_config_delivery_channel` + `aws_config_configuration_recorder_status` + `aws_config_config_rule` × 2 | depends_on 順序：Recorder → Channel → Status → Rules |

---

## 指令

```bash
# 1. 複製變數範例並填入 alert_email
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化（填完所有 TODO 後執行）
terraform fmt

# 4. 語法驗證（resource body 空白時會失敗，這是正常的）
terraform validate

# 5. 預覽
terraform plan

# 6. 部署
terraform apply
```

> **注意**：apply 後立即查收 `alert_email` 的確認信，點擊「Confirm subscription」，否則告警無法送達。

---

## 驗證

### 1. 確認 CloudTrail 正在記錄

```bash
TRAIL_ARN=$(terraform output -raw cloudtrail_arn)

aws cloudtrail get-trail-status \
  --name "$TRAIL_ARN" \
  --query '{IsLogging:IsLogging,LatestDelivery:LatestDeliveryTime}' \
  --output table
```

**期望輸出**：`IsLogging = True`

### 2. 確認 Multi-region Trail 設定

```bash
aws cloudtrail describe-trails \
  --query 'trailList[0].{Name:Name,MultiRegion:IsMultiRegionTrail,LogGroup:CloudWatchLogsLogGroupArn}' \
  --output table
```

**期望輸出**：`MultiRegion = True`

### 3. 觸發 API 事件並查詢（等待 5-15 分鐘）

```bash
# 任何 AWS API 呼叫都會被 CloudTrail 記錄
aws iam list-users > /dev/null
echo "等待 CloudTrail 傳送到 CloudWatch Logs（約 5-15 分鐘）..."

# 查詢最近事件
aws cloudtrail lookup-events --max-results 5 \
  --query 'Events[*].{User:Username,Event:EventName,Time:EventTime}' \
  --output table
```

### 4. 觸發 Security Group 變更（測試 Metric Filter）

```bash
# 建立臨時 SG，觸發 sg-change Metric Filter
SG_ID=$(aws ec2 create-security-group \
  --group-name "lab35-test-sg" \
  --description "Temporary test SG for lab 35" \
  --query 'GroupId' --output text)

echo "已建立 SG: $SG_ID，Metric Filter 應在 5 分鐘內計數"

# 立即刪除
aws ec2 delete-security-group --group-id "$SG_ID"
```

### 5. 確認 Config Recorder 運作中

```bash
aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[0].{Name:name,Recording:recording,LastStatus:lastStatus}' \
  --output table
```

**期望輸出**：`Recording = True`，`LastStatus = SUCCESS`

### 6. 確認 Config 合規評估（等待 5-10 分鐘）

```bash
aws configservice describe-compliance-by-config-rule \
  --query 'ComplianceByConfigRules[*].{Rule:ConfigRuleName,Compliance:Compliance.ComplianceType}' \
  --output table
```

**期望輸出**：`cloud-trail-enabled` 顯示 `COMPLIANT`（因本 lab 已建立 Trail）

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`。

> **注意**：S3 Bucket 設定了 `force_destroy = true`，destroy 時會自動清空並刪除。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| CloudTrail（前 90 天 management events）| $0（Free Tier）|
| S3 儲存（少量 log）| < $0.01 |
| CloudWatch Logs（ingestion）| < $0.10 |
| CloudWatch Metric Alarms（2 個）| ~$0.20 |
| AWS Config（依錄製資源數，lab 短時間）| < $0.10 |
| SNS（< 1000 email）| $0 |
| **合計** | **< $0.50（🟡 注意，練完當天 destroy）** |

---

## 核心概念釐清

### CloudTrail vs AWS Config

| | CloudTrail | AWS Config |
|--|-----------|-----------|
| 問的問題 | 誰在什麼時間做了什麼？ | 現在的資源設定是否合規？ |
| 資料來源 | API 呼叫事件 | 資源設定快照 |
| 時間特性 | 事後查詢 | 即時持續評估 |
| 告警整合 | CloudWatch Metric Filter → Alarm → SNS | Config Rule 評估結果 |
| SOA 考試重點 | Multi-region Trail、CloudWatch 整合 | Recorder、Delivery Channel、Managed Rules |

### depends_on 順序（AWS Config 必考）

```
aws_config_configuration_recorder   → 定義「錄什麼」
         ↓ depends_on
aws_config_delivery_channel          → 定義「送到哪」
         ↓ depends_on
aws_config_configuration_recorder_status → 啟動錄製（is_enabled = true）
         ↓ depends_on
aws_config_rule                      → 評估規則（需要 Recorder 在運作）
```

---

## 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 誰刪了這個 S3 bucket？ | CloudTrail | 查 `DeleteBucket` 事件，含呼叫者和時間 |
| 現在有哪些 S3 bucket 開放公開寫入？ | Config Rule | 持續評估，不需翻 log |
| 收到 root login 告警 | CloudTrail + Metric Filter + SNS | 即時通知，不需手動查詢 |
| 定期合規報告 | Config | 可匯出所有資源的合規狀態 |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 失敗：`Trail already exists` | 同 region 已有同名 Trail，換 `project` 名稱或先刪除舊 Trail |
| `apply` 失敗：`InsufficientS3BucketPolicyException` | Bucket Policy 缺少 CloudTrail 的 `GetBucketAcl` 或 `PutObject` Statement |
| `apply` 失敗：`InsufficientDeliveryPolicyException` | Config Delivery Channel 無法寫入 S3，確認 Bucket Policy 含 Config 的 Statement |
| Alarm 永遠不觸發 | `metric_name` 或 `namespace` 和 Metric Filter 不一致（大小寫敏感） |
| CloudTrail 事件沒出現在 CloudWatch Logs | `cloud_watch_logs_group_arn` 缺少 `:*` 後綴，或 IAM Role 權限不足 |
| Config Rule 顯示 `NOT_APPLICABLE` | 帳號中沒有被該 Rule 評估的資源（正常現象） |
| SNS 訂閱一直是 `PendingConfirmation` | 需手動點擊確認信中的連結 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
