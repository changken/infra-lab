#==============================================================
# 場景：自動化部署流水線
#
# 完整流程：
#   git push (main branch)
#       │
#       ▼
#   GitHub Actions (OIDC → IAM Role，零 Access Key)
#       ├── docker build + push → ECR
#       └── 上傳 deployment.zip (appspec.yaml + taskdef.json) → S3
#               │
#               ▼
#           CodePipeline (S3 Source 偵測到新 zip)
#               │
#               ▼
#           CodeDeploy (ECS Blue/Green Deploy)
#               ├── 啟動新 Task（Green）
#               ├── 等待 Health Check 通過
#               ├── 切換 ALB Listener 流量到 Green
#               └── 5 分鐘後終止舊 Task（Blue）
#
# 關鍵設計點（ADR 摘要，完整見 README）：
#   1. OIDC 取代 Access Key → 短效憑證，不存在 GitHub Secrets
#   2. Blue/Green 取代 Rolling Update → 零停機，可立即回滾
#   3. S3 + CodePipeline 解耦觸發 → CI（GitHub）和 CD（AWS）各自獨立
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
#==============================================================


# 已完成：基礎 Data Sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

# 已完成：S3 bucket 名稱需要唯一 suffix
resource "random_id" "suffix" {
  byte_length = 4
}


#--------------------------------------------------------------
# TODO 1: ECR Repository（存放 Docker Image）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
#
#   name                 = "${var.project}-app"
#   image_tag_mutability = "MUTABLE"   # 允許 latest tag 覆蓋（lab 用）
#   force_delete         = true        # destroy 時自動刪除含 image 的 repo
#   tags                 = local.common_tags
#
#   image_scanning_configuration {
#     scan_on_push = true              # 推送時自動掃描漏洞
#   }

resource "aws_ecr_repository" "app" {
  # TODO

  image_scanning_configuration {
    # TODO
  }
}


#--------------------------------------------------------------
# TODO 2: VPC + 2 Public Subnets + IGW + Route Table
#--------------------------------------------------------------
# 文件 (vpc):                     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
# 文件 (subnet):                  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
# 文件 (internet_gateway):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
# 文件 (route_table):             https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
# 文件 (route_table_association): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
#
# [VPC]
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_hostnames = true
#   tags                 = local.common_tags
#
# [Subnet A / B]（分佈在 2 個 AZ，ALB 強制需要）
#   availability_zone       = data.aws_availability_zones.available.names[0/1]
#   cidr_block              = "10.0.1.0/24" / "10.0.2.0/24"
#   map_public_ip_on_launch = true
#
# [IGW + Route Table]（0.0.0.0/0 → IGW，兩個 Subnet 都關聯）
#
# ⚠️ 注意：ALB 強制要求至少 2 個不同 AZ 的 Subnet

resource "aws_vpc" "main" {
  # TODO
}

resource "aws_subnet" "public_a" {
  # TODO
}

resource "aws_subnet" "public_b" {
  # TODO
}

resource "aws_internet_gateway" "main" {
  # TODO
}

resource "aws_route_table" "public" {
  # TODO
  route {
    # TODO
  }
}

resource "aws_route_table_association" "public_a" {
  # TODO
}

resource "aws_route_table_association" "public_b" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: Security Groups（ALB + ECS Task）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# [ALB Security Group]
#   name   = "${var.project}-alb-sg"
#   vpc_id = aws_vpc.main.id
#   tags   = local.common_tags
#
#   ingress 80  （生產流量）from 0.0.0.0/0
#   ingress 8080（測試流量，Blue/Green 切換期間用）from 0.0.0.0/0
#   egress all  to 0.0.0.0/0
#
# [ECS Security Group]
#   name   = "${var.project}-ecs-sg"
#   vpc_id = aws_vpc.main.id
#   tags   = local.common_tags
#
#   ingress 80  from aws_security_group.alb.id  ← 只接受 ALB 的流量
#   egress all  to 0.0.0.0/0
#
# ⚠️ 注意：ALB SG 需要同時開放 80（生產）和 8080（測試）兩個 port
#          8080 是 Blue/Green 部署期間，驗證新版本（Green）用的測試 Listener

resource "aws_security_group" "alb" {
  # TODO

  ingress {
    # TODO port 80
  }

  ingress {
    # TODO port 8080
  }

  egress {
    # TODO
  }
}

resource "aws_security_group" "ecs" {
  # TODO

  ingress {
    # TODO
  }

  egress {
    # TODO
  }
}


#--------------------------------------------------------------
# TODO 4: ALB + 2 Target Groups（Blue / Green）+ 2 Listeners
#--------------------------------------------------------------
# 文件 (lb):            https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
# 文件 (target_group):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
# 文件 (listener):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
#
# [ALB]
#   name               = "${var.project}-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb.id]
#   subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
#   tags               = local.common_tags
#
# [Blue Target Group]（初始生產流量目標）
#   name        = "${var.project}-blue-tg"
#   port        = 80
#   protocol    = "HTTP"
#   target_type = "ip"    ← Fargate 使用 "ip"，非 "instance"
#   vpc_id      = aws_vpc.main.id
#   health_check { path = "/", healthy_threshold = 2, unhealthy_threshold = 3, interval = 30 }
#   tags = local.common_tags
#
# [Green Target Group]（Blue/Green 切換時的新版本目標，設定與 Blue 相同）
#   name = "${var.project}-green-tg"
#   （其餘與 Blue TG 相同）
#
# [Production Listener - Port 80]（平時走生產流量 → Blue TG）
#   load_balancer_arn = aws_lb.main.arn
#   port              = "80"
#   protocol          = "HTTP"
#   default_action { type = "forward", target_group_arn = aws_lb_target_group.blue.arn }
#
# [Test Listener - Port 8080]（Blue/Green 部署期間，驗證 Green TG 用）
#   port = "8080"
#   default_action { type = "forward", target_group_arn = aws_lb_target_group.green.arn }
#
# ⚠️ 注意：Fargate 的 target_type 必須是 "ip"，用 "instance" 會導致健康檢查失敗

resource "aws_lb" "main" {
  # TODO
}

resource "aws_lb_target_group" "blue" {
  # TODO
  health_check {
    # TODO
  }
}

resource "aws_lb_target_group" "green" {
  # TODO
  health_check {
    # TODO
  }
}

resource "aws_lb_listener" "prod" {
  # TODO production listener (port 80)
  default_action {
    # TODO
  }
}

resource "aws_lb_listener" "test" {
  # TODO test listener (port 8080)
  default_action {
    # TODO
  }
}


#--------------------------------------------------------------
# TODO 5: ECS（Cluster + Task Execution Role + Log Group + Task Definition + Service）
#--------------------------------------------------------------
# 文件 (cluster):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster
# 文件 (task_def):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
# 文件 (service):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
# 文件 (log_group):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group
#
# [ECS Cluster]
#   name = "${var.project}-cluster"
#   tags = local.common_tags
#
# [Task Execution Role]（ECS 拉取 ECR image + 寫 CloudWatch Logs）
#   name = "${var.project}-ecs-execution-role"
#   assume_role_policy: Principal.Service = "ecs-tasks.amazonaws.com"
#   附加 managed policy: "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
#
# [CloudWatch Log Group]（ECS 容器的 stdout/stderr）
#   name              = "/ecs/${var.project}-web"
#   retention_in_days = 7
#   tags              = local.common_tags
#
# [Task Definition]（初始使用 nginx:alpine 佔位，CodeDeploy 後會更新）
#   family                   = "${var.project}-web"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_execution.arn
#   tags                     = local.common_tags
#
#   container_definitions = jsonencode([{
#     name      = "web"           ← 必須和 appspec.yaml 的 ContainerName 一致
#     image     = "nginx:alpine"  ← 佔位 image；GitHub Actions 部署後會更新
#     essential = true
#     portMappings = [{ containerPort = 80, protocol = "tcp" }]
#     logConfiguration = {
#       logDriver = "awslogs"
#       options = {
#         "awslogs-group"         = "/ecs/${var.project}-web"
#         "awslogs-region"        = var.region
#         "awslogs-stream-prefix" = "ecs"
#       }
#     }
#   }])
#
#   lifecycle {
#     ignore_changes = [container_definitions]   ← CodeDeploy 接管後，Terraform 不再管 image
#   }
#
# [ECS Service]
#   name            = "${var.project}-web"
#   cluster         = aws_ecs_cluster.main.id
#   task_definition = aws_ecs_task_definition.web.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   tags            = local.common_tags
#
#   deployment_controller { type = "CODE_DEPLOY" }  ← 關鍵：使用 CodeDeploy 管理部署
#
#   network_configuration {
#     subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
#     security_groups  = [aws_security_group.ecs.id]
#     assign_public_ip = true
#   }
#
#   load_balancer {
#     target_group_arn = aws_lb_target_group.blue.arn  ← 初始指向 Blue TG
#     container_name   = "web"
#     container_port   = 80
#   }
#
#   lifecycle {
#     ignore_changes = [task_definition, load_balancer]  ← CodeDeploy 接管後不 revert
#   }
#
# ⚠️ 注意：deployment_controller type = "CODE_DEPLOY" 後，Terraform destroy 時
#          ECS Service 需要先手動刪除或由 CodeDeploy 清空，否則 destroy 可能超時

resource "aws_ecs_cluster" "main" {
  # TODO
}

resource "aws_iam_role" "ecs_execution" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  # TODO
}

resource "aws_cloudwatch_log_group" "ecs" {
  # TODO
}

resource "aws_ecs_task_definition" "web" {
  # TODO

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "web" {
  # TODO

  deployment_controller {
    # TODO
  }

  network_configuration {
    # TODO
  }

  load_balancer {
    # TODO
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}


#--------------------------------------------------------------
# TODO 6: CodeDeploy（App + ECS Blue/Green Deployment Group）
#--------------------------------------------------------------
# 文件 (app):            https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codedeploy_app
# 文件 (deploy_group):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codedeploy_deployment_group
#
# [CodeDeploy IAM Role]
#   name = "${var.project}-codedeploy-role"
#   assume_role_policy: Principal.Service = "codedeploy.amazonaws.com"
#   附加 managed policy: "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
#
# [CodeDeploy App]
#   name             = "${var.project}-app"
#   compute_platform = "ECS"     ← 必須是 "ECS"（非 "Server" 或 "Lambda"）
#   tags             = local.common_tags
#
# [Deployment Group]
#   app_name               = aws_codedeploy_app.main.name
#   deployment_group_name  = "${var.project}-dg"
#   service_role_arn       = aws_iam_role.codedeploy.arn
#   deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
#
#   auto_rollback_configuration {
#     enabled = true
#     events  = ["DEPLOYMENT_FAILURE"]   ← 部署失敗自動回滾到上一個版本
#   }
#
#   blue_green_deployment_config {
#     deployment_ready_option {
#       action_on_timeout = "CONTINUE_DEPLOYMENT"  ← 測試通過後自動切換（不等人工確認）
#     }
#     terminate_blue_instances_on_deployment_success {
#       action                           = "TERMINATE"
#       termination_wait_time_in_minutes = 5  ← 切換後等 5 分鐘再終止舊 Task
#     }
#   }
#
#   deployment_style {
#     deployment_option = "WITH_TRAFFIC_CONTROL"  ← 使用 ALB 控制流量切換
#     deployment_type   = "BLUE_GREEN"
#   }
#
#   ecs_service {
#     cluster_name = aws_ecs_cluster.main.name
#     service_name = aws_ecs_service.web.name
#   }
#
#   load_balancer_info {
#     target_group_pair_info {
#       prod_traffic_route { listener_arns = [aws_lb_listener.prod.arn] }
#       test_traffic_route { listener_arns = [aws_lb_listener.test.arn] }
#       target_group { name = aws_lb_target_group.blue.name }
#       target_group { name = aws_lb_target_group.green.name }
#     }
#   }
#
# ⚠️ 注意：deployment_config_name "CodeDeployDefault.ECSAllAtOnce" 表示一次切換所有流量
#          生產環境可改 "CodeDeployDefault.ECSCanary10Percent5Minutes"（金絲雀部署）

resource "aws_iam_role" "codedeploy" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  # TODO
}

resource "aws_codedeploy_app" "main" {
  # TODO
}

resource "aws_codedeploy_deployment_group" "main" {
  # TODO

  auto_rollback_configuration {
    # TODO
  }

  blue_green_deployment_config {
    deployment_ready_option {
      # TODO
    }
    terminate_blue_instances_on_deployment_success {
      # TODO
    }
  }

  deployment_style {
    # TODO
  }

  ecs_service {
    # TODO
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        # TODO
      }
      test_traffic_route {
        # TODO
      }
      target_group {
        # TODO blue
      }
      target_group {
        # TODO green
      }
    }
  }
}


#--------------------------------------------------------------
# TODO 7: GitHub Actions OIDC Provider + IAM Role
#--------------------------------------------------------------
# 文件 (oidc_provider): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
# 文件 (iam_role):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# [OIDC Provider]（每個帳號只需建一次）
#   url            = "https://token.actions.githubusercontent.com"
#   client_id_list = ["sts.amazonaws.com"]
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1",
#     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
#   ]
#
# ⚠️ 注意：若 Lab 27 已建過 OIDC Provider，apply 會報 EntityAlreadyExists 錯誤
#          解決方法：terraform import aws_iam_openid_connect_provider.github \
#            arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com
#
# [GitHub Actions IAM Role]
#   name = "${var.project}-github-actions-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
#       Action = "sts:AssumeRoleWithWebIdentity"
#       Condition = {
#         StringLike = {
#           "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
#         }
#         StringEquals = {
#           "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#         }
#       }
#     }]
#   })
#
# [GitHub Actions Role Policy]（最小權限：只允許 ECR push + S3 put）
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = "ecr:GetAuthorizationToken"
#         Resource = "*"          ← GetAuthorizationToken 不支援 Resource 限制
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer",
#           "ecr:BatchGetImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
#           "ecr:CompleteLayerUpload", "ecr:PutImage"
#         ]
#         Resource = aws_ecr_repository.app.arn
#       },
#       {
#         Effect   = "Allow"
#         Action   = ["s3:PutObject", "s3:GetObject", "s3:GetBucketLocation"]
#         Resource = ["${aws_s3_bucket.artifacts.arn}", "${aws_s3_bucket.artifacts.arn}/*"]
#       }
#     ]
#   })

resource "aws_iam_openid_connect_provider" "github" {
  # TODO
}

resource "aws_iam_role" "github_actions" {
  # TODO
}

resource "aws_iam_role_policy" "github_actions" {
  # TODO
}


#--------------------------------------------------------------
# TODO 8: S3 Artifact Bucket + CodePipeline + IAM Role
#--------------------------------------------------------------
# 文件 (s3_bucket):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
# 文件 (versioning):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning
# 文件 (codepipeline):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codepipeline
#
# [S3 Artifact Bucket]（CodePipeline Source + Artifact store 共用）
#   bucket        = "${var.project}-artifacts-${random_id.suffix.hex}"
#   force_destroy = true
#   tags          = local.common_tags
#
# [S3 Versioning]（CodePipeline S3 Source 必須啟用 Versioning）
#   versioning_configuration { status = "Enabled" }
#
# [CodePipeline IAM Role]
#   name = "${var.project}-codepipeline-role"
#   assume_role_policy: Principal.Service = "codepipeline.amazonaws.com"
#
# [CodePipeline Role Policy]
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning",
#                     "s3:PutObjectAcl", "s3:PutObject"]
#         Resource = ["${aws_s3_bucket.artifacts.arn}", "${aws_s3_bucket.artifacts.arn}/*"]
#       },
#       {
#         Effect = "Allow"
#         Action = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment",
#                   "codedeploy:GetDeploymentConfig", "codedeploy:GetApplicationRevision",
#                   "codedeploy:RegisterApplicationRevision"]
#         Resource = "*"
#       },
#       {
#         Effect   = "Allow"
#         Action   = "iam:PassRole"
#         Resource = "*"
#       }
#     ]
#   })
#
# [CodePipeline]
#   name     = "${var.project}-pipeline"
#   role_arn = aws_iam_role.codepipeline.arn
#   tags     = local.common_tags
#
#   artifact_store {
#     location = aws_s3_bucket.artifacts.id
#     type     = "S3"
#   }
#
#   stage {
#     name = "Source"
#     action {
#       name             = "S3Source"
#       category         = "Source"
#       owner            = "AWS"
#       provider         = "S3"
#       version          = "1"
#       output_artifacts = ["source_output"]
#       configuration = {
#         S3Bucket             = aws_s3_bucket.artifacts.id
#         S3ObjectKey          = "deployment.zip"
#         PollForSourceChanges = "true"
#       }
#     }
#   }
#
#   stage {
#     name = "Deploy"
#     action {
#       name            = "BlueGreenDeploy"
#       category        = "Deploy"
#       owner           = "AWS"
#       provider        = "CodeDeploy"
#       version         = "1"
#       input_artifacts = ["source_output"]
#       configuration = {
#         ApplicationName     = aws_codedeploy_app.main.name
#         DeploymentGroupName = aws_codedeploy_deployment_group.main.deployment_group_name
#       }
#     }
#   }
#
# ⚠️ 注意：第一次 apply 後 Pipeline 會立即執行並失敗（S3 bucket 是空的）
#          這是正常現象，執行 GitHub Actions 推送 deployment.zip 後 Pipeline 會自動重試

resource "aws_s3_bucket" "artifacts" {
  # TODO
}

resource "aws_s3_bucket_versioning" "artifacts" {
  # TODO
  versioning_configuration {
    # TODO
  }
}

resource "aws_iam_role" "codepipeline" {
  # TODO
}

resource "aws_iam_role_policy" "codepipeline" {
  # TODO
}

resource "aws_codepipeline" "main" {
  # TODO

  artifact_store {
    # TODO
  }

  stage {
    name = "Source"
    action {
      # TODO
    }
  }

  stage {
    name = "Deploy"
    action {
      # TODO
    }
  }
}
