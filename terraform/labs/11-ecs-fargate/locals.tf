locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Container definition JSON
  # 傳給 aws_ecs_task_definition 的 container_definitions 引數
  # 定義了容器 image、port mapping、以及 CloudWatch Logs 設定
  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.ecr_image_url
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}
