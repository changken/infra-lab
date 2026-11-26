#==============================================================
# 學習目標：SSM Session Manager + Patch Manager
#
# 核心問題：如何在完全沒有 SSH port 的情況下安全連進 EC2？
#
# Session Manager 原理（面試必考）：
#   EC2 上的 SSM Agent 主動建立出站 HTTPS 連線到 SSM 服務
#   → 不需任何 inbound port，不需 Bastion Host，不需 VPN
#   → 連線紀錄自動寫入 CloudTrail / CloudWatch（合規友善）
#
# Patch Manager 架構（4 個資源）：
#   aws_ssm_patch_baseline        → 定義哪些 CVE 等級要修補
#   aws_ssm_maintenance_window    → 定義維護排程（rate / cron）
#   aws_ssm_maintenance_window_target → 定義目標 EC2（tag 篩選）
#   aws_ssm_maintenance_window_task   → 定義執行的 SSM Document
#
# Public Subnet + IGW vs VPC Endpoint：
#   VPC Endpoint 需要 3 個（ssm、ec2messages、ssmmessages）
#   每個 $0.01/hr → lab 環境不必要
#   Public Subnet 提供免費出站路徑，EC2 需要 Public IP
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：動態取得 Amazon Linux 2023 最新 AMI
# Amazon Linux 2023 預裝 SSM Agent，不需額外安裝
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}


#--------------------------------------------------------------
# TODO 1: VPC + Public Subnet + IGW + Route Table
#--------------------------------------------------------------
# 文件 (vpc):                   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
# 文件 (subnet):                https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
# 文件 (internet_gateway):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
# 文件 (route_table):           https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
# 文件 (route_table_association): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
#
# [VPC]
#   cidr_block = "10.0.0.0/16"
#   tags       = local.common_tags
#
# [Subnet]
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.1.0/24"
#   map_public_ip_on_launch = true   # ← EC2 自動取得 Public IP，才能出站連 SSM
#   tags                    = local.common_tags
#
# [Internet Gateway]
#   vpc_id = aws_vpc.main.id
#   tags   = local.common_tags
#
# [Route Table]（Public 路由：0.0.0.0/0 → IGW）
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }
#   tags = local.common_tags
#
# [Route Table Association]
#   subnet_id      = aws_subnet.public.id
#   route_table_id = aws_route_table.public.id

resource "aws_vpc" "main" {
  # TODO
  cidr_block = "10.0.0.0/16"
  tags       = local.common_tags
}

resource "aws_subnet" "public" {
  # TODO
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # ← EC2 自動取得 Public IP，才能出站連 SSM
  tags                    = local.common_tags
}

resource "aws_internet_gateway" "main" {
  # TODO
  vpc_id = aws_vpc.main.id
  tags   = local.common_tags
}

resource "aws_route_table" "public" {
  # TODO
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = local.common_tags
}

resource "aws_route_table_association" "public" {
  # TODO
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


#--------------------------------------------------------------
# TODO 2: Security Group（無任何 inbound 規則，outbound HTTPS 443）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
#   name        = "${var.project}-ec2-sg"
#   description = "No inbound - SSM Session Manager only"
#   vpc_id      = aws_vpc.main.id
#   tags        = local.common_tags
#
# ⚠️ 注意：inbound 區塊完全不加（或留空 ingress = []）
#         這是本 lab 的核心重點：Security Group 零 inbound，SSH 22 完全關閉
#
# [Egress：HTTPS 443 到 SSM Endpoint]
#   egress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#     description = "HTTPS to SSM endpoints"
#   }

resource "aws_security_group" "ec2" {
  # TODO
  name        = "${var.project}-ec2-sg"
  description = "No inbound - SSM Session Manager only"
  vpc_id      = aws_vpc.main.id
  tags        = local.common_tags

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to SSM endpoints"
  }
}


#--------------------------------------------------------------
# TODO 3: IAM Role + Instance Profile（AmazonSSMManagedInstanceCore）
#--------------------------------------------------------------
# 文件 (role):             https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (policy_attachment): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
# 文件 (instance_profile): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
#
# [IAM Role]（EC2 使用）
#   name = "${var.project}-ec2-role"
#   tags = local.common_tags
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
# [Policy Attachment：SSM Core]
#   role       = aws_iam_role.ec2_ssm.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#   # ← 此受管政策包含 Session Manager + Patch Manager 所需全部 SSM 權限
#
# [Instance Profile]（將 Role 綁定給 EC2）
#   name = "${var.project}-ec2-profile"
#   role = aws_iam_role.ec2_ssm.name
#   tags = local.common_tags
#
# ⚠️ 注意：EC2 需要透過 Instance Profile 取得 Role，直接指定 Role ARN 不夠

resource "aws_iam_role" "ec2_ssm" {
  # TODO
  name = "${var.project}-ec2-role"
  tags = local.common_tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  # TODO
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  # TODO
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_ssm.name
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: EC2 Instance（Amazon Linux 2023, t3.micro）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
#
#   ami                    = data.aws_ami.amazon_linux_2023.id
#   instance_type          = "t3.micro"
#   subnet_id              = aws_subnet.public.id
#   vpc_security_group_ids = [aws_security_group.ec2.id]
#   iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
#   tags                   = merge(local.common_tags, {
#     Name       = "${var.project}-ssm-target"
#     PatchGroup = var.project   # ← Patch Manager Target 會用此 tag 篩選
#   })
#
# ⚠️ 注意：不要加 key_name（沒有 SSH key）、不要加 associate_public_ip_address
#         Public IP 由 Subnet 的 map_public_ip_on_launch = true 自動指派

resource "aws_instance" "ssm_target" {
  # TODO
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  tags = merge(local.common_tags, {
    Name       = "${var.project}-ssm-target"
    PatchGroup = var.project # ← Patch Manager Target 會用此 tag 篩選
  })
}


#--------------------------------------------------------------
# TODO 5: SSM Patch Baseline（Amazon Linux 2023）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_patch_baseline
#
#   name             = "${var.project}-baseline"
#   description      = "Patch baseline for Amazon Linux 2023"
#   operating_system = "AMAZON_LINUX_2023"
#   tags             = local.common_tags
#
#   approval_rule {
#     approve_after_days = 7   # ← 修補釋出 7 天後自動核准
#     compliance_level   = "HIGH"
#
#     patch_filter {
#       key    = "PRODUCT"
#       values = ["AmazonLinux2023"]
#     }
#
#     patch_filter {
#       key    = "CLASSIFICATION"
#       values = ["Security", "Bugfix"]
#     }
#
#     patch_filter {
#       key    = "SEVERITY"
#       values = ["Critical", "Important"]
#     }
#   }

resource "aws_ssm_patch_baseline" "amazon_linux_2023" {
  # TODO
  name             = "${var.project}-baseline"
  description      = "Patch baseline for Amazon Linux 2023"
  operating_system = "AMAZON_LINUX_2023"
  tags             = local.common_tags

  approval_rule {
    approve_after_days = 7 # ← 修補釋出 7 天後自動核准
    compliance_level   = "HIGH"

    patch_filter {
      key    = "PRODUCT"
      values = ["AmazonLinux2023"]
    }

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }
}


#--------------------------------------------------------------
# TODO 6: Maintenance Window + Target + Task（每 7 天掃描）
#--------------------------------------------------------------
# 文件 (window):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window
# 文件 (target):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_target
# 文件 (task):    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_task
#
# [Maintenance Window]
#   name              = "${var.project}-window"
#   schedule          = "rate(7 days)"   # ← lab 使用 rate 語法；生產環境常用 cron
#   duration          = 2                # ← 維護視窗持續 2 小時
#   cutoff            = 1                # ← 截止前 1 小時停止啟動新任務
#   allow_unassociated_targets = false
#   tags              = local.common_tags
#
# [Window Target]（指定要修補的 EC2）
#   window_id     = aws_ssm_maintenance_window.weekly.id
#   name          = "${var.project}-target"
#   resource_type = "INSTANCE"
#
#   targets {
#     key    = "tag:PatchGroup"       # ← 比對 EC2 tag PatchGroup
#     values = [var.project]          # ← 只有 PatchGroup = "ssm-lab" 的 EC2
#   }
#
# [Window Task]（執行 Patch Scan）
#   window_id        = aws_ssm_maintenance_window.weekly.id
#   name             = "${var.project}-patch-scan"
#   task_arn         = "arn:aws:ssm:${var.region}::document/AWS-RunPatchBaseline"
#   task_type        = "RUN_COMMAND"
#   # service_role_arn is optional for RUN_COMMAND tasks and can be omitted
#   priority         = 1
#   max_concurrency  = "1"
#   max_errors       = "1"
#
#   targets {
#     key    = "WindowTargetIds"
#     values = [aws_ssm_maintenance_window_target.ec2.id]
#   }
#
#   task_invocation_parameters {
#     run_command_parameters {
#       document_version = "$DEFAULT"
#
#       parameter {
#         name   = "Operation"
#         values = ["Scan"]   # ← Scan 只檢查不安裝；生產環境改 "Install"
#       }
#     }
#   }
#
# ⚠️ 注意：task_arn 的 document ARN 格式為
#          arn:aws:ssm:{region}::document/AWS-RunPatchBaseline（雙冒號 ::，無帳號 ID）

resource "aws_ssm_maintenance_window" "weekly" {
  # TODO
  name                       = "${var.project}-window"
  schedule                   = "rate(7 days)" # ← lab 使用 rate 語法；生產環境常用 cron
  duration                   = 2              # ← 維護視窗持續 2 小時
  cutoff                     = 1              # ← 截止前 1 小時停止啟動新任務
  allow_unassociated_targets = false
  tags                       = local.common_tags
}

resource "aws_ssm_maintenance_window_target" "ec2" {
  # TODO
  window_id     = aws_ssm_maintenance_window.weekly.id
  name          = "${var.project}-target"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup" # ← 比對 EC2 tag PatchGroup
    values = [var.project]    # ← 只有 PatchGroup = "ssm-lab" 的 EC2
  }
}

resource "aws_ssm_maintenance_window_task" "patch_scan" {
  # TODO
  window_id       = aws_ssm_maintenance_window.weekly.id
  name            = "${var.project}-patch-scan"
  task_arn        = "arn:aws:ssm:${var.region}::document/AWS-RunPatchBaseline" # ← 注意雙冒號
  task_type       = "RUN_COMMAND"
  priority        = 1
  max_concurrency = "1"
  max_errors      = "1"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.ec2.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      document_version = "$DEFAULT"

      parameter {
        name   = "Operation"
        values = ["Scan"] # ← Scan 只檢查不安裝；生產環境改 "Install"
      }
    }
  }
}
