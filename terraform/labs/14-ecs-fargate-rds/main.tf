#==============================================================
# 學習目標：ECS Fargate + RDS PostgreSQL 整合
#
# 與前面 Lab 的差異：
#   Lab 11-12：ECS 跑靜態 nginx，無資料庫
#   Lab 14（本 lab）：ECS 跑 Flask app，透過 Security Group 連接 RDS
#
# ⭐ 新概念：
#   1. 三層 Security Group 鏈：Internet → ALB → ECS → RDS
#      每一層只允許來自「上一層 SG」的流量（不開放 0.0.0.0/0）
#
#   2. Task Definition 的 environment block
#      把 RDS endpoint、帳密以環境變數注入容器
#      （生產環境改用 secrets block + Secrets Manager）
#
#   3. DB Subnet Group：RDS 需要跨越至少 2 個 AZ 的 Subnet Group
#
# ⚠️ 費用警告：RDS 約 $0.017/hr，apply 完馬上操作，操作完立刻 destroy！
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
# ECS Cluster
#--------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = var.project
  tags = local.common_tags
}


#--------------------------------------------------------------
# ALB Security Group（已學過）
#--------------------------------------------------------------
resource "aws_security_group" "alb" {
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
# ALB + Target Group + Listener（已學過）
#--------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
  tags               = local.common_tags
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}


#--------------------------------------------------------------
# ECS Service（已學過）
#--------------------------------------------------------------
resource "aws_ecs_service" "app" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.common_tags
}


#==============================================================
# ↓ 以下是本 Lab 的新內容，請填寫 TODO
#==============================================================


#--------------------------------------------------------------
# TODO 1: ECS Service Security Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# ⭐ 本 Lab 的 ECS SG 有兩個方向需要設定：
#
#   Ingress：只接受來自 ALB SG 的流量（SG-to-SG，Lab 12 概念複習）
#     from_port       = var.container_port   # 5000
#     security_groups = [aws_security_group.alb.id]
#
#   Egress（需要兩條）：
#     1. 對外全開（拉 ECR image 需要）：protocol="-1", cidr="0.0.0.0/0"
#     2. 連接 RDS：
#        from_port       = 5432
#        to_port         = 5432
#        protocol        = "tcp"
#        security_groups = [aws_security_group.rds.id]  ← 指向 RDS SG
#
# 需要設定：
#   name        = "${var.project}-ecs-sg"
#   description = "ECS tasks: allow from ALB, allow egress to RDS"
#   vpc_id      = data.aws_vpc.default.id
#   tags        = local.common_tags
#
# ⚠️ 注意：Egress 需要兩個 egress block（不能合併成一個）

resource "aws_security_group" "ecs" {
  # TODO
  name        = "${var.project}-ecs-sg"
  description = "ECS tasks: allow from ALB, allow egress to RDS"
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
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: RDS Security Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# ⭐ RDS 只接受來自 ECS Task 的連線（port 5432）。
#    不對外開放，不接受 0.0.0.0/0。
#
# 需要設定：
#   name        = "${var.project}-rds-sg"
#   description = "RDS: allow PostgreSQL from ECS tasks only"
#   vpc_id      = data.aws_vpc.default.id
#
#   ingress {
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs.id]   # ← 只允許來自 ECS SG
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

resource "aws_security_group" "rds" {
  # TODO
  name        = "${var.project}-rds-sg"
  description = "RDS: allow PostgreSQL from ECS tasks only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.common_tags
}

#--------------------------------------------------------------
# RDS Security Group Ingress Rule（分開定義以避免 Cycle）
#--------------------------------------------------------------
resource "aws_security_group_rule" "rds_ingress_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.rds.id
}


#--------------------------------------------------------------
# TODO 3: RDS DB Subnet Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
#
# RDS 必須放在 Subnet Group 中（即使用 Default VPC 也需要）。
# Subnet Group 必須跨越至少 2 個 AZ。
#
# 需要設定：
#   name       = "${var.project}-db-subnet-group"
#   subnet_ids = data.aws_subnets.default.ids   # Default VPC 的 subnet 已跨多 AZ
#   tags       = local.common_tags

resource "aws_db_subnet_group" "main" {
  # TODO
  name       = "${var.project}-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  tags       = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: RDS PostgreSQL Instance
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
#
# 需要設定：
#   identifier        = "${var.project}-db"
#   engine            = "postgres"
#   engine_version    = "16"
#   instance_class    = "db.t3.micro"
#   allocated_storage = 20
#
#   db_name  = var.db_name
#   username = var.db_username
#   password = var.db_password
#
#   db_subnet_group_name   = aws_db_subnet_group.main.name
#   vpc_security_group_ids = [aws_security_group.rds.id]
#
#   publicly_accessible = false   # 不對外開放！只透過 Security Group 讓 ECS 存取
#   skip_final_snapshot = true    # Lab 用，destroy 時不留 snapshot
#
#   tags = local.common_tags
#
# ⚠️ RDS 啟動約需 5-10 分鐘，apply 時請耐心等候。

resource "aws_db_instance" "postgres" {
  # TODO
  identifier        = "${var.project}-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 5: ECS Task Definition（含 DB 環境變數）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
#
# ⭐ 本 Lab 最重要的概念：用 environment block 把 RDS 連線資訊注入容器
#
# 需要設定：
#   family                   = "${var.project}-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = var.task_cpu
#   memory                   = var.task_memory
#   execution_role_arn       = aws_iam_role.ecs_task_execution.arn
#   tags                     = local.common_tags
#
#   container_definitions = jsonencode([{
#     name      = var.container_name
#     image     = var.ecr_image_url
#     essential = true
#     portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
#
#     environment = [
#       { name = "DB_HOST",     value = aws_db_instance.postgres.address },
#       { name = "DB_PORT",     value = "5432" },
#       { name = "DB_NAME",     value = var.db_name },
#       { name = "DB_USER",     value = var.db_username },
#       { name = "DB_PASSWORD", value = var.db_password },
#     ]
#
#     logConfiguration = {
#       logDriver = "awslogs"
#       options = {
#         "awslogs-group"         = "/ecs/${var.project}"
#         "awslogs-region"        = var.region
#         "awslogs-stream-prefix" = "ecs"
#       }
#     }
#   }])
#
# ⚠️ 注意：這裡用 environment（明文），適合 Lab 練習。
#    生產環境改用 secrets block + AWS Secrets Manager（不會出現在 Console 或 Log）。

resource "aws_ecs_task_definition" "app" {
  # TODO
  family                   = "${var.project}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  tags                     = local.common_tags

  container_definitions = jsonencode([{
    name         = var.container_name
    image        = var.ecr_image_url
    essential    = true
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    environment = [
      { name = "DB_HOST", value = aws_db_instance.postgres.address },
      { name = "DB_PORT", value = "5432" },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_username },
      { name = "DB_PASSWORD", value = var.db_password },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project}"
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
