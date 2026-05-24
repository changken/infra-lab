#==============================================================
# 學習目標：CodeBuild Project + buildspec.yml + ECR image build
#
# 流程：
#   Terraform 打包 app/ 目錄 → 上傳到 S3（Source）
#     → 你手動觸發 CodeBuild
#         → CodeBuild 讀取 Source → 執行 buildspec.yml
#             → docker build → docker push → ECR
#
# 新概念：
#   aws_codebuild_project   → 定義建置環境、Source、Artifacts、IAM
#   buildspec.yml           → 建置腳本（phases: pre_build/build/post_build）
#   privileged_mode = true  → 在 CodeBuild 容器內執行 docker 指令的必要設定
#   ECR 登入流程            → get-login-password | docker login
#
# ⚠️ 最常忘記的事：
#   1. IAM Role 需要 ecr:GetAuthorizationToken（Resource = "*"，無法限縮）
#   2. privileged_mode = true 沒設 → docker build 會失敗（permission denied）
#   3. S3 Source 的 location 格式：bucket-name/path/to/source.zip
#
# 完成順序：1 → 2 → 3 → 4
#==============================================================


# 已完成：取得目前 AWS 帳號 ID（ECR registry URL 需要）
data "aws_caller_identity" "current" {}

# 已完成：S3 suffix（bucket 名稱需要全球唯一）
resource "random_id" "suffix" {
  byte_length = 4
}

# 已完成：打包 app/ 目錄為 zip
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/app"
  output_path = "${path.module}/app/source.zip"
  excludes    = ["source.zip"]
}

# 已完成：S3 Bucket（存放 CodeBuild source code）
resource "aws_s3_bucket" "source" {
  bucket        = "${var.project}-source-${random_id.suffix.hex}"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${var.project}-source" })
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 已完成：上傳 source zip 到 S3
resource "aws_s3_object" "source" {
  bucket = aws_s3_bucket.source.id
  key    = "source.zip"
  source = data.archive_file.source.output_path
  etag   = data.archive_file.source.output_md5
}


#--------------------------------------------------------------
# TODO 1: ECR Repository
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
#
# CodeBuild 建置完成後會把 image 推送到這裡。
#
#   name                 = var.project
#   image_tag_mutability = "MUTABLE"   # 允許覆寫 latest tag
#
#   image_scanning_configuration {
#     scan_on_push = true              # 推送時自動掃描漏洞
#   }
#
#   tags = merge(local.common_tags, { Name = var.project })

resource "aws_ecr_repository" "app" {
  # TODO
  name                 = var.project
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, { Name = var.project })
}


#--------------------------------------------------------------
# TODO 2: CloudWatch Log Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group
#
# CodeBuild 的建置 log 會送到這裡，方便除錯。
# 不設定的話 CodeBuild 會自動建立，但 terraform destroy 不會刪掉它。
#
#   name              = "/aws/codebuild/${var.project}"
#   retention_in_days = 7
#   tags              = local.common_tags

resource "aws_cloudwatch_log_group" "codebuild" {
  # TODO
  name              = "/aws/codebuild/${var.project}"
  retention_in_days = 7
  tags              = merge(local.common_tags, { Name = "/aws/codebuild/${var.project}" })
}


#--------------------------------------------------------------
# TODO 3: IAM Role + Policy（CodeBuild 執行權限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# ── IAM Role ──
#   name = "${var.project}-codebuild-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "codebuild.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#   tags = local.common_tags
#
# ── IAM Policy ── （三個功能區塊）
#   name = "${var.project}-codebuild-policy"
#   role = aws_iam_role.codebuild.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       # 1. ECR 登入（必須 Resource = "*"，這個 API 不支援縮小範圍）
#       {
#         Effect   = "Allow"
#         Action   = ["ecr:GetAuthorizationToken"]
#         Resource = ["*"]
#       },
#       # 2. ECR 推送（限定到此 repository）
#       {
#         Effect = "Allow"
#         Action = [
#           "ecr:BatchCheckLayerAvailability",
#           "ecr:InitiateLayerUpload",
#           "ecr:UploadLayerPart",
#           "ecr:CompleteLayerUpload",
#           "ecr:PutImage"
#         ]
#         Resource = [aws_ecr_repository.app.arn]
#       },
#       # 3. CloudWatch Logs（建置 log 輸出）
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ]
#         Resource = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
#       },
#       # 4. S3 讀取 Source（CodeBuild 需要從 S3 拉取 source.zip）
#       {
#         Effect   = "Allow"
#         Action   = ["s3:GetObject", "s3:GetObjectVersion"]
#         Resource = ["${aws_s3_bucket.source.arn}/*"]
#       }
#     ]
#   })

resource "aws_iam_role" "codebuild" {
  # TODO
  name = "${var.project}-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "codebuild" {
  # TODO
  name = "${var.project}-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [aws_ecr_repository.app.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = ["${aws_s3_bucket.source.arn}/*"]
      }
    ]
  })
}


#--------------------------------------------------------------
# TODO 4: CodeBuild Project
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project
#
#   name          = var.project
#   description   = "Build Docker image and push to ECR"
#   service_role  = aws_iam_role.codebuild.arn
#   tags          = local.common_tags
#
# ── source（從 S3 讀取 source.zip）──
#   source {
#     type      = "S3"
#     location  = "${aws_s3_bucket.source.id}/source.zip"
#     # ⚠️ location 格式是 "bucket-name/key"，不是完整 S3 URL
#   }
#
# ── artifacts（這個 lab 不需要輸出 artifact，但 type 不能省略）──
#   artifacts {
#     type = "NO_ARTIFACTS"
#   }
#
# ── environment（建置環境設定）──
#   environment {
#     compute_type    = "BUILD_GENERAL1_SMALL"   # vCPU 3 / RAM 4GB，夠用且最便宜
#     image           = "aws/codebuild/standard:7.0"  # 內建 Docker
#     type            = "LINUX_CONTAINER"
#     privileged_mode = true
#     # ⚠️ privileged_mode = true 是在容器內執行 docker 指令的必要條件
#     #    忘記設定 → 建置時報 "Cannot connect to the Docker daemon"
#
#     environment_variable {
#       name  = "ECR_REGISTRY"
#       value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
#     }
#     environment_variable {
#       name  = "ECR_REPOSITORY"
#       value = aws_ecr_repository.app.name
#     }
#   }
#
# ── logs_config（指定 CloudWatch Log Group）──
#   logs_config {
#     cloudwatch_logs {
#       group_name  = aws_cloudwatch_log_group.codebuild.name
#       stream_name = "build-log"
#     }
#   }

resource "aws_codebuild_project" "main" {
  # TODO
  name         = var.project
  description  = "Build Docker image and push to ECR"
  service_role = aws_iam_role.codebuild.arn
  tags         = local.common_tags

  source {
    type     = "S3"
    location = "${aws_s3_bucket.source.id}/source.zip"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REGISTRY"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    }
    environment_variable {
      name  = "ECR_REPOSITORY"
      value = aws_ecr_repository.app.name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build-log"
    }
  }
}
