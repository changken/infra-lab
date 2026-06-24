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
#
# deployment_controller = "CODE_DEPLOY"：
#   - 停用 ECS rolling update，改由 CodeDeploy 控制 Blue/Green 切換
#   - 不相容：deployment_circuit_breaker、deployment_min/max_percent
#   - CodeDeploy 負責：task 啟動、health check、流量切換、舊 task 清除
#
# ⚠️ 注意：從 ECS rolling 改成 CODE_DEPLOY 需要重建 Service（ForceNew）

resource "aws_ecs_service" "app" {
  name                   = "${local.name_prefix}-app-service"
  cluster                = aws_ecs_cluster.main.arn
  task_definition        = aws_ecs_task_definition.app.arn
  desired_count          = var.service_desired_count
  enable_execute_command = true

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  # Blue TG 為初始生產目標；CodeDeploy 部署後會自動切換
  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_iam_role_policy_attachment.task_execution_secrets,
  ]

  tags = local.common_tags

  lifecycle {
    # task_definition 和 load_balancer 由 CodeDeploy 管理，Terraform 不應覆蓋
    # desired_count 由 Application Auto Scaling 管理
    ignore_changes = [task_definition, load_balancer, desired_count]
  }
}
