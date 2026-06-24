#==============================================================
# ECS Cluster + Task Definition + Service
#
# 核心概念對比 EKS：
#   EKS Deployment → ECS Service
#   K8s Pod         → ECS Task
#   K8s Container   → ECS Container Definition
#   K8s Node (EC2)  → Fargate（無 Node 概念）
#   kubectl exec    → aws ecs execute-command
#   kubectl logs    → aws logs tail（CloudWatch）
#==============================================================

# ── ECS Cluster ─────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── Task Definition ──────────────────────────────────────────
# ECS 的「Pod spec」等價物
# CPU/Memory 在 task 層級宣告（Fargate 按此計費）

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  network_mode             = "awsvpc" # Fargate 只支援 awsvpc
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT", value = tostring(var.container_port) },
      { name = "APP_VERSION", value = var.app_version },
      { name = "AWS_REGION", value = var.region },
    ]

    # Secrets Manager 原生注入：ECS agent 在 task 啟動時讀取，注入為環境變數
    # valueFrom 格式：{secret_arn}:{json_key}::
    # 對比 EKS ESO：ExternalSecret → K8s Secret → envFrom
    secrets = [
      {
        name      = "API_KEY"
        valueFrom = "${aws_secretsmanager_secret.app_config.arn}:API_KEY::"
      },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:${var.container_port}/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])

  tags = local.common_tags
}

# ── ECS Service ──────────────────────────────────────────────

resource "aws_ecs_service" "app" {
  name                   = "${local.name_prefix}-app-service"
  cluster                = aws_ecs_cluster.main.arn
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.service_desired_count
  enable_execute_command = true # 允許 aws ecs execute-command（類似 kubectl exec）

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true # 無 NAT Gateway：task 需要 public IP 出外網
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_iam_role_policy_attachment.task_execution_secrets,
  ]

  tags = local.common_tags

  lifecycle {
    # desired_count 由 Auto Scaling 管理；task_definition 由 Terraform 管理
    # 待 GitHub Actions CI/CD 設好後，可加回 task_definition
    ignore_changes = [desired_count]
  }
}
