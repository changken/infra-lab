terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  #--------------------------------------------------------------
  # TODO 5: S3 Remote Backend（在 bootstrap 完成後設定）
  #--------------------------------------------------------------
  # 步驟：
  #   1. cd bootstrap && terraform init && terraform apply -auto-approve
  #   2. terraform output -raw backend_config   ← 複製輸出
  #   3. 取消下方 backend 區塊的註解，填入 bucket / dynamodb_table
  #   4. cd .. && terraform init -migrate-state
  #      （Terraform 會詢問是否遷移 state → 輸入 yes）
  #
  # ⚠️ 注意：
  #   - backend 的值不能使用 var 或資源引用（它在 provider init 之前解析）
  #   - terraform init -migrate-state 把本地 .tfstate 遷移到 S3（不會遺失資源）
  #   - 遷移後，多人協作時 Terraform 會自動用 DynamoDB 加鎖，防止並行 apply

  # backend "s3" {
  #   bucket         = "<paste from: cd bootstrap && terraform output -raw state_bucket_name>"
  #   key            = "43-terraform-modules/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "<paste from: cd bootstrap && terraform output -raw lock_table_name>"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}
