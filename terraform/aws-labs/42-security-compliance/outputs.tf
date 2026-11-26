output "cloudtrail_bucket" {
  description = "CloudTrail S3 Bucket 名稱"
  value       = aws_s3_bucket.cloudtrail.id
}

output "config_bucket" {
  description = "AWS Config Snapshot S3 Bucket 名稱"
  value       = aws_s3_bucket.config.id
}

output "guardduty_detector_id" {
  description = "GuardDuty Detector ID"
  value       = aws_guardduty_detector.main.id
}

output "sns_topic_arn" {
  description = "Security Alerts SNS Topic ARN"
  value       = aws_sns_topic.security.arn
}

output "check_config_compliance" {
  description = "查詢 Config Rules 合規狀態"
  value       = "aws configservice get-compliance-summary-by-config-rule --query 'ComplianceSummariesByConfigRule[*].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}' --output table"
}

output "check_config_violations" {
  description = "列出不合規的 Config Rules"
  value       = "aws configservice describe-compliance-by-config-rule --compliance-types NON_COMPLIANT --query 'ComplianceByConfigRules[*].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}' --output table"
}

output "check_guardduty_findings" {
  description = "列出 GuardDuty Findings（初始可能為空）"
  value       = "aws guardduty list-findings --detector-id ${aws_guardduty_detector.main.id} --finding-criteria '{\"Criterion\":{\"severity\":{\"Gte\":4}}}' --output text"
}

output "lookup_cloudtrail_events" {
  description = "查詢 CloudTrail 最近 10 筆事件"
  value       = "aws cloudtrail lookup-events --max-results 10 --query 'Events[*].{Time:EventTime,User:Username,Event:EventName,Source:EventSource}' --output table"
}

output "lookup_root_events" {
  description = "查詢 CloudTrail 中的 Root 帳號活動"
  value       = "aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=root --max-results 10 --output table"
}

output "check_alarm_status" {
  description = "查詢所有安全告警狀態"
  value       = "aws cloudwatch describe-alarms --alarm-name-prefix ${var.project} --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' --output table"
}

output "config_console_url" {
  description = "AWS Config Console 直連 URL"
  value       = "https://${var.region}.console.aws.amazon.com/config/home?region=${var.region}#/dashboard"
}

output "guardduty_console_url" {
  description = "GuardDuty Console 直連 URL"
  value       = "https://${var.region}.console.aws.amazon.com/guardduty/home?region=${var.region}#/findings"
}

output "cloudtrail_console_url" {
  description = "CloudTrail Console 直連 URL"
  value       = "https://${var.region}.console.aws.amazon.com/cloudtrail/home?region=${var.region}#/events"
}
