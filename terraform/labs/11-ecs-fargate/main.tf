#==============================================================
# 學習目標：建立 ECS Fargate Service，從 ECR 拉取 image 並執行
#
# ECS = Elastic Container Service
#   → AWS 的容器編排服務（不需要管理 EC2）
#   → Fargate = Serverless 容器執行環境（不需要管理 Worker Node）
#
# 架構：
#   ECR image（Lab 10）
#     → Task Definition（定義容器規格）
#       → ECS Service（維持 desired_count 個 Task 持續執行）
#         → Fargate Task（有 Public IP，直接對外服務）
#
# ⚠️ 這個 lab 不使用 ALB，直接用 assign_public_ip = true。
#    Lab 12 才加 ALB（更穩定的生產方式）。
#==============================================================


#--------------------------------------------------------------
# Data Sources：使用 Default VPC 和 Subnets（不新建 VPC）
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
# CloudWatch Log Group（給 ECS container logs 用）
#--------------------------------------------------------------
# ECS task 啟動時會自動往這個 log group 寫 container stdout/stderr
# AmazonECSTaskExecutionRolePolicy 已包含寫入權限，但需要先建立 group

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
  tags              = local.common_tags
}


#--------------------------------------------------------------
# IAM：ECS Task Execution Role
#--------------------------------------------------------------
# ECS 用這個 Role 來：
#   1. 從 ECR 拉取 image（ecr:GetAuthorizationToken, ecr:BatchGetImage...）
#   2. 寫入 CloudWatch Logs（logs:CreateLogStream, logs:PutLogEvents）
# AmazonECSTaskExecutionRolePolicy 已包含以上所有權限

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
# TODO 1: ECS Cluster
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster
#
# ECS Cluster 是一個邏輯容器，用來組織和管理 ECS Service / Task。
# 使用 Fargate 時，Cluster 本身不需要設定 EC2 instance。
#
# 需要設定：
#   name = var.project
#   tags = local.common_tags

resource "aws_ecs_cluster" "main" {
  # TODO
  name = var.project
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: ECS Task Definition
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
#
# Task Definition 定義了容器的執行規格（類似 docker run 的參數）。
# container_definitions 已在 locals.tf 定義好，直接引用即可。
#
# 需要設定：
#   family                   = "${var.project}-task"
#   network_mode             = "awsvpc"         # Fargate 必須用 awsvpc
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = var.task_cpu     # 字串或數字皆可
#   memory                   = var.task_memory
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   container_definitions    = local.container_definitions
#   tags                     = local.common_tags
#
# ⚠️ Fargate 的 cpu/memory 只允許特定組合，例如：
#    cpu=256  → memory 可以是 512, 1024, 2048
#    cpu=512  → memory 可以是 1024~4096
#    完整列表: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size

resource "aws_ecs_task_definition" "app" {
  # TODO
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
# TODO 3: Security Group（允許 HTTP 進入 ECS task）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# 需要設定：
#   name        = "${var.project}-ecs-sg"
#   description = "Allow HTTP to ECS tasks"
#   vpc_id      = data.aws_vpc.default.id
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
#     protocol    = "-1"       # -1 = all protocols（允許所有對外流量，拉 image 需要）
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   tags = local.common_tags

resource "aws_security_group" "ecs_service" {
  # TODO
  name        = "${var.project}-ecs-sg"
  description = "Allow HTTP to ECS tasks"
  vpc_id      = data.aws_vpc.default.id

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

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: ECS Service
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
#
# ECS Service 會確保永遠有 desired_count 個 Task 在執行。
# 使用 Fargate 時必須設定 network_configuration。
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
#     assign_public_ip = true    # ← 沒有 ALB 時，直接給 Public IP 對外服務
#   }
#
#   tags = local.common_tags
#
# ⚠️ apply 完成後 ECS 還需要約 1-2 分鐘啟動 task（拉 image、啟動容器）。
#    用 aws ecs describe-tasks 或 Console 確認 task 狀態為 RUNNING。

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

  tags = local.common_tags
}
