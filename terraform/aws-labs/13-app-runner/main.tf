#==============================================================
# 學習目標：使用 App Runner 部署容器，體驗「全代管」vs「自行管理」的差異
#
# App Runner vs ECS Fargate：
#   ECS（Lab 11-12）：
#     需要自行設定 Cluster、Task Definition、Service、Security Group、ALB
#     優點：完整控制，支援複雜架構
#
#   App Runner（本 lab）：
#     只需要提供 image URL 和 port，其餘 AWS 全包
#     自動處理：load balancing、auto scaling、HTTPS 憑證、health check
#     優點：極簡設定，適合快速部署簡單服務
#
# 這個 lab 只有 2 個資源需要填寫：
#   1. IAM Role（讓 App Runner 有權限從 ECR 拉 image）
#   2. aws_apprunner_service（服務本體）
#==============================================================


#--------------------------------------------------------------
# IAM Policy Attachment（已預先填好）
#--------------------------------------------------------------
# AWSAppRunnerServicePolicyForECRAccess 包含了從 ECR 拉 image 所需的所有權限：
#   ecr:GetAuthorizationToken
#   ecr:BatchCheckLayerAvailability
#   ecr:GetDownloadUrlForLayer
#   ecr:BatchGetImage

resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  role       = aws_iam_role.apprunner_ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}


#--------------------------------------------------------------
# TODO 1: IAM Role for App Runner ECR Access
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# App Runner 需要一個 Role 來代替你存取 ECR 拉取 image。
# 注意 Principal Service 與 Lambda / ECS 不同：
#
# 需要設定：
#   name = "${var.project}-ecr-access-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Action    = "sts:AssumeRole"
#       Principal = { Service = "build.apprunner.amazonaws.com" }
#       #                        ↑ 注意：不是 tasks、不是 lambda，是 build.apprunner
#     }]
#   })
#
#   tags = local.common_tags

resource "aws_iam_role" "apprunner_ecr_access" {
  # TODO
  name = "${var.project}-ecr-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "build.apprunner.amazonaws.com" }
    }]
  })
}


#--------------------------------------------------------------
# TODO 2: App Runner Service
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apprunner_service
#
# App Runner 自動處理 load balancing、HTTPS 憑證、health check、auto scaling。
# 你只需要告訴它：image 在哪、listen 哪個 port、給多少資源。
#
# 需要設定：
#   service_name = var.project
#
#   source_configuration {
#     authentication_configuration {
#       access_role_arn = aws_iam_role.apprunner_ecr_access.arn
#       # 告訴 App Runner 用哪個 Role 去拉 ECR image
#     }
#
#     image_repository {
#       image_identifier      = var.ecr_image_url
#       image_repository_type = "ECR"    # 私有 ECR（公開 image 用 "ECR_PUBLIC"）
#
#       image_configuration {
#         port = tostring(var.container_port)    # App Runner 的 port 是字串
#       }
#     }
#
#     auto_deployments_enabled = false    # true = ECR image 更新時自動重新部署
#   }
#
#   instance_configuration {
#     cpu    = var.cpu      # 格式："0.25 vCPU"（注意與 ECS 的數字格式不同）
#     memory = var.memory   # 格式："0.5 GB"
#   }
#
#   tags = local.common_tags
#
# ⚠️ apply 後需要等約 2-3 分鐘，App Runner 才會完成部署並將 status 變成 RUNNING。
#    可到 Console → App Runner → Services 查看進度。

resource "aws_apprunner_service" "app" {
  # TODO
  service_name = var.project

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_ecr_access.arn
    }

    image_repository {
      image_identifier      = var.ecr_image_url
      image_repository_type = "ECR"

      image_configuration {
        port = tostring(var.container_port)
      }
    }

    auto_deployments_enabled = false
  }

  instance_configuration {
    cpu    = var.cpu
    memory = var.memory
  }

  tags = local.common_tags
}
