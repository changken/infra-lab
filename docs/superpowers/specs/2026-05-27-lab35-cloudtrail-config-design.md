# Lab 35: CloudTrail + Config Rules + SNS 合規告警 — Design Spec

**日期**：2026-05-27
**階段**：Phase 1-D 安全與合規
**費用**：< $0.50
**認證覆蓋**：SOA, SAA

---

## 目標

建立填空式 Terraform 骨架，讓用戶透過實作理解：
1. CloudTrail 如何將 API 事件串接到 CloudWatch Logs
2. CloudWatch Metric Filter + Alarm 如何偵測特定安全事件（root login、SG 變更）
3. AWS Config Recorder + Managed Rules 如何持續評估合規狀態
4. CloudTrail 看「誰動了什麼」vs Config 看「現在是否合規」的本質差異

---

## 架構

```
CloudTrail (Multi-region Trail)
  ├── S3 Bucket (cloudtrail-logs-{account}-{random})
  │     └── Lifecycle: 90 天後轉 Glacier（TODO 骨架，可選）
  └── CloudWatch Log Group (/aws/cloudtrail/lab35)
        ├── Metric Filter 1: root-login-count
        │     └── CloudWatch Alarm → SNS Topic → Email
        └── Metric Filter 2: sg-change-count
              └── CloudWatch Alarm → SNS Topic → Email

AWS Config
  ├── IAM Role (aws-config-role)
  ├── Configuration Recorder
  ├── Delivery Channel → 同一個 S3 Bucket
  ├── Rule 1: s3-bucket-public-write-prohibited
  └── Rule 2: cloud-trail-enabled
```

---

## TODO 填空設計（6 個）

| TODO | 資源 | 關鍵設定 | 常見卡關 |
|------|------|---------|---------|
| 1 | `aws_s3_bucket` + `aws_s3_bucket_policy` | CloudTrail bucket policy 格式固定：需包含 `GetBucketAcl` 和 `PutObject` | policy `Resource` 路徑需含 `AWSLogs/{account_id}/*` |
| 2 | `aws_cloudwatch_log_group` + `aws_iam_role`（CloudTrail 用）+ `aws_cloudtrail` | `is_multi_region_trail = true`、`cloud_watch_logs_group_arn` 需加 `:*` 後綴 | log group ARN 格式錯誤是最常見錯誤 |
| 3 | `aws_cloudwatch_log_metric_filter` × 2 | root: `{ $.userIdentity.type = "Root" }`、sg: `{ $.eventName = "AuthorizeSecurityGroupIngress" }` | pattern 語法嚴格，大小寫和空格敏感 |
| 4 | `aws_cloudwatch_metric_alarm` × 2 | `comparison_operator = "GreaterThanOrEqualToThreshold"`、`threshold = 1`、`alarm_actions = [aws_sns_topic.alerts.arn]` | namespace 必須和 metric filter 一致 |
| 5 | `aws_sns_topic` + `aws_sns_topic_subscription` | `protocol = "email"`、`endpoint = var.alert_email` | 訂閱需手動點 Email 確認連結 |
| 6 | `aws_iam_role`（Config 用）+ `aws_config_configuration_recorder` + `aws_config_delivery_channel` + `aws_config_rule` × 2 | `source.owner = "AWS"`、rule name: `s3-bucket-public-write-prohibited`、`cloud-trail-enabled` | Recorder 要先 apply，Rule 才能評估 |

---

## 檔案結構

```
terraform/labs/35-cloudtrail-config/
├── terraform.tf           # AWS provider >= 5.0, terraform >= 1.9
├── variables.tf           # aws_region, project_name, environment, alert_email
├── locals.tf              # common_tags, account_id (data source)
├── main.tf                # 6 個 TODO 區塊
├── outputs.tf             # cloudtrail_arn, log_group_name, sns_topic_arn, config_recorder_name
├── terraform.tfvars.example
├── .gitignore
└── README.md
```

---

## 驗證設計（動態驗證腳本）

1. **確認 CloudTrail 啟動**：`aws cloudtrail describe-trails --home-region`
2. **觸發 root 模擬**：手動呼叫 `aws iam list-users`（用非 root 帳號），說明真正 root 無法在 lab 中安全觸發
3. **觸發 SG 變更**：`aws ec2 describe-security-groups`（不會觸發），改用 `aws ec2 create-security-group`（示範）
4. **確認 Config 評估**：`aws configservice describe-compliance-by-config-rule`
5. **查看 CloudTrail 最近事件**：`aws cloudtrail lookup-events --max-results 5`

---

## 成本估算

| 資源 | 費用 |
|------|------|
| CloudTrail（前 90 天 management events）| $0（Free Tier）|
| S3 儲存（少量 log）| < $0.01 |
| CloudWatch Metrics + Alarms（2 個）| < $0.20 |
| CloudWatch Logs（ingestion）| < $0.10 |
| AWS Config（每個 recorded resource/月）| ~$0.003/resource，lab 短時間 < $0.10 |
| SNS（< 1000 email）| $0 |
| **合計** | **< $0.50（🟡 注意）** |

---

## 核心概念對照

| | CloudTrail | AWS Config |
|--|-----------|-----------|
| 問的問題 | 誰在什麼時間做了什麼？ | 現在的資源設定是否合規？ |
| 資料類型 | API 呼叫事件 log | 資源設定快照 |
| 時間維度 | 事後查詢（Who did what） | 即時評估（Is it compliant now） |
| SOA 考試重點 | Multi-region Trail、CloudWatch 整合 | Managed Rule、Recorder、Delivery Channel |

---

## 設計決策

- **Managed Rules only**：Custom Rule 需要 Lambda，增加複雜度；兩個 managed rules 足以展示 Config 核心概念
- **Management Events only**：Data Events（S3/Lambda）會產生費用，Management Events 已覆蓋考試重點
- **CloudWatch Metric Filter（非 EventBridge）**：SOA 考試最常考此模式，且能展示 CloudTrail → CloudWatch Logs 整合鏈路
- **SNS Email 而非 SQS**：用 email 讓用戶能在 lab 中實際看到告警，加強學習效果
