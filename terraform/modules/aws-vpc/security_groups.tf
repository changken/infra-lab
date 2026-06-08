#--------------------------------------------------------------
# Security Group for k3s nodes
#--------------------------------------------------------------
resource "aws_security_group" "k3s_nodes" {
  name        = "k3s-nodes-sg"
  description = "Security group for k3s nodes"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.personal_pc_cidr]
  }

  # k3s API server
  ingress {
    description = "k3s API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.personal_pc_cidr]
  }

  # k3s agent communication
  ingress {
    description = "k3s agent communication"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.personal_pc_cidr]
  }

  # Flannel VXLAN
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr, var.personal_pc_cidr]
  }

  # myvue3app
  ingress {
    description = "myvue3app"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.personal_pc_cidr]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "k3s-nodes-sg"
  })
}

#--------------------------------------------------------------
# Security Group for internal communication
#--------------------------------------------------------------
resource "aws_security_group" "internal" {
  name        = "internal-sg"
  description = "Security group for internal communication"
  vpc_id      = aws_vpc.main.id

  # Allow all internal traffic
  ingress {
    description = "Internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "internal-sg"
  })
}
