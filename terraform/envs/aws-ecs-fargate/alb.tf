#==============================================================
# Application Load Balancer + Blue/Green Target Groups
#
# Rolling deploy（原本）：
#   ALB → 1 個 TG → ECS 自己滾動換 task
#
# Blue/Green（現在）：
#   Port 80  → Production Listener → Blue TG（當前生產版本）
#   Port 8080 → Test Listener      → Green TG（新版本預覽）
#
#   CodeDeploy 部署時：
#     1. 啟動新 task → 註冊到 Green TG
#     2. 健康檢查通過 → 透過 Test Listener 驗證
#     3. 切換：Production Listener 指向 Green TG
#     4. 等 5 分鐘 → 刪除舊 Blue tasks
#==============================================================

# ── Security Group: ALB ─────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Production traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Test traffic (Green TG preview before cutover)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to ECS tasks"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

# ── Security Group: ECS Tasks ───────────────────────────────

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB only"
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

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-tasks-sg" })
}

# ── ALB ─────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = local.common_tags
}

# ── Blue Target Group（當前生產版本）────────────────────────

resource "aws_lb_target_group" "blue" {
  name        = "${local.name_prefix}-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-blue" })
}

# ── Green Target Group（新版本，部署期間使用）───────────────

resource "aws_lb_target_group" "green" {
  name        = "${local.name_prefix}-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-green" })
}

# ── Production Listener（:80 → Blue TG）─────────────────────
# CodeDeploy 部署完成後會把此 Listener 改指向 Green TG

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  tags = local.common_tags
}

# ── Test Listener（:8080 → Green TG）────────────────────────
# 部署期間可用此 port 測試新版本，traffic 切換前驗證

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  tags = local.common_tags
}
