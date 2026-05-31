#==============================================================
# 場景：安全合規架構
#
# 三條安全監控管線，全部匯集到 SNS 通知：
#
#   ┌─── CloudTrail ──────────────────────────────────┐
#   │  所有 API 呼叫 → S3 Bucket（稽核留存）          │
#   │               → CloudWatch Logs                 │
#   │                    └─ Metric Filters → Alarms ──┼──┐
#   └──────────────────────────────────────────────────┘  │
#                                                          │
#   ┌─── AWS Config ──────────────────────────────────┐   │
#   │  持續掃描資源合規狀態                            │   │
#   │  Config Rules（Managed）：                       │   │
#   │    ・S3 public read 禁止                         │   │
#   │    ・Root MFA 啟用                               │   │
#   │    ・IAM 密碼政策                                │   │
#   │  NON_COMPLIANT → EventBridge → SNS ─────────────┼──┤
#   └──────────────────────────────────────────────────┘  │
#                                                          │
#   ┌─── GuardDuty ───────────────────────────────────┐   │
#   │  ML 威脅偵測（異常 API 行為、惡意 IP、等等）    │   │
#   │  Finding (severity ≥ 4) → EventBridge → SNS ───┼──┤
#   └──────────────────────────────────────────────────┘  │
#                                                          ▼
#                                               SNS Topic → Email（optional）
#
# 與 Lab 35 的差異（面試常考）：
#   Lab 35：Config + CloudTrail + SNS（直接通知）
#   Lab 42：加入 GuardDuty + EventBridge 路由 + CIS Benchmark Metric Filters
#           EventBridge 讓多個安全服務的事件統一匯集到單一通知管道
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：Data Sources + 唯一名稱後綴
data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}


#--------------------------------------------------------------
# TODO 1: CloudTrail（S3 + IAM + CloudWatch Logs + Trail）
#--------------------------------------------------------------
# 文件 (cloudtrail):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail
# 文件 (bucket):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
# 文件 (log_group):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group
#
# [S3 Bucket for CloudTrail Logs]
#   bucket        = "${var.project}-cloudtrail-${random_id.suffix.hex}"
#   force_destroy = true   ← lab 結束才能 destroy
#   tags          = local.common_tags
#
# [S3 Public Access Block]（CloudTrail log 絕對不能公開）
#   block_public_acls = block_public_policy = ignore_public_acls = restrict_public_buckets = true
#
# [S3 Bucket Policy]（允許 CloudTrail service 寫入）
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid       = "AWSCloudTrailAclCheck"
#         Effect    = "Allow"
#         Principal = { Service = "cloudtrail.amazonaws.com" }
#         Action    = "s3:GetBucketAcl"
#         Resource  = aws_s3_bucket.cloudtrail.arn
#         Condition = { StringEquals = {
#           "AWS:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-trail"
#         }}
#       },
#       {
#         Sid       = "AWSCloudTrailWrite"
#         Effect    = "Allow"
#         Principal = { Service = "cloudtrail.amazonaws.com" }
#         Action    = "s3:PutObject"
#         Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
#         Condition = { StringEquals = {
#           "s3:x-amz-acl" = "bucket-owner-full-control"
#           "AWS:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-trail"
#         }}
#       }
#     ]
#   })
#
# [CloudWatch Log Group for CloudTrail]
#   name              = "/aws/cloudtrail/${var.project}"
#   retention_in_days = 90   ← CIS Benchmark 要求 90 天以上
#   tags              = local.common_tags
#
# [IAM Role for CloudTrail → CloudWatch Logs]
#   name = "${var.project}-cloudtrail-role"
#   assume_role_policy: Principal.Service = "cloudtrail.amazonaws.com"
#
#   Inline Policy（CloudTrail 只需要 CreateLogStream + PutLogEvents）：
#   Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
#   Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
#
# [CloudTrail]
#   name                          = "${var.project}-trail"
#   s3_bucket_name                = aws_s3_bucket.cloudtrail.id
#   include_global_service_events = true    ← 包含 IAM, STS, Route53（全球服務）
#   is_multi_region_trail         = true    ← CIS Benchmark 要求
#   enable_log_file_validation    = true    ← 防止日誌被竄改（Log File Integrity Validation）
#   cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
#   cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn
#   tags                          = local.common_tags
#
# ⚠️ 注意：
#   - S3 bucket policy 必須在 trail 建立前套用（加 depends_on）
#   - cloud_watch_logs_group_arn 結尾需要 ":*"（非 ARN 的完整 log group ARN）
#   - is_multi_region_trail = true 代表只需 1 個 trail 就能涵蓋所有 region

resource "aws_s3_bucket" "cloudtrail" {
  # TODO
  bucket        = "${var.project}-cloudtrail-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  # TODO
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  # TODO
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = { StringEquals = {
          "AWS:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-trail"
        } }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = {
          "s3:x-amz-acl"  = "bucket-owner-full-control"
          "AWS:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-trail"
        } }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  # TODO
  name              = "/aws/cloudtrail/${var.project}"
  retention_in_days = 90
  tags              = local.common_tags
}

resource "aws_iam_role" "cloudtrail" {
  # TODO
  name = "${var.project}-cloudtrail-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  # TODO
  name = "${var.project}-cloudtrail-logs"
  role = aws_iam_role.cloudtrail.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  # TODO
  name                          = "${var.project}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn
  tags                          = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: AWS Config（S3 + IAM + Recorder + Channel + Status）
#--------------------------------------------------------------
# 文件 (recorder): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder
# 文件 (channel):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_delivery_channel
# 文件 (status):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder_status
#
# ⚠️ 注意：AWS Config 需要三個 Terraform 資源，有嚴格的建立順序：
#   1. aws_config_configuration_recorder（設定要記錄什麼）
#   2. aws_config_delivery_channel（設定送到哪裡）→ depends_on [recorder]
#   3. aws_config_configuration_recorder_status（啟動錄製）→ depends_on [channel]
#   若順序錯誤會出現 "there is no delivery channel available" 錯誤
#
# [S3 Bucket for Config Snapshots]
#   bucket        = "${var.project}-config-${random_id.suffix.hex}"
#   force_destroy = true
#
# [S3 Bucket Policy for Config]
#   Statement = [
#     AWSConfigBucketPermissionsCheck: s3:GetBucketAcl
#     AWSConfigBucketExistenceCheck:   s3:ListBucket
#     AWSConfigBucketDelivery:         s3:PutObject to /AWSLogs/{account}/Config/*
#   ]
#   （三條 statement 都用 Principal.Service = "config.amazonaws.com"）
#
# [IAM Role for Config]
#   name = "${var.project}-config-role"
#   assume_role_policy: Principal.Service = "config.amazonaws.com"
#
#   Policy Attachment（AWSConfigRole 包含 Describe 所有資源的權限）：
#   arn:aws:iam::aws:policy/service-role/AWSConfigRole
#
#   Inline Policy（S3 寫入）：
#   Action   = "s3:PutObject"
#   Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
#
# [Configuration Recorder]
#   name     = "default"   ← 名稱固定為 "default"
#   role_arn = aws_iam_role.config.arn
#
#   recording_group {
#     all_supported                 = true    ← 記錄所有支援的資源類型
#     include_global_resource_types = true    ← 包含 IAM, Route53 等全球資源
#   }
#
# [Delivery Channel]
#   name           = "default"
#   s3_bucket_name = aws_s3_bucket.config.id
#   depends_on     = [aws_config_configuration_recorder.main]
#
#   snapshot_delivery_properties {
#     delivery_frequency = "TwentyFour_Hours"   ← 每天快照一次
#   }
#
# [Recorder Status]（啟動錄製 — 開始計費！）
#   name       = aws_config_configuration_recorder.main.name
#   is_enabled = true
#   depends_on = [aws_config_delivery_channel.main]

resource "aws_s3_bucket" "config" {
  # TODO
  bucket        = "${var.project}-config-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "config" {
  # TODO
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config" {
  # TODO
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
        Effect   = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      },
      {
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Effect   = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "config" {
  # TODO
  name = "${var.project}-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config_role" {
  # TODO
  role       = aws_iam_role.config.name
  # ⚠️ AWSConfigRole 已廢棄，正確名稱為 AWS_ConfigRole
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  # TODO
  name = "${var.project}-config-s3"
  role = aws_iam_role.config.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "main" {
  # TODO
  name     = "default"
  role_arn = aws_iam_role.config.arn
  recording_group {
    # TODO
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  # TODO
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.id

  snapshot_delivery_properties {
    # TODO
    delivery_frequency = "TwentyFour_Hours"
  }
}

resource "aws_config_configuration_recorder_status" "main" {
  # TODO
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}


#--------------------------------------------------------------
# TODO 3: AWS Config Rules（Managed Rules × 3）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_config_rule
# 所有 Managed Rule 清單: https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html
#
# ⚠️ 注意：Config Rules 必須在 recorder 啟動後才能建立
#   depends_on = [aws_config_configuration_recorder_status.main]
#
# [Rule 1: S3 公開讀取禁止]（CIS Benchmark 2.1.5）
#   name = "s3-bucket-public-read-prohibited"
#   source {
#     owner             = "AWS"
#     source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
#   }
#
# [Rule 2: Root 帳號啟用 MFA]（CIS Benchmark 1.5）
#   name = "root-account-mfa-enabled"
#   source {
#     owner             = "AWS"
#     source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
#   }
#
# [Rule 3: IAM 密碼政策]（CIS Benchmark 1.8-1.11）
#   name = "iam-password-policy"
#   source {
#     owner             = "AWS"
#     source_identifier = "IAM_PASSWORD_POLICY"
#   }
#
#   input_parameters = jsonencode({
#     RequireUppercaseCharacters = "true"
#     RequireLowercaseCharacters = "true"
#     RequireSymbols             = "true"
#     RequireNumbers             = "true"
#     MinimumPasswordLength      = "14"
#     PasswordReusePrevention    = "24"
#     MaxPasswordAge             = "90"
#   })
#
# ⚠️ 注意：
#   - source_identifier 是全大寫加底線的格式（與 AWS console 顯示的 rule id 對應）
#   - ROOT_ACCOUNT_MFA_ENABLED 通常立刻回報 NON_COMPLIANT（除非你真的有 root MFA）
#   - 這三條規則涵蓋 CIS AWS Foundations Benchmark 中最基礎的合規要求

resource "aws_config_config_rule" "s3_public_read" {
  # TODO
  name = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "root_mfa" {
  # TODO
  name = "root-account-mfa-enabled"
  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "iam_password_policy" {
  # TODO
  name = "iam-password-policy"
  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }
  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols             = "true"
    RequireNumbers             = "true"
    MinimumPasswordLength      = "14"
    PasswordReusePrevention    = "24"
    MaxPasswordAge             = "90"
  })
  depends_on = [aws_config_configuration_recorder_status.main]
}


#--------------------------------------------------------------
# TODO 4: GuardDuty + SNS Topic + SNS Topic Policy
#--------------------------------------------------------------
# 文件 (guardduty): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector
# 文件 (sns):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
# 文件 (policy):    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy
#
# [GuardDuty Detector]（啟用威脅偵測）
#   enable = true
#   tags   = local.common_tags
#
#   ⚠️ GuardDuty 費用：首 30 天免費試用。試用後依分析的 CloudTrail 事件量計費。
#      LAB 結束後記得 destroy，否則 30 天後開始收費。
#
# [SNS Topic]
#   name = "${var.project}-security-alerts"
#   tags = local.common_tags
#
# [SNS Topic Subscription]（條件建立）
#   count     = var.notification_email != "" ? 1 : 0
#   topic_arn = aws_sns_topic.security.arn
#   protocol  = "email"
#   endpoint  = var.notification_email
#
# [SNS Topic Policy]（允許 EventBridge 和 CloudWatch 發布訊息）
#   ⚠️ 注意：預設 SNS policy 只允許帳號 owner。EventBridge 路由 → SNS 需要明確授權。
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "AllowAccountOwner"
#         Effect = "Allow"
#         Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
#         Action   = "sns:*"
#         Resource = aws_sns_topic.security.arn
#       },
#       {
#         Sid    = "AllowEventBridgePublish"
#         Effect = "Allow"
#         Principal = { Service = "events.amazonaws.com" }
#         Action   = "sns:Publish"
#         Resource = aws_sns_topic.security.arn
#       },
#       {
#         Sid    = "AllowCloudWatchPublish"
#         Effect = "Allow"
#         Principal = { Service = "cloudwatch.amazonaws.com" }
#         Action   = "sns:Publish"
#         Resource = aws_sns_topic.security.arn
#       }
#     ]
#   })

resource "aws_guardduty_detector" "main" {
  # TODO
  enable = true
  tags   = local.common_tags
}

resource "aws_sns_topic" "security" {
  # TODO
  name = "${var.project}-security-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  # TODO（記得加 count）
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_policy" "security" {
  # TODO
  arn = aws_sns_topic.security.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountOwner"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        # ⚠️ sns:* 在 Topic Policy 中無效（CreateTopic 等帳號層級操作不能套用在 topic resource）
        # ⚠️ sns:Unsubscribe 是 subscription 層級 action（ARN 格式為 topic:subscription），
        #   不能用於 topic ARN，否則觸發 "out of service scope" 錯誤
        Action = [
          "sns:Publish",
          "sns:Subscribe",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:ListSubscriptionsByTopic",
        ]
        Resource  = aws_sns_topic.security.arn
      },
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.security.arn
      }
      # ⚠️ 注意：cloudwatch.amazonaws.com 不支援 SNS Topic Policy 直接授權。
      #   CloudWatch Alarm → SNS 使用帳號層級的 IAM 權限，無需在 Topic Policy 中明確允許。
    ]
  })
}


#--------------------------------------------------------------
# TODO 5: EventBridge Rules（安全事件路由到 SNS）
#--------------------------------------------------------------
# 文件 (rule):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule
# 文件 (target): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target
#
# [Rule 1: Config NON_COMPLIANT → SNS]
#   name        = "${var.project}-config-noncompliant"
#   description = "Route Config compliance violations to SNS"
#
#   event_pattern = jsonencode({
#     source      = ["aws.config"]
#     detail-type = ["Config Rules Compliance Change"]
#     detail = {
#       newEvaluationResult = {
#         complianceType = ["NON_COMPLIANT"]   ← 只路由不合規事件，COMPLIANT 不通知
#       }
#     }
#   })
#   tags = local.common_tags
#
#   Target: SNS
#     rule      = aws_cloudwatch_event_rule.config_noncompliant.name
#     target_id = "ConfigNonCompliantSNS"
#     arn       = aws_sns_topic.security.arn
#
# [Rule 2: GuardDuty High/Medium Finding → SNS]
#   name = "${var.project}-guardduty-finding"
#
#   event_pattern = jsonencode({
#     source      = ["aws.guardduty"]
#     detail-type = ["GuardDuty Finding"]
#     detail = {
#       severity = [{ numeric = [">=", 4] }]   ← Medium(4), High(7), Critical(9)
#       # Low(1-3) 不通知，避免告警疲勞
#     }
#   })
#
#   Target: SNS
#     rule      = aws_cloudwatch_event_rule.guardduty_finding.name
#     target_id = "GuardDutyFindingSNS"
#     arn       = aws_sns_topic.security.arn
#
# ⚠️ 注意：
#   - EventBridge Target 指向 SNS 需要 SNS Topic Policy 允許（TODO 4 已設定）
#   - GuardDuty severity: Low=1-3, Medium=4-6, High=7-8, Critical=9-10

resource "aws_cloudwatch_event_rule" "config_noncompliant" {
  # TODO
  name        = "${var.project}-config-noncompliant"
  description = "Route Config compliance violations to SNS"
  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "config_sns" {
  # TODO
  rule      = aws_cloudwatch_event_rule.config_noncompliant.name
  target_id = "ConfigNonCompliantSNS"
  arn       = aws_sns_topic.security.arn
}

resource "aws_cloudwatch_event_rule" "guardduty_finding" {
  # TODO
  name        = "${var.project}-guardduty-finding"
  description = "Route GuardDuty high/medium findings to SNS"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }] # Medium(4), High(7), Critical(9)
    }
  })
  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  # TODO
  rule      = aws_cloudwatch_event_rule.guardduty_finding.name
  target_id = "GuardDutyFindingSNS"
  arn       = aws_sns_topic.security.arn
}


#--------------------------------------------------------------
# TODO 6: CloudWatch Metric Filters + Alarms（CIS Benchmark）
#--------------------------------------------------------------
# 文件 (filter): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter
# 文件 (alarm):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
# CIS 參考:      https://docs.aws.amazon.com/securityhub/latest/userguide/cloudtrail-controls.html
#
# 原理：CloudTrail logs → CloudWatch Logs → Metric Filter → Metric → Alarm → SNS
# 每個 filter 監控一種高風險操作，超過閾值就觸發告警
#
# [Filter 1: Root 帳號使用]（CIS 1.1）
#   name           = "${var.project}-root-usage"
#   log_group_name = aws_cloudwatch_log_group.cloudtrail.name
#   pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
#   metric_transformation {
#     name      = "RootUsageCount"
#     namespace = "SecurityMetrics/${var.project}"
#     value     = "1"
#     default_value = "0"
#   }
#
# [Alarm 1: Root 使用即告警]
#   alarm_name          = "${var.project}-root-usage"
#   namespace           = "SecurityMetrics/${var.project}"
#   metric_name         = "RootUsageCount"
#   period              = 300
#   evaluation_periods  = 1
#   threshold           = 1    ← 任何一次 root 使用都告警
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   statistic           = "Sum"
#   treat_missing_data  = "notBreaching"
#   alarm_actions       = [aws_sns_topic.security.arn]
#
# [Filter 2: 未授權 API 呼叫]（CIS 3.1）
#   pattern = "{ ($.errorCode = \"AccessDenied\") || ($.errorCode = \"UnauthorizedOperation\") }"
#   metric_transformation: name = "UnauthorizedApiCallCount"
#
# [Alarm 2]
#   metric_name = "UnauthorizedApiCallCount"
#   threshold   = 5    ← 5 分鐘內超過 5 次才告警（避免正常偶發 AccessDenied 誤報）
#
# [Filter 3: IAM 政策變更]（CIS 3.4）
#   pattern = "{ ($.eventName = PutUserPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) }"
#   metric_transformation: name = "IamPolicyChangeCount"
#
# [Alarm 3]
#   metric_name = "IamPolicyChangeCount"
#   threshold   = 1    ← IAM 政策任何變更即告警（高風險操作）
#
# ⚠️ 注意：
#   - CloudTrail 必須設定 cloud_watch_logs_group_arn 才能讓 Metric Filter 工作（TODO 1）
#   - filter pattern 使用 CloudWatch Logs Insights 過濾語法（不是 SQL）
#   - alarm 的 namespace 和 metric_name 必須與 filter 的 metric_transformation 完全一致

resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  # TODO
  name           = "${var.project}-root-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
  metric_transformation {
    name          = "RootUsageCount"
    namespace     = "SecurityMetrics/${var.project}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  # TODO
  alarm_name          = "${var.project}-root-usage"
  namespace           = "SecurityMetrics/${var.project}"
  metric_name         = "RootUsageCount"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]
}

resource "aws_cloudwatch_log_metric_filter" "unauthorized_api" {
  # TODO
  name           = "${var.project}-unauthorized-api"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"AccessDenied\" ) || ($.errorCode = \"UnauthorizedOperation\" ) }"
  metric_transformation {
    name          = "UnauthorizedApiCallCount"
    namespace     = "SecurityMetrics/${var.project}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api" {
  # TODO
  alarm_name          = "${var.project}-unauthorized-api"
  namespace           = "SecurityMetrics/${var.project}"
  metric_name         = "UnauthorizedApiCallCount"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]
}

resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  # TODO
  name           = "${var.project}-iam-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = PutUserPolicy ) || ($.eventName = PutRolePolicy ) || ($.eventName = AttachRolePolicy ) || ($.eventName = DetachRolePolicy ) || ($.eventName = AttachUserPolicy ) || ($.eventName = DetachUserPolicy ) }"
  metric_transformation {
    name          = "IamPolicyChangeCount"
    namespace     = "SecurityMetrics/${var.project}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  # TODO
  alarm_name          = "${var.project}-iam-changes"
  namespace           = "SecurityMetrics/${var.project}"
  metric_name         = "IamPolicyChangeCount"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]
}
