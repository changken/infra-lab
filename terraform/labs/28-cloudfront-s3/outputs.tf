output "cloudfront_url" {
  description = "CloudFront Distribution URL"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution domain name (without https)"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "distribution_id" {
  description = "CloudFront Distribution ID（invalidation 時需要）"
  value       = aws_cloudfront_distribution.website.id
}

output "s3_bucket_name" {
  description = "S3 Bucket name"
  value       = aws_s3_bucket.website.id
}

output "s3_bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.website.arn
}
