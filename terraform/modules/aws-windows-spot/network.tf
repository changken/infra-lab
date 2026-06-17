# ---------- Networking (Default VPC) ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "win2025" {
  name_prefix = "${var.name_prefix}-"
  vpc_id      = data.aws_vpc.default.id

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
