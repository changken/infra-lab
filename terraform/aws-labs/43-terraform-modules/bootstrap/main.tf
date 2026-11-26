# Bootstrap：建立 S3 Remote State Backend + DynamoDB Lock Table
#
# ⚠️ 本 config 使用 local backend（不能用自己尚未建立的 S3 存自己的 state）
# 完成後把 output 的 bucket/table 名稱填入上層目錄的 terraform.tf
#
# 使用順序：
#   1. cd bootstrap && terraform init
#   2. terraform apply -auto-approve
#   3. terraform output backend_config  →  複製內容到 ../terraform.tf
#   4. cd .. && terraform init -migrate-state

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "tf-lab"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket：存放 terraform.tfstate（加密 + 版本控制）
resource "aws_s3_bucket" "state" {
  bucket        = "${var.project}-state-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # state 版本控制：萬一誤操作可回滾
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table：state lock（防止多人同時 apply 導致 state 損壞）
resource "aws_dynamodb_table" "lock" {
  name         = "${var.project}-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S" # Terraform 固定使用 LockID 作為鎖定 key
  }
}

output "state_bucket_name" {
  description = "S3 State Bucket 名稱"
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "DynamoDB Lock Table 名稱"
  value       = aws_dynamodb_table.lock.id
}

output "backend_config" {
  description = "複製此輸出到上層 terraform.tf 的 backend 區塊（取代 TODO 5 的範例）"
  value       = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.state.id}"
      key            = "43-terraform-modules/terraform.tfstate"
      region         = "${var.region}"
      dynamodb_table = "${aws_dynamodb_table.lock.id}"
      encrypt        = true
    }
  EOT
}
