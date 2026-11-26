#==============================================================
# 學習目標：建立 ECR Repository，push Docker image
#
# ECR = Elastic Container Registry
#   → AWS 的私有 Docker Registry（類似 Docker Hub 的私有版）
#   → ECS / EKS 部署時從這裡拉 image
#
# 這個 lab 分兩步：
#   Step 1（Terraform）：建立 ECR repository + lifecycle policy
#   Step 2（Docker CLI）：build image → 認證 ECR → push image
#
# 完成順序：1 → 2（然後照 README 的 docker 指令操作）
#==============================================================


#--------------------------------------------------------------
# TODO 1: ECR Repository
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
#
# 需要設定：
#   name                 = var.repository_name
#   image_tag_mutability = "MUTABLE"
#   # MUTABLE  → 允許覆蓋同一個 tag（開發方便）
#   # IMMUTABLE → 同一個 tag 只能 push 一次（生產環境推薦）
#
#   image_scanning_configuration {
#     scan_on_push = true    # 每次 push 自動掃描漏洞（免費功能）
#   }
#
#   tags = merge(local.common_tags, { Name = var.repository_name })

resource "aws_ecr_repository" "main" {
  # TODO
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = merge(local.common_tags, { Name = var.repository_name })
}


#--------------------------------------------------------------
# TODO 2: ECR Lifecycle Policy（自動清理舊 image）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy
#
# ECR 儲存是按 GB 計費，不清理舊 image 會慢慢累積費用。
# Lifecycle Policy 可以自動刪除超過數量限制的舊 image。
#
# 需要設定：
#   repository = aws_ecr_repository.main.name
#
#   policy = jsonencode({
#     rules = [{
#       rulePriority = 1
#       description  = "Keep last ${var.max_image_count} images"
#       selection = {
#         tagStatus   = "any"
#         countType   = "imageCountMoreThan"
#         countNumber = var.max_image_count
#       }
#       action = {
#         type = "expire"
#       }
#     }]
#   })

resource "aws_ecr_lifecycle_policy" "main" {
  # TODO
  repository = aws_ecr_repository.main.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.max_image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_image_count
      }
      action = {
        type = "expire"
      }
    }]
  })
}
