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
