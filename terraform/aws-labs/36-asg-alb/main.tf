#==============================================================
# 學習目標：Auto Scaling Group + ALB + Scaling Policy
#
# 核心問題：如何讓 EC2 根據流量自動水平擴展，並透過 ALB 分配請求？
#
# 架構關係（面試必考）：
#   Launch Template → 定義 EC2 的「藍圖」（AMI, instance type, SG, user_data）
#   Auto Scaling Group → 根據藍圖啟動 EC2，管理數量（min/max/desired）
#   Target Group → ASG 把 EC2 自動註冊進來，ALB 的流量目標
#   ALB → 接收外部流量，分配到 Target Group 中健康的 EC2
#   Scaling Policy → 根據 CPU / 請求數自動調整 ASG 的 desired_capacity
#
# 關鍵選擇（面試常考）：
#   health_check_type = "ELB"（非 "EC2"）
#     → "EC2" 只看 VM 狀態（開著就算健康）
#     → "ELB" 看 HTTP 200 回應（應用層健康才算健康），更準確
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：動態取得 Amazon Linux 2023 最新 AMI（預裝 httpd 套件來源）
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 已完成：動態取得當前 region 可用的 AZ（ALB 需要至少 2 個 AZ）
data "aws_availability_zones" "available" {
  state = "available"
}


#--------------------------------------------------------------
# TODO 1: VPC + 2 Public Subnets + IGW + Route Table
#--------------------------------------------------------------
# 文件 (vpc):                     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
# 文件 (subnet):                  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
# 文件 (internet_gateway):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
# 文件 (route_table):             https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
# 文件 (route_table_association): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
#
# [VPC]
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_hostnames = true   # EC2 取得 DNS 名稱，方便除錯
#   tags                 = local.common_tags
#
# [Subnet A]（第一個 AZ）
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.1.0/24"
#   availability_zone       = data.aws_availability_zones.available.names[0]
#   map_public_ip_on_launch = true
#   tags                    = merge(local.common_tags, { Name = "${var.project}-public-a" })
#
# [Subnet B]（第二個 AZ）
#   cidr_block        = "10.0.2.0/24"
#   availability_zone = data.aws_availability_zones.available.names[1]
#   （其餘同 Subnet A）
#
# [Internet Gateway]
#   vpc_id = aws_vpc.main.id
#   tags   = local.common_tags
#
# [Route Table]（0.0.0.0/0 → IGW）
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }
#   tags = local.common_tags
#
# [Route Table Association × 2]（兩個 Subnet 都關聯到同一個 Route Table）
#
# ⚠️ 注意：ALB 至少需要 2 個不同 AZ 的 Subnet，這是 AWS 的硬性限制

resource "aws_vpc" "main" {
  # TODO
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = local.common_tags
}

resource "aws_subnet" "public_a" {
  # TODO
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${var.project}-public-a" })
}

resource "aws_subnet" "public_b" {
  # TODO
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${var.project}-public-b" })
}

resource "aws_internet_gateway" "main" {
  # TODO
  vpc_id = aws_vpc.main.id
  tags   = local.common_tags
}

resource "aws_route_table" "public" {
  # TODO
  vpc_id = aws_vpc.main.id
  tags   = local.common_tags

  route {
    # TODO
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public_a" {
  # TODO
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  # TODO
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


#--------------------------------------------------------------
# TODO 2: Security Groups（ALB SG + EC2 SG）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# [ALB Security Group]（接收來自 Internet 的 HTTP 流量）
#   name        = "${var.project}-alb-sg"
#   description = "Allow HTTP from internet"
#   vpc_id      = aws_vpc.main.id
#   tags        = local.common_tags
#
#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#     description = "HTTP from internet"
#   }
#   egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
#
# [EC2 Security Group]（只允許來自 ALB SG 的流量，不開放給 Internet）
#   name        = "${var.project}-ec2-sg"
#   description = "Allow HTTP from ALB only"
#   vpc_id      = aws_vpc.main.id
#   tags        = local.common_tags
#
#   ingress {
#     from_port       = 80
#     to_port         = 80
#     protocol        = "tcp"
#     security_groups = [aws_security_group.alb.id]   ← 引用 ALB SG，非 CIDR！
#     description     = "HTTP from ALB"
#   }
#   egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
#
# ⚠️ 注意：EC2 SG 的 ingress 來源使用 security_groups（SG ID），不用 cidr_blocks
#          這是「最小權限」的實踐：只有來自 ALB 的流量才能到達 EC2
#          如果用 cidr_blocks = ["0.0.0.0/0"]，EC2 就等於直接暴露在網路上

resource "aws_security_group" "alb" {
  # TODO
  name        = "${var.project}-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.main.id
  tags        = local.common_tags

  ingress {
    # TODO
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  egress {
    # TODO
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  # TODO
  name        = "${var.project}-ec2-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.main.id
  tags        = local.common_tags

  ingress {
    # TODO
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB only"
  }

  egress {
    # TODO
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#--------------------------------------------------------------
# TODO 3: Launch Template（EC2 啟動藍圖）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template
#
#   name_prefix            = "${var.project}-"
#   image_id               = data.aws_ami.amazon_linux_2023.id
#   instance_type          = var.instance_type
#   vpc_security_group_ids = [aws_security_group.ec2.id]
#   tags                   = local.common_tags
#
#   user_data = base64encode(<<-EOF
#     #!/bin/bash
#     yum install -y httpd
#     systemctl start httpd
#     systemctl enable httpd
#     EC2_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
#     AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
#     echo "<h1>Hello from $EC2_ID ($AZ)</h1>" > /var/www/html/index.html
#   EOF
#   )
#
#   tag_specifications {
#     resource_type = "instance"
#     tags          = merge(local.common_tags, { Name = "${var.project}-web" })
#   }
#
# ⚠️ 注意：Launch Template 使用 name_prefix（非 name），Terraform 會自動加唯一後綴
#          user_data 必須 base64encode，EC2 metadata IP 169.254.169.254 是固定的

resource "aws_launch_template" "web" {
  # TODO
  name_prefix            = "${var.project}-"
  image_id               = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2.id]
  tags                   = local.common_tags

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    EC2_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    echo "<h1>Hello from $EC2_ID ($AZ)</h1>" > /var/www/html/index.html
  EOF
  )

  tag_specifications {
    # TODO
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.project}-web" })
  }
}


#--------------------------------------------------------------
# TODO 4: Target Group + ALB + Listener
#--------------------------------------------------------------
# 文件 (target_group): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
# 文件 (lb):           https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
# 文件 (listener):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
#
# [Target Group]
#   name        = "${var.project}-tg"
#   port        = 80
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.main.id
#   target_type = "instance"
#   tags        = local.common_tags
#
#   health_check {
#     enabled             = true
#     path                = "/"
#     protocol            = "HTTP"
#     healthy_threshold   = 2
#     unhealthy_threshold = 3
#     interval            = 30
#     timeout             = 5
#     matcher             = "200"
#   }
#
# [Application Load Balancer]
#   name               = "${var.project}-alb"
#   internal           = false          # 面向 Internet（非 internal）
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb.id]
#   subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
#   tags               = local.common_tags
#
# [Listener]（Port 80 → 轉發到 Target Group）
#   load_balancer_arn = aws_lb.main.arn
#   port              = "80"
#   protocol          = "HTTP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.web.arn
#   }
#
# ⚠️ 注意：ALB 需要等待 2-3 分鐘才能完全啟動，state 顯示 active 才可測試

resource "aws_lb_target_group" "web" {
  # TODO
  name        = "${var.project}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  tags        = local.common_tags

  health_check {
    # TODO
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb" "main" {
  # TODO
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = local.common_tags
}

resource "aws_lb_listener" "http" {
  # TODO
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    # TODO
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}


#--------------------------------------------------------------
# TODO 5: Auto Scaling Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
#
#   name                      = "${var.project}-asg"
#   min_size                  = 1
#   max_size                  = 3
#   desired_capacity          = 2
#   vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
#   target_group_arns         = [aws_lb_target_group.web.arn]
#   health_check_type         = "ELB"    ← 使用 ALB Health Check（應用層）
#   health_check_grace_period = 300      ← 300 秒內不做 health check（等待 user_data 完成）
#
#   launch_template {
#     id      = aws_launch_template.web.id
#     version = "$Latest"               ← 永遠用最新版本的 Launch Template
#   }
#
#   tag {
#     key                 = "Name"
#     value               = "${var.project}-web"
#     propagate_at_launch = true        ← 這個 tag 傳給 ASG 啟動的每個 EC2
#   }
#
# ⚠️ 注意：health_check_grace_period 很重要
#          如果太短，EC2 還在跑 user_data 就被 ASG 認為不健康並終止，陷入無限啟動循環
#          t3.micro 上 user_data 完成通常需要 60-120 秒

resource "aws_autoscaling_group" "web" {
  # TODO
  name                      = "${var.project}-asg"
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    # TODO
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    # TODO
    key                 = "Name"
    value               = "${var.project}-web"
    propagate_at_launch = true
  }
}


#--------------------------------------------------------------
# TODO 6: Target Tracking Scaling Policy（CPU 自動擴縮）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy
#
#   name                   = "${var.project}-cpu-tracking"
#   autoscaling_group_name = aws_autoscaling_group.web.name
#   policy_type            = "TargetTrackingScaling"
#
#   target_tracking_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ASGAverageCPUUtilization"  # 監控 ASG 平均 CPU
#     }
#     target_value = 50.0   # 目標：維持平均 CPU 在 50%
#                           # CPU > 50% → Scale Out（加 EC2）
#                           # CPU < 50% → Scale In（減 EC2，有 cooldown）
#   }
#
# ⚠️ 注意：Target Tracking 是最簡單的策略，AWS 自動計算 Scale Out / Scale In 觸發點
#          三種策略比較（面試常考）：
#          ┌────────────────────┬─────────────────────────────────────────┐
#          │ Simple Scaling     │ 手動設定 Add/Remove N 台，有 cooldown   │
#          │ Step Scaling       │ 根據 Alarm breached 幅度分段調整台數    │
#          │ Target Tracking    │ 設定目標值，AWS 自動決定調整幅度（推薦）│
#          └────────────────────┴─────────────────────────────────────────┘

resource "aws_autoscaling_policy" "cpu_tracking" {
  # TODO
  name                   = "${var.project}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      # TODO
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    # TODO
    target_value = 50.0
  }
}
