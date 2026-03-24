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
  name_prefix = "win2025-"
  vpc_id      = data.aws_vpc.default.id

  # RDP - 建議鎖 IP，別開 0.0.0.0/0
  ingress {
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

  tags = { Name = "win2025-sg" }
}
