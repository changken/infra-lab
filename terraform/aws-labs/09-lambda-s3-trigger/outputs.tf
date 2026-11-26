output "bucket_name" {
  description = "S3 bucket to upload files to"
  value       = aws_s3_bucket.upload.bucket
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.processor.function_name
}

# TODO: upload_command
#   提示：用 format() 組出測試用的 aws s3 cp 指令：
#   "echo 'hello terraform' > /tmp/test.txt && aws s3 cp /tmp/test.txt s3://%s/uploads/test.txt"
#   引數：aws_s3_bucket.upload.bucket

output "upload_command" {
  description = "Example command to upload a file to S3 and trigger Lambda"
  value = format(
    "echo 'hello terraform' > /tmp/test.txt && aws s3 cp /tmp/test.txt s3://%s/uploads/test.txt",
    aws_s3_bucket.upload.bucket
  )
}