#==============================================================
# Application Load Balancer
#
# ALB → Target Group → ECS Service（awsvpc mode）
# awsvpc mode：每個 Fargate task 有獨立 ENI 和 IP
#              ALB 直接路由到 task IP（不經 NodePort）
#              比 EKS NodePort 更乾淨，沒有 kube-proxy overhead
#==============================================================

# ── Security Group: ALB ─────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
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

  # 出口需要全開：pull ECR image、呼叫 Secrets Manager、寫 CloudWatch
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

# ── Target Group ─────────────────────────────────────────────
# target_type = "ip"：直連 task ENI IP（awsvpc mode 必須用 ip）

resource "aws_lb_target_group" "app" {
  name_prefix = "ecs-tg"  # 用 prefix + 隨機後綴，create_before_destroy 才不會衝名
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

  tags = local.common_tags

  lifecycle {
    # 先建新 TG → Listener 指向新 TG → 再刪舊 TG
    # 避免「TG 還被 Listener 使用、無法刪除」的錯誤
    create_before_destroy = true
  }
}

# ── Listener ─────────────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = local.common_tags
}
