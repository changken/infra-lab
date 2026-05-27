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
