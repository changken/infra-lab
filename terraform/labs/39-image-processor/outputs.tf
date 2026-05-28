output "input_bucket_name" {
  description = "S3 Input Bucket 名稱（上傳圖片用）"
  value       = aws_s3_bucket.input.id
}

output "output_bucket_name" {
  description = "S3 Output Bucket 名稱（處理後圖片）"
  value       = aws_s3_bucket.output.id
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution Domain（存取處理後圖片）"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "eventbridge_rule_name" {
  description = "EventBridge Rule 名稱"
  value       = aws_cloudwatch_events_rule.s3_upload.name
}

output "upload_command" {
  description = "上傳測試圖片的 AWS CLI 指令"
  value       = "aws s3 cp <your-image.jpg> s3://${aws_s3_bucket.input.id}/test-image.jpg"
}

output "verify_output_command" {
  description = "確認 Lambda 已處理並寫入 Output Bucket 的指令"
  value       = "aws s3 ls s3://${aws_s3_bucket.output.id}/processed/ --recursive"
}

output "cloudfront_image_url_example" {
  description = "透過 CloudFront 存取處理後圖片的 URL 範例"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/processed/test-image.jpg"
}

output "eventbridge_events_command" {
  description = "查詢 EventBridge Rule 過去觸發次數的 CLI 指令"
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name TriggeredRules --dimensions Name=RuleName,Value=${aws_cloudwatch_events_rule.s3_upload.name} --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ') --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') --period 3600 --statistics Sum"
}
