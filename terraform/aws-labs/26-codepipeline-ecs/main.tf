#==============================================================
# 學習目標：CodePipeline（Source → Build → Deploy to ECS）
#
# 流程：
#   terraform apply 上傳 source.zip → S3
#     → CodePipeline Source Stage 偵測到變更
#         → Build Stage：CodeBuild 建置 image → ECR
#             → Deploy Stage：ECS Rolling Update
#
# 和 Lab 25 的差異：
#   Lab 25：CodeBuild standalone，Source = S3，手動觸發
#   Lab 26：CodeBuild type = CODEPIPELINE，Source 由 Pipeline 傳入，
#           增加 Deploy Stage，整個流程自動串聯
#
# 新概念：
#   aws_codepipeline          → 定義 Pipeline 與 Stages
#   stage / action block      → Pipeline 的執行單元
#   InputArtifacts / OutputArtifacts → Stage 之間傳遞資料的機制
#   imagedefinitions.json     → Build Stage 輸出，告訴 ECS Deploy 用哪個 image
#   PassRole                  → CodePipeline 需要 IAM PassRole 才能傳遞 Role 給 ECS
#
# ⚠️ 最常踩的坑：
#   1. CodePipeline IAM 缺少 iam:PassRole → Deploy Stage 一直失敗
#   2. imagedefinitions.json 的 container name ≠ Task Definition container name
#   3. S3 artifact bucket 和 source bucket 是兩個不同的 bucket
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：基礎 Data Sources
data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 已完成：唯一 suffix
resource "random_id" "suffix" {
  byte_length = 4
}

# 已完成：打包 app/ 為 zip（S3 Source 用）
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/app"
  output_path = "${path.module}/app/source.zip"
  excludes    = ["source.zip"]
}

# 已完成：S3 Source Bucket（存放 app source code，觸發 Pipeline）
resource "aws_s3_bucket" "source" {
  bucket        = "${var.project}-source-${random_id.suffix.hex}"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${var.project}-source" })
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_object" "source" {
  bucket = aws_s3_bucket.source.id
  key    = "source.zip"
  source = data.archive_file.source.output_path
  etag   = data.archive_file.source.output_md5
}

# 已完成：S3 Artifact Bucket（CodePipeline Stage 之間傳遞 artifacts）
# ⚠️ 這和 Source Bucket 是不同的 bucket！
#   Source Bucket：存放你的程式碼，觸發 Pipeline
#   Artifact Bucket：CodePipeline 內部用來傳遞 Stage 產出的暫存區
resource "aws_s3_bucket" "artifact" {
  bucket        = "${var.project}-artifact-${random_id.suffix.hex}"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${var.project}-artifact" })
}

# 已完成：ECS Task Execution Role（ECS 拉取 ECR image + 寫 CloudWatch Logs）
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 已完成：CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project}"
  retention_in_days = 7
  tags              = local.common_tags
}


#--------------------------------------------------------------
# TODO 1: ECR Repository
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
#
#   name                 = var.project
#   image_tag_mutability = "MUTABLE"
#
#   image_scanning_configuration {
#     scan_on_push = true
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
# TODO 2: ECS 基礎設施（Security Group + Cluster + Task Definition + Service）
#--------------------------------------------------------------
# 文件（cluster）:  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster
# 文件（task）:     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
# 文件（service）:  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
#
# ── Security Group（允許 container_port ingress）──
#   name   = "${var.project}-ecs-sg"
#   vpc_id = data.aws_vpc.default.id
#
#   ingress {
#     from_port   = var.container_port
#     to_port     = var.container_port
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
# ── ECS Cluster ──
#   name = var.project
#   tags = local.common_tags
#
# ── Task Definition ──
#   family                   = var.project
#   cpu                      = var.task_cpu
#   memory                   = var.task_memory
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   tags                     = local.common_tags
#
#   container_definitions = jsonencode([{
#     name      = "app"           # ⚠️ 必須和 imagedefinitions.json 的 name 一致
#     image     = "nginx:alpine"  # 初始佔位 image，Pipeline 會更新成 ECR image
#     essential = true
#     portMappings = [{
#       containerPort = var.container_port
#       protocol      = "tcp"
#     }]
#     logConfiguration = {
#       logDriver = "awslogs"
#       options = {
#         "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
#         "awslogs-region"        = var.region
#         "awslogs-stream-prefix" = "ecs"
#       }
#     }
#   }])
#
# ── ECS Service ──
#   name            = var.project
#   cluster         = aws_ecs_cluster.main.id
#   task_definition = aws_ecs_task_definition.app.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#
#   network_configuration {
#     subnets          = data.aws_subnets.public.ids
#     security_groups  = [aws_security_group.ecs.id]
#     assign_public_ip = true
#   }
#
#   lifecycle {
#     ignore_changes = [task_definition]
#     # ⚠️ CodePipeline 會更新 task_definition，若不忽略，
#     #    下次 terraform apply 會把它改回來，造成 Pipeline 和 Terraform 打架
#   }

resource "aws_security_group" "ecs" {
  # TODO
  name   = "${var.project}-ecs-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "main" {
  # TODO
  name = var.project
  tags = local.common_tags
}

resource "aws_ecs_task_definition" "app" {
  # TODO
  family                   = var.project
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  tags                     = local.common_tags

  container_definitions = jsonencode([{
    name      = "app"
    image     = "nginx:alpine"
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  # TODO
  name            = var.project
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}


#--------------------------------------------------------------
# TODO 3: CodeBuild IAM + CodeBuild Project（CODEPIPELINE 型）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project
#
# 和 Lab 25 的關鍵差異：
#   source { type = "CODEPIPELINE" }   → Source 由 Pipeline 傳入，不需要指定 S3 location
#   artifacts { type = "CODEPIPELINE" } → 輸出 artifacts 傳回 Pipeline（不是 NO_ARTIFACTS）
#
# ── IAM Role（principal = codebuild.amazonaws.com）──
#   name = "${var.project}-codebuild-role"
#   （assume_role_policy 結構和 Lab 25 相同）
#
# ── IAM Policy ──
#   包含：ECR GetAuthorizationToken（*）+ ECR Push + CloudWatch Logs + S3 Artifact（讀寫）
#
#   # 額外加入 S3 Artifact Bucket 的讀寫（Pipeline 傳遞 artifacts 用）
#   {
#     Effect   = "Allow"
#     Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
#     Resource = ["${aws_s3_bucket.artifact.arn}/*"]
#   }
#
# ── CodeBuild Project ──
#   name         = var.project
#   service_role = aws_iam_role.codebuild.arn
#
#   source { type = "CODEPIPELINE" }      # ← 和 Lab 25 不同
#   artifacts { type = "CODEPIPELINE" }   # ← 和 Lab 25 不同
#
#   environment {
#     compute_type    = "BUILD_GENERAL1_SMALL"
#     image           = "aws/codebuild/standard:7.0"
#     type            = "LINUX_CONTAINER"
#     privileged_mode = true
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
#   logs_config {
#     cloudwatch_logs {
#       group_name  = aws_cloudwatch_log_group.codebuild.name
#       stream_name = "build-log"
#     }
#   }

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
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = ["${aws_s3_bucket.artifact.arn}/*"]
      }
    ]
  })
}

resource "aws_codebuild_project" "main" {
  # TODO
  name = var.project
  source {
    type = "CODEPIPELINE"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0"
    privileged_mode = true
    compute_type    = "BUILD_GENERAL1_SMALL"
    environment_variable {
      name  = "ECR_REGISTRY"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    }
    environment_variable {
      name  = "ECR_REPOSITORY"
      value = aws_ecr_repository.app.name
    }
  }
  service_role = aws_iam_role.codebuild.arn
  tags         = local.common_tags

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build-log"
    }
  }
}


#--------------------------------------------------------------
# TODO 4: CodePipeline IAM Role + Policy
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# ── IAM Role（principal = codepipeline.amazonaws.com）──
#   name = "${var.project}-pipeline-role"
#
# ── IAM Policy（5 個功能區塊）──
#   name = "${var.project}-pipeline-policy"
#   role = aws_iam_role.pipeline.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       # 1. S3 Source Bucket（讀取 source.zip，偵測版本變更）
#       {
#         Effect   = "Allow"
#         Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning"]
#         Resource = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
#       },
#       # 2. S3 Artifact Bucket（讀寫，Stage 間傳遞 artifacts）
#       {
#         Effect   = "Allow"
#         Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
#         Resource = ["${aws_s3_bucket.artifact.arn}/*"]
#       },
#       # 3. CodeBuild（觸發建置、查詢狀態）
#       {
#         Effect   = "Allow"
#         Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
#         Resource = [aws_codebuild_project.main.arn]
#       },
#       # 4. ECS Deploy（更新 Service 的 task definition）
#       {
#         Effect = "Allow"
#         Action = [
#           "ecs:DescribeClusters",
#           "ecs:DescribeServices",
#           "ecs:DescribeTaskDefinition",
#           "ecs:DescribeTasks",
#           "ecs:ListTasks",
#           "ecs:RegisterTaskDefinition",
#           "ecs:TagResource",
#           "ecs:UpdateService"
#         ]
#         Resource = ["*"]
#       },
#       # 5. IAM PassRole（把 ECS Task Execution Role 傳給 ECS）
#       # ⚠️ 缺少這個 → Deploy Stage 報 "not authorized to perform: iam:PassRole"
#       {
#         Effect   = "Allow"
#         Action   = ["iam:PassRole"]
#         Resource = [aws_iam_role.ecs_task_execution.arn]
#       }
#     ]
#   })

resource "aws_iam_role" "pipeline" {
  # TODO
  name = "${var.project}-pipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "pipeline" {
  # TODO
  name = "${var.project}-pipeline-policy"
  role = aws_iam_role.pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning"]
        Resource = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = [aws_s3_bucket.artifact.arn, "${aws_s3_bucket.artifact.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = [aws_codebuild_project.main.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:TagResource",
          "ecs:UpdateService"
        ]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_task_execution.arn]
      }
    ]
  })
}


#--------------------------------------------------------------
# TODO 5: CodePipeline Pipeline（3 Stages）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codepipeline
#
#   name     = var.project
#   role_arn = aws_iam_role.pipeline.arn
#   tags     = local.common_tags
#
#   artifact_store {
#     location = aws_s3_bucket.artifact.id
#     type     = "S3"
#   }
#
# ── Stage 1: Source（從 S3 取得 source.zip）──
#   stage {
#     name = "Source"
#     action {
#       name             = "Source"
#       category         = "Source"
#       owner            = "AWS"
#       provider         = "S3"
#       version          = "1"
#       output_artifacts = ["source_output"]   # 傳給下一個 Stage
#
#       configuration = {
#         S3Bucket             = aws_s3_bucket.source.id
#         S3ObjectKey          = "source.zip"
#         PollForSourceChanges = "true"         # S3 版本變更時自動觸發
#       }
#     }
#   }
#
# ── Stage 2: Build（CodeBuild 建置 image）──
#   stage {
#     name = "Build"
#     action {
#       name             = "Build"
#       category         = "Build"
#       owner            = "AWS"
#       provider         = "CodeBuild"
#       version          = "1"
#       input_artifacts  = ["source_output"]   # 接收 Stage 1 的輸出
#       output_artifacts = ["build_output"]    # 輸出給 Stage 3（含 imagedefinitions.json）
#
#       configuration = {
#         ProjectName = aws_codebuild_project.main.name
#       }
#     }
#   }
#
# ── Stage 3: Deploy（ECS Rolling Update）──
#   stage {
#     name = "Deploy"
#     action {
#       name            = "Deploy"
#       category        = "Deploy"
#       owner           = "AWS"
#       provider        = "ECS"
#       version         = "1"
#       input_artifacts = ["build_output"]     # 接收 Stage 2 的 imagedefinitions.json
#
#       configuration = {
#         ClusterName = aws_ecs_cluster.main.name
#         ServiceName = aws_ecs_service.app.name
#         FileName    = "imagedefinitions.json"  # Build Stage 輸出的檔案名稱
#       }
#     }
#   }

resource "aws_codepipeline" "main" {
  # TODO
  name       = var.project
  role_arn   = aws_iam_role.pipeline.arn
  tags       = local.common_tags
  depends_on = [aws_iam_role_policy.pipeline]

  artifact_store {
    location = aws_s3_bucket.artifact.id
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        S3Bucket             = aws_s3_bucket.source.id
        S3ObjectKey          = "source.zip"
        PollForSourceChanges = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.app.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}
