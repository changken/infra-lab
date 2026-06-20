# ---------- Networking ----------
# 支援兩種模式：
#   1. Default VPC 模式：vpc_id = null（原有行為，不需額外設定）
#   2. 自訂 VPC 模式：  vpc_id = "vpc-xxx"（與 aws-vpc 模組搭配使用）
#
# 注意：data source 不使用 count，避免 apply-time 值導致
#       "Invalid count argument" 錯誤（Terraform 要求 count 在 plan 階段靜態可知）

# ── Default VPC（始終宣告，由 locals 判斷是否實際使用）─────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── 解析實際使用的 VPC / Subnet ───────────────────────────
# 若呼叫端傳入 vpc_id / subnet_id，優先使用；否則 fallback 到 Default VPC

locals {
  resolved_vpc_id    = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default.id
  resolved_subnet_id = var.subnet_id != null ? var.subnet_id : data.aws_subnets.default.ids[0]
}

# ── Security Group ─────────────────────────────────────────

resource "aws_security_group" "win2025" {
  name_prefix = "${var.name_prefix}-"
  vpc_id      = local.resolved_vpc_id

  ingress {
    description = "RDP from my IP only"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
