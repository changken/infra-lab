#==============================================================
# 學習目標：在 ECS Fargate 前加入 ALB（Application Load Balancer）
#
# 與 Lab 11 的差異：
#   Lab 11 → Fargate Task 直接暴露 Public IP（每次重啟 IP 會變）
#   Lab 12 → ALB 作為固定入口，後端 Task 可以動態擴縮
#
# ALB 的優點：
#   - 固定 DNS 名稱（不因 Task 重啟而改變）
#   - 健康檢查自動剔除異常 Task
#   - 支援 path-based routing（Lab 後續進階）
#   - 支援 HTTPS（搭配 ACM 憑證）
#
# 架構：
#   Internet
#     → ALB（Security Group：允許 0.0.0.0/0:80）
#       → Target Group（type=ip，health check /）
#         → Fargate Task（Security Group：只允許來自 ALB SG）
#==============================================================


#--------------------------------------------------------------
# Data Sources
#--------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


#--------------------------------------------------------------
# CloudWatch Log Group
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
  tags              = local.common_tags
}


#--------------------------------------------------------------
# IAM：ECS Task Execution Role
#--------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


#--------------------------------------------------------------
# ECS Cluster（已學過，直接給出）
#--------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = var.project
  tags = local.common_tags
}


#--------------------------------------------------------------
# ECS Task Definition（已學過，直接給出）
#--------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  container_definitions    = local.container_definitions
  tags                     = local.common_tags
}


#--------------------------------------------------------------
# TODO 1: ALB Security Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# ALB 需要對外開放 port 80（接收來自 Internet 的請求）。
#
# 需要設定：
#   name        = "${var.project}-alb-sg"
#   description = "Allow HTTP from internet to ALB"
#   vpc_id      = data.aws_vpc.default.id
#
#   ingress {
#     from_port   = 80
#     to_port     = 80
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
#   tags = local.common_tags

resource "aws_security_group" "alb" {
  # TODO
  name        = "${var.project}-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: ECS Service Security Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# ⭐ 重點：ECS task 只接受來自 ALB 的流量（不直接對外開放）
#          ingress 的 source 改用 security_groups，而非 cidr_blocks。
#          這是 SG-to-SG 參考（更安全的做法）。
#
# 需要設定：
#   name        = "${var.project}-ecs-sg"
#   description = "Allow traffic from ALB to ECS tasks"
#   vpc_id      = data.aws_vpc.default.id
#
#   ingress {
#     from_port       = var.container_port
#     to_port         = var.container_port
#     protocol        = "tcp"
#     security_groups = [aws_security_group.alb.id]   # ← 只允許來自 ALB SG
#   }
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]    # Task 需要對外拉 ECR image
#   }
#
#   tags = local.common_tags

resource "aws_security_group" "ecs_service" {
  # TODO
  name        = "${var.project}-ecs-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 3: Application Load Balancer
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
#
# ALB 是 Layer 7 的 Load Balancer，負責接收 HTTP/HTTPS 請求並轉發給後端。
#
# 需要設定：
#   name               = "${var.project}-alb"
#   internal           = false              # false = 面向 Internet
#   load_balancer_type = "application"      # ALB（另有 network / gateway）
#   security_groups    = [aws_security_group.alb.id]
#   subnets            = data.aws_subnets.default.ids
#   tags               = local.common_tags
#
# ⚠️ ALB 費用：$0.008/hr + LCU 費用，記得 Lab 完成後立刻 destroy！

resource "aws_lb" "main" {
  # TODO
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
  tags               = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: Target Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
#
# Target Group 定義後端的一組目標（這裡是 Fargate Task），
# 以及如何對它們做健康檢查。
#
# 需要設定：
#   name        = "${var.project}-tg"
#   port        = var.container_port
#   protocol    = "HTTP"
#   vpc_id      = data.aws_vpc.default.id
#   target_type = "ip"    # ⭐ Fargate 使用 awsvpc 模式，target 是 IP 不是 instance
#
#   health_check {
#     path                = "/"
#     healthy_threshold   = 2
#     unhealthy_threshold = 3
#     interval            = 30     # 秒
#   }
#
#   tags = local.common_tags

resource "aws_lb_target_group" "app" {
  # TODO
  name        = "${var.project}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 5: ALB Listener
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
#
# Listener 定義 ALB 監聽哪個 port，以及收到請求後的預設動作。
# 這裡設定 port 80 → 轉發給 Target Group。
#
# 需要設定：
#   load_balancer_arn = aws_lb.main.arn
#   port              = "80"
#   protocol          = "HTTP"
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }

resource "aws_lb_listener" "http" {
  # TODO

  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}


#--------------------------------------------------------------
# TODO 6: ECS Service（含 ALB 整合）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
#
# 與 Lab 11 相比，新增了 load_balancer block，
# 並在 network_configuration 中改用 ECS 專屬的 Security Group。
#
# 需要設定：
#   name            = "${var.project}-service"
#   cluster         = aws_ecs_cluster.main.id
#   task_definition = aws_ecs_task_definition.app.arn
#   desired_count   = var.desired_count
#   launch_type     = "FARGATE"
#
#   network_configuration {
#     subnets          = data.aws_subnets.default.ids
#     security_groups  = [aws_security_group.ecs_service.id]
#     assign_public_ip = true    # Default VPC 的 public subnet 需要此設定才能拉 ECR image
#   }
#
#   load_balancer {
#     target_group_arn = aws_lb_target_group.app.arn
#     container_name   = var.container_name
#     container_port   = var.container_port
#   }
#
#   tags = local.common_tags
#
# ⚠️ 必須加 depends_on，確保 Listener 建好後 Service 才啟動，
#    否則 ECS 可能在 Target Group 還沒關聯 Listener 前就嘗試註冊：
#   depends_on = [aws_lb_listener.http]

resource "aws_ecs_service" "app" {
  # TODO
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  tags = local.common_tags
}
