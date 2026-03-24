#--------------------------------------------------------------
# Data Sources
#--------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#--------------------------------------------------------------
# Networking
#--------------------------------------------------------------

resource "aws_default_subnet" "default_az1" {
  availability_zone = var.availability_zone

  tags = merge(local.common_tags, {
    Name = "Default subnet for ${var.availability_zone}"
  })
}

resource "aws_security_group" "web_sg" {
  name        = "web-security-group"
  description = "Security Group for web server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH access from my IP"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "web-server-sg"
  })
}

#--------------------------------------------------------------
# SSH Key Pair
#--------------------------------------------------------------

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_keypair" {
  key_name   = var.key_name
  public_key = tls_private_key.ec2_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/${var.key_name}.pem"
  file_permission = "0600"
}

# Alternative: Use existing SSH key from local machine
/*resource "aws_key_pair" "my_key" {
  key_name   = "my-key"
  public_key = file("~/.ssh/aws_terraform_rsa.pub")
}*/

#--------------------------------------------------------------
# EC2 Instance
#--------------------------------------------------------------

resource "aws_instance" "my_instance" {
  ami             = data.aws_ami.amazon_linux.id
  instance_type   = var.instance_type
  key_name        = aws_key_pair.ec2_keypair.id
  security_groups = [aws_security_group.web_sg.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  subnet_id                   = aws_default_subnet.default_az1.id
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${var.project}-instance"
  })
}
