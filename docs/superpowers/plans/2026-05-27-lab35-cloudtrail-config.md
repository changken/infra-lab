# Lab 35: CloudTrail + Config Rules + SNS 合規告警 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `terraform/labs/35-cloudtrail-config/` 填空式骨架，讓用戶透過 6 個 TODO 學習 CloudTrail → CloudWatch Logs → SNS 合規告警鏈路 + AWS Config Managed Rules。

**Architecture:** CloudTrail 記錄 Management Events 同時送至 S3 和 CloudWatch Logs。CloudWatch Metric Filters 偵測 root login 和 SG 變更，觸發 CloudWatch Alarms → SNS Email 告警。AWS Config 並行持續評估 2 個 Managed Rules，快照也送至同一個 S3 Bucket。

**Tech Stack:** Terraform >= 1.0, AWS Provider ~> 5.0（CloudTrail, CloudWatch Logs, SNS, AWS Config, S3, IAM）

---

### Task 1: 建立目錄骨架（terraform.tf / variables.tf / locals.tf / .gitignore / tfvars.example）

**Files:**
- Create: `terraform/labs/35-cloudtrail-config/terraform.tf`
- Create: `terraform/labs/35-cloudtrail-config/variables.tf`
- Create: `terraform/labs/35-cloudtrail-config/locals.tf`
- Create: `terraform/labs/35-cloudtrail-config/terraform.tfvars.example`
- Create: `terraform/labs/35-cloudtrail-config/.gitignore`

- [ ] **Step 1: 建立 terraform.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 2: 建立 variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "cloudtrail-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "Email address for security alert notifications"
  type        = string
}
```

- [ ] **Step 3: 建立 locals.tf**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "35-cloudtrail-config"
    ManagedBy   = "terraform"
  }
}
```

- [ ] **Step 4: 建立 terraform.tfvars.example**

```
region      = "us-east-1"
project     = "cloudtrail-lab"
environment = "dev"
alert_email = "your-email@example.com"
```

- [ ] **Step 5: 建立 .gitignore**

```
*.tfvars
*.tfstate
*.tfstate.backup
.terraform/
```

- [ ] **Step 6: Commit**

```bash
git add terraform/labs/35-cloudtrail-config/
git commit -m "chore(labs): scaffold lab 35 support files"
```

---

### Task 2: 撰寫 main.tf 填空骨架

**Files:**
- Create: `terraform/labs/35-cloudtrail-config/main.tf`

- [ ] **Step 1: 建立 main.tf**

Write the following content to `terraform/labs/35-cloudtrail-config/main.tf`:

```hcl
#==============================================================
# 學習目標：CloudTrail + Config Rules + SNS 合規告警
#
# 核心問題：如何同時達成「事件稽核」和「持續合規評估」？
#
# CloudTrail vs AWS Config（面試必考）：
#   CloudTrail  → 記錄 API 呼叫，回答「誰在什麼時間做了什麼」（事後稽核）
#   AWS Config  → 持續評估資源設定，回答「現在是否符合合規政策」（即時狀態）
#
# 本 lab 的資料流：
#   CloudTrail → S3（長期保存）
#              → CloudWatch Log Group → Metric Filter → Alarm → SNS → Email
#   Config     → S3（設定快照）→ Config Rules（持續評估）
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：取得目前 AWS 帳號 ID（S3 Bucket 命名和 Bucket Policy 必要）
data "aws_caller_identity" "current" {}


#--------------------------------------------------------------
# TODO 1: S3 Bucket + Bucket Policy（CloudTrail + Config 共用）
#--------------------------------------------------------------
# 文件 (bucket):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
# 文件 (bucket_policy): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
# 文件 (public_access): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
#
# [S3 Bucket]
#   bucket        = "${var.project}-logs-${data.aws_caller_identity.current.account_id}"
#   force_destroy = true   # lab 環境允許刪除非空 bucket
#   tags          = local.common_tags
#
# [S3 Public Access Block]（強制封鎖所有公開存取）
#   bucket                  = aws_s3_bucket.cloudtrail.id
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
#
# [S3 Bucket Policy]（允許 CloudTrail 和 Config 服務寫入，格式固定）
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       { Sid="AWSCloudTrailAclCheck", Principal={Service="cloudtrail.amazonaws.com"},
#         Action="s3:GetBucketAcl", Resource=aws_s3_bucket.cloudtrail.arn },
#       { Sid="AWSCloudTrailWrite", Principal={Service="cloudtrail.amazonaws.com"},
#         Action="s3:PutObject",
#         Resource="${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
#         Condition={StringEquals={"s3:x-amz-acl"="bucket-owner-full-control"}} },
#       { Sid="AWSConfigAclCheck", Principal={Service="config.amazonaws.com"},
#         Action="s3:GetBucketAcl", Resource=aws_s3_bucket.cloudtrail.arn },
#       { Sid="AWSConfigWrite", Principal={Service="config.amazonaws.com"},
#         Action="s3:PutObject",
#         Resource="${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*",
#         Condition={StringEquals={"s3:x-amz-acl"="bucket-owner-full-control"}} }
#     ]
#   })
#
# ⚠️ 注意：Bucket Policy 是 CloudTrail 和 Config 能否寫入的關鍵
#          缺少任何一條 Statement 會導致 Trail 建立或 Config Delivery Channel 失敗

resource "aws_s3_bucket" "cloudtrail" {
  # TODO
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  # TODO
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: CloudWatch Log Group + CloudTrail IAM Role + Trail
#--------------------------------------------------------------
# 文件 (log_group):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group
# 文件 (iam_role):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (cloudtrail): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail
#
# [CloudWatch Log Group]
#   name              = "/aws/cloudtrail/${var.project}"
#   retention_in_days = 7
#   tags              = local.common_tags
#
# [IAM Role（CloudTrail → CloudWatch Logs 寫入權限）]
#   name = "${var.project}-cloudtrail-role"
#   assume_role_policy: Principal.Service = "cloudtrail.amazonaws.com"
#
# [IAM Role Inline Policy]
#   Actions:  ["logs:CreateLogStream", "logs:PutLogEvents"]
#   Resource: "${aws_cloudwatch_log_group.cloudtrail.arn}:*"   ← 注意尾端 :*
#
# [CloudTrail]
#   name                          = "${var.project}-trail"
#   s3_bucket_name                = aws_s3_bucket.cloudtrail.id
#   is_multi_region_trail         = true
#   enable_log_file_validation    = true
#   include_global_service_events = true
#   cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"  ← 注意 :*
#   cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn
#   tags                          = local.common_tags
#
#   event_selector {
#     read_write_type           = "All"
#     include_management_events = true
#   }
#
# ⚠️ 注意：cloud_watch_logs_group_arn 和 IAM Policy Resource 都需要 :* 後綴
#          沒有 :* 會導致 CloudTrail apply 失敗或無法寫入 Logs

resource "aws_cloudwatch_log_group" "cloudtrail" {
  # TODO
}

resource "aws_iam_role" "cloudtrail" {
  # TODO
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  # TODO
}

resource "aws_cloudtrail" "main" {
  # TODO

  event_selector {
    # TODO
  }
}


#--------------------------------------------------------------
# TODO 3: CloudWatch Log Metric Filters（偵測特定 API 事件）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter
#
# [Filter 1: Root 帳號登入偵測]
#   name           = "${var.project}-root-login"
#   log_group_name = aws_cloudwatch_log_group.cloudtrail.name
#   pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
#
#   metric_transformation {
#     name          = "RootLoginCount"
#     namespace     = "${var.project}/SecurityMetrics"
#     value         = "1"
#     default_value = "0"
#   }
#
# [Filter 2: Security Group 變更偵測]
#   name           = "${var.project}-sg-change"
#   log_group_name = aws_cloudwatch_log_group.cloudtrail.name
#   pattern        = "{ $.eventName = \"AuthorizeSecurityGroupIngress\" || $.eventName = \"AuthorizeSecurityGroupEgress\" || $.eventName = \"RevokeSecurityGroupIngress\" || $.eventName = \"CreateSecurityGroup\" || $.eventName = \"DeleteSecurityGroup\" }"
#
#   metric_transformation {
#     name          = "SecurityGroupChangeCount"
#     namespace     = "${var.project}/SecurityMetrics"   ← 與 Filter 1 相同 namespace
#     value         = "1"
#     default_value = "0"
#   }
#
# ⚠️ 注意：pattern 格式嚴格，{ } 和引號都不能省略，大小寫敏感
#          namespace 必須在 Metric Filter 和 Alarm 之間完全一致

resource "aws_cloudwatch_log_metric_filter" "root_login" {
  # TODO
}

resource "aws_cloudwatch_log_metric_filter" "sg_change" {
  # TODO
}


#--------------------------------------------------------------
# TODO 4: CloudWatch Metric Alarms（閾值觸發 SNS 告警）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
#
# [Alarm 1: Root 登入告警]
#   alarm_name          = "${var.project}-root-login-alarm"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = "RootLoginCount"                    ← 必須和 Filter 1 的 name 完全一致
#   namespace           = "${var.project}/SecurityMetrics"    ← 必須和 Filter 1 一致
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1
#   alarm_actions       = [aws_sns_topic.alerts.arn]
#   treat_missing_data  = "notBreaching"
#   tags                = local.common_tags
#
# [Alarm 2: Security Group 變更告警]
#   alarm_name  = "${var.project}-sg-change-alarm"
#   metric_name = "SecurityGroupChangeCount"                  ← 對應 Filter 2
#   （其餘設定與 Alarm 1 相同）
#
# ⚠️ 注意：metric_name 和 namespace 必須和 metric_transformation 完全一致
#          任何拼字或大小寫差異都會導致 Alarm 永遠不觸發

resource "aws_cloudwatch_metric_alarm" "root_login" {
  # TODO
}

resource "aws_cloudwatch_metric_alarm" "sg_change" {
  # TODO
}


#--------------------------------------------------------------
# TODO 5: SNS Topic + Email 訂閱（接收告警通知）
#--------------------------------------------------------------
# 文件 (topic):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
# 文件 (subscription): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# [SNS Topic]
#   name = "${var.project}-security-alerts"
#   tags = local.common_tags
#
# [Email 訂閱]
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "email"
#   endpoint  = var.alert_email
#
# ⚠️ 注意：Email 訂閱建立後，收件人需手動點擊確認連結
#          在確認前，SNS 不會發送任何告警郵件（狀態：PendingConfirmation）
#          apply 後請立即查收確認信

resource "aws_sns_topic" "alerts" {
  # TODO
}

resource "aws_sns_topic_subscription" "email" {
  # TODO
}


#--------------------------------------------------------------
# TODO 6: AWS Config（Recorder + Delivery Channel + Managed Rules）
#--------------------------------------------------------------
# 文件 (iam_role):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (recorder):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder
# 文件 (status):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder_status
# 文件 (channel):    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_delivery_channel
# 文件 (rule):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_rule
#
# [IAM Role for Config]
#   name = "${var.project}-config-role"
#   assume_role_policy: Principal.Service = "config.amazonaws.com"
#   attach managed policy: "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
#
# [Configuration Recorder]
#   name     = "${var.project}-recorder"
#   role_arn = aws_iam_role.config.arn
#   recording_group {
#     all_supported                 = true
#     include_global_resource_types = true
#   }
#
# [Delivery Channel]
#   name           = "${var.project}-delivery-channel"
#   s3_bucket_name = aws_s3_bucket.cloudtrail.id
#   depends_on     = [aws_config_configuration_recorder.main]
#
# [Recorder Status]（啟動錄製，必須在 Delivery Channel 之後）
#   name       = aws_config_configuration_recorder.main.name
#   is_enabled = true
#   depends_on = [aws_config_delivery_channel.main]
#
# [Config Rule 1: S3 不允許公開寫入]
#   name = "s3-bucket-public-write-prohibited"
#   source { owner = "AWS", source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED" }
#   depends_on = [aws_config_configuration_recorder_status.main]
#
# [Config Rule 2: CloudTrail 必須啟用]
#   name = "cloud-trail-enabled"
#   source { owner = "AWS", source_identifier = "CLOUD_TRAIL_ENABLED" }
#   depends_on = [aws_config_configuration_recorder_status.main]
#
# ⚠️ 注意：depends_on 順序：Recorder → Delivery Channel → Recorder Status → Rules
#          aws_config_configuration_recorder_status 是啟動錄製的關鍵，缺少它 Recorder 不會工作

resource "aws_iam_role" "config" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "config" {
  # TODO
}

resource "aws_config_configuration_recorder" "main" {
  # TODO

  recording_group {
    # TODO
  }
}

resource "aws_config_delivery_channel" "main" {
  # TODO
}

resource "aws_config_configuration_recorder_status" "main" {
  # TODO
}

resource "aws_config_rule" "s3_public_write" {
  # TODO

  source {
    # TODO
  }
}

resource "aws_config_rule" "cloudtrail_enabled" {
  # TODO

  source {
    # TODO
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/35-cloudtrail-config/main.tf
git commit -m "feat(labs): add lab 35 main.tf with TODO scaffolding"
```

---

### Task 3: 撰寫 outputs.tf

**Files:**
- Create: `terraform/labs/35-cloudtrail-config/outputs.tf`

- [ ] **Step 1: 建立 outputs.tf**

```hcl
output "cloudtrail_arn" {
  description = "CloudTrail Trail ARN"
  value       = aws_cloudtrail.main.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group 名稱（可查詢 CloudTrail 事件）"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "sns_topic_arn" {
  description = "SNS Topic ARN（安全告警）"
  value       = aws_sns_topic.alerts.arn
}

output "config_recorder_name" {
  description = "AWS Config Recorder 名稱"
  value       = aws_config_configuration_recorder.main.name
}

output "s3_bucket_name" {
  description = "CloudTrail + Config 共用的 S3 Bucket 名稱"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_lookup_command" {
  description = "查詢最近 CloudTrail 事件的 CLI 指令"
  value       = "aws cloudtrail lookup-events --max-results 5 --region ${var.region}"
}

output "config_compliance_command" {
  description = "查詢 Config 合規狀態的 CLI 指令"
  value       = "aws configservice describe-compliance-by-config-rule --region ${var.region}"
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/35-cloudtrail-config/outputs.tf
git commit -m "feat(labs): add lab 35 outputs.tf"
```

---

### Task 4: 撰寫 README.md

**Files:**
- Create: `terraform/labs/35-cloudtrail-config/README.md`

- [ ] **Step 1: 建立 README.md**

```markdown
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
| 6 | `aws_iam_role` + `aws_iam_role_policy_attachment` + `aws_config_configuration_recorder` + `aws_config_delivery_channel` + `aws_config_configuration_recorder_status` + `aws_config_rule` × 2 | depends_on 順序：Recorder → Channel → Status → Rules |

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
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/35-cloudtrail-config/README.md
git commit -m "docs(labs): add lab 35 README with verification guide"
```

---

### Task 5: 執行 terraform init 產生 lock file

**Files:**
- Create: `terraform/labs/35-cloudtrail-config/.terraform.lock.hcl`

- [ ] **Step 1: 執行 terraform init**

```bash
cd terraform/labs/35-cloudtrail-config
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

- [ ] **Step 2: Commit lock file**

```bash
git add terraform/labs/35-cloudtrail-config/.terraform.lock.hcl
git commit -m "chore(labs): add lab 35 terraform lock file"
```

---

### Task 6: 更新 roadmap 並完成

**Files:**
- Modify: `terraform/docs/roadmap-v2.md`

- [ ] **Step 1: 更新 roadmap-v2.md**

In `terraform/docs/roadmap-v2.md`, find the line:
```
| 35 | `35-cloudtrail-config` | CloudTrail + Config Rules + SNS 合規告警 | < $0.50 | SOA, SAA |
```

Change to:
```
| 35 🚧 | `35-cloudtrail-config` | CloudTrail + Config Rules + SNS 合規告警 | < $0.50 | SOA, SAA |
```

- [ ] **Step 2: Commit**

```bash
git add terraform/docs/roadmap-v2.md
git commit -m "docs(roadmap): mark lab 35 as scaffolded"
```
