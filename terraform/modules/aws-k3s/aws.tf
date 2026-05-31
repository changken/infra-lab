data "aws_caller_identity" "current" {}

# ============================================================================
# AWS EC2 + K3s Lab
# ============================================================================
# This file contains AWS resources for a K3s node that will join the same
# Tailscale network as the Azure VM.
# ============================================================================

# 1. VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "my-k3s-lab-vpc"
    Project = "k3s-lab"
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "my-k3s-lab-igw"
    Project = "k3s-lab"
  }
}

# 3. Subnet
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = var.aws_availability_zone != "" ? var.aws_availability_zone : null
  map_public_ip_on_launch = false # No public IP, Tailscale only

  tags = {
    Name    = "my-k3s-lab-subnet"
    Project = "k3s-lab"
  }
}

# 4. Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "my-k3s-lab-rt"
    Project = "k3s-lab"
  }
}

# 5. Route Table Association
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# 6. Security Group (Tailscale-first, minimal rules)
resource "aws_security_group" "k3s" {
  name        = "my-k3s-lab-sg"
  description = "Security group for K3s node (Tailscale-first access)"
  vpc_id      = aws_vpc.main.id

  # Egress: Allow all outbound (for apt, K3s, Tailscale)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # K3s API server — inter-node (self) and kubectl from outside
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
    description = "K3s API server (inter-node)"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "K3s API server (kubectl access)"
  }

  # Flannel VXLAN — pod network overlay
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
    description = "Flannel VXLAN (pod network)"
  }

  # Kubelet — health checks between nodes
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet metrics"
  }

  # Optional: Emergency SSH (uncomment if needed)
  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["YOUR_IP/32"]
  #   description = "Emergency SSH access"
  # }

  tags = {
    Name    = "my-k3s-lab-sg"
    Project = "k3s-lab"
  }
}

# ============================================================================
# IAM Role for K3s nodes (SSM Parameter Store access)
# ============================================================================

resource "aws_iam_role" "k3s_node" {
  name = "my-k3s-lab-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "my-k3s-lab-node-role"
    Project = "k3s-lab"
  }
}

resource "aws_iam_role_policy" "k3s_ssm" {
  name = "my-k3s-lab-ssm-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:DeleteParameter"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/k3s-lab/node-token"
    }]
  })
}

resource "aws_iam_instance_profile" "k3s_node" {
  name = "my-k3s-lab-node-profile"
  role = aws_iam_role.k3s_node.name

  tags = {
    Name    = "my-k3s-lab-node-profile"
    Project = "k3s-lab"
  }
}

# 7. SSH Key Pair
resource "aws_key_pair" "emergency" {
  key_name   = "my-k3s-lab-emergency-key"
  public_key = file(pathexpand(var.aws_ssh_public_key_path))

  tags = {
    Name    = "my-k3s-lab-emergency-key"
    Project = "k3s-lab"
  }
}

# 8. EC2 Instance
resource "aws_instance" "k3s" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.aws_instance_type
  key_name      = aws_key_pair.emergency.key_name

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true # Needed for initial Tailscale setup

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 64
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name    = "my-k3s-vm-aws-root"
      Project = "k3s-lab"
    }
  }

  user_data = templatefile("${path.module}/user-data-aws.sh", {
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = "my-k3s-vm-aws"
  })

  metadata_options {
    http_tokens   = "required" # Enforce IMDSv2
    http_endpoint = "enabled"
  }

  tags = {
    Name    = "my-k3s-vm-aws"
    Project = "k3s-lab"
  }
}

# 9. Data Source: Latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
