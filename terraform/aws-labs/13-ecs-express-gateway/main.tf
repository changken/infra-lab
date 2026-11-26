#==============================================================
# 學習目標：使用 ECS Express Gateway Service 部署容器
#
# ECS Express Gateway Service 是什麼？
#   → 2025 年底推出的全代管容器服務
#   → 提供「App Runner 般的簡約」+ 「ECS 的底層架構」
#   → 只需 image + 兩個 IAM Role，AWS 自動建立：
#       ALB、Target Group、Security Group、Auto Scaling、HTTPS 憑證
#
# 與 Lab 11-12（ECS Fargate）的差異：
#   Lab 12（手動）：需要 11 個資源（Cluster、Task Def、Service、ALB、TG、Listener、SG×2...）
#   本 Lab（Express）：只需要 3 個資源（2 個 IAM Role + 1 個 Express Service）
#
# ⭐ 新概念：Infrastructure Role
#   ECS Express 需要「兩個」IAM Role，而不是一個：
#   1. Execution Role  → Task 啟動時用（拉 ECR image、寫 CloudWatch Logs）
#   2. Infrastructure Role → ECS 代替你建 ALB、SG、Auto Scaling 時用
#==============================================================


#--------------------------------------------------------------
# CloudWatch Log Group（pre-filled）
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
  tags              = local.common_tags
}


#--------------------------------------------------------------
# Execution Role（已學過，直接給出）
#--------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name = "${var.project}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


#--------------------------------------------------------------
# TODO 1: Infrastructure Role
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# ⭐ 這是與 Lab 11-12 最不同的地方：
#    ECS Express 需要一個額外的 Role，讓 ECS 代替你管理 AWS 基礎設施
#    （建立 ALB、Target Group、Security Group、Auto Scaling Policy）。
#
# Principal Service 與 Execution Role 不同：
#   Execution Role → "ecs-tasks.amazonaws.com"   ← Task 啟動時使用
#   Infrastructure Role → "ecs.amazonaws.com"    ← ECS 管理資源時使用
#
# 需要設定：
#   name = "${var.project}-infrastructure-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Action    = "sts:AssumeRole"
#       Principal = { Service = "ecs.amazonaws.com" }
#     }]
#   })
#
#   tags = local.common_tags
#
# ⚠️ infrastructure_role_arn 建立後無法修改，
#    如果需要更換必須重新建立整個 Express Service。

resource "aws_iam_role" "infrastructure" {
  # TODO
  name = "${var.project}-infrastructure-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: Infrastructure Role Policy Attachment
#--------------------------------------------------------------
# 文件: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-iam.html
#
# 把 AWS Managed Policy 附加到 infrastructure role。
# Express Gateway Service 需要這個 Policy 才能管理 ALB 和 Auto Scaling。
#
# 需要設定：
#   role       = aws_iam_role.infrastructure.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForExpressGatewayService"
#
# ⚠️ 如果 policy_arn 錯誤，可以用以下指令列出正確的 Policy：
#    aws iam list-policies \
#      --query 'Policies[?contains(PolicyName, `ExpressGateway`)].[PolicyName,Arn]' \
#      --output table

resource "aws_iam_role_policy" "infrastructure" {
  name = "${var.project}-infrastructure-policy"
  role = aws_iam_role.infrastructure.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeRouteTables",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:CreateLaunchConfiguration",
          "autoscaling:DeleteLaunchConfiguration",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:CreateLaunchTemplate",
          "autoscaling:DeleteLaunchTemplate",
          "autoscaling:DescribeLaunchTemplateVersions",
          "autoscaling:AttachLoadBalancers",
          "autoscaling:DetachLoadBalancers",
          "autoscaling:AttachLoadBalancerTargetGroups",
          "autoscaling:DetachLoadBalancerTargetGroups",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:CreateOrUpdateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "iam:GetServiceLinkedRoleDeletionStatus",
          "iam:DeleteServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListHostedZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:RequestCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DeleteLogGroup"
        ]
        Resource = "*"
      }
    ]
  })
}


#--------------------------------------------------------------
# TODO 3: ECS Express Gateway Service
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_express_gateway_service
#
# 這個資源自動建立並管理：ALB、Target Group、Security Group、Auto Scaling。
# 你只需要提供 image 和兩個 Role ARN。
#
# 需要設定：
#   service_name            = var.project
#   execution_role_arn      = aws_iam_role.execution.arn
#   infrastructure_role_arn = aws_iam_role.infrastructure.arn
#   cpu                     = var.cpu      # 字串格式，例如 "256"
#   memory                  = var.memory   # 字串格式，例如 "512"
#   health_check_path       = "/"
#
#   primary_container {
#     image          = var.ecr_image_url
#     container_port = var.container_port
#
#     aws_logs_configuration {
#       log_group = aws_cloudwatch_log_group.app.name
#     }
#   }
#
#   tags = local.common_tags
#
# Output 說明：
#   apply 完成後，服務的公開 URL 在 ingress_paths 屬性中：
#   aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint
#
# ⚠️ create timeout 預設 30 分鐘（ALB 建立需要時間），apply 後耐心等候。

resource "aws_ecs_express_gateway_service" "app" {
  # TODO
  service_name            = var.project
  execution_role_arn      = aws_iam_role.execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  cpu                     = var.cpu
  memory                  = var.memory
  health_check_path       = "/"
  wait_for_steady_state   = true

  primary_container {
    image          = var.ecr_image_url
    container_port = var.container_port

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.app.name
      log_stream_prefix = "ecs"
    }
  }

  tags = local.common_tags
}
