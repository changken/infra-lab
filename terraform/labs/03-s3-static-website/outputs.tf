#--------------------------------------------------------------
# Outputs
#--------------------------------------------------------------

output "bucket_name" {
  description = "The S3 bucket name (globally unique)"
  value       = aws_s3_bucket.site.id
}

# TODO: bucket_arn
#   提示：aws_s3_bucket.site.arn

# TODO: website_endpoint
#   提示：aws_s3_bucket_website_configuration.site.website_endpoint
#   這是最重要的 output — apply 完直接複製去瀏覽器開

# TODO: website_url
#   把 endpoint 包成 http://... 方便點擊
#   提示：value = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.site.arn
}

output "website_endpoint" {
  description = "The endpoint for the static website"
  value       = aws_s3_bucket_website_configuration.site.website_endpoint
}

output "website_url" {
  description = "The URL for the static website"
  value       = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"
}