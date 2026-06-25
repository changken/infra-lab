#==============================================================
# Scheduled Task（EventBridge Scheduler → ECS RunTask）
#
# 對比 Kubernetes CronJob：
#   K8s CronJob:   CronJob YAML → JobController → Pod（跑完自動刪）
#   ECS Scheduled: EventBridge Scheduler → ECS RunTask → Task（跑完自動刪）
#
# 優點：
#   - Task 跑完自動終止，不佔常駐費用
#   - 與 ECS Service 無關，Task Definition 可獨立管理
#   - 同一個 image，用不同 CMD 區分 server / job
#==============================================================

# ── IAM：授權 EventBridge Scheduler 執行 ECS Task ───────────

resource "aws_iam_role" "scheduler" {
  name = "${local.name_prefix}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "run-ecs-task"
  role = aws_iam_role.scheduler.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunTask"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = [aws_ecs_task_definition.job.arn]
        Condition = {
          ArnLike = { "ecs:cluster" = aws_ecs_cluster.main.arn }
        }
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.task_execution.arn,
          aws_iam_role.task.arn,
        ]
      }
    ]
  })
}

# ── Task Definition（Job）────────────────────────────────────
# 同一個 ECR image，但 command 換成 /app/job
# 不需要 portMappings 和 healthCheck（跑完就退出）

resource "aws_ecs_task_definition" "job" {
  family                   = "${local.name_prefix}-job"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "job"
    image     = var.container_image
    command   = ["/app/job"]
    essential = true

    environment = [
      { name = "APP_VERSION", value = var.app_version },
      { name = "AWS_REGION",  value = var.region },
    ]

    secrets = [{
      name      = "API_KEY"
      valueFrom = "${aws_secretsmanager_secret.app_config.arn}:API_KEY::"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "job"  # 與 app stream 區分
      }
    }
  }])

  tags = local.common_tags
}

# ── EventBridge Scheduler ────────────────────────────────────
# 每 5 分鐘跑一次 job（lab 觀察用，生產通常設每小時/每天）

resource "aws_scheduler_schedule" "job" {
  name       = "${local.name_prefix}-job"
  group_name = "default"

  flexible_time_window {
    mode = "OFF" # 精確執行，不允許時間浮動
  }

  schedule_expression          = "rate(5 minutes)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.job.arn
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = [for s in aws_subnet.public : s.id]
        security_groups  = [aws_security_group.ecs_tasks.id]
        assign_public_ip = true
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = 300 # 失敗後最多重試 5 分鐘內
      maximum_retry_attempts       = 1
    }
  }
}
