# ---------- Provider ----------
provider "aws" {
  region = var.region
}

# ---------- AMI ----------
data "aws_ssm_parameter" "win2025_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2025-English-Full-Base"
}

# ---------- Instance ----------
resource "aws_instance" "win2025" {
  ami                         = data.aws_ssm_parameter.win2025_ami.value
  instance_type               = "m5a.xlarge"
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.win2025.id]
  key_name                    = aws_key_pair.win2025.key_name
  associate_public_ip_address = true

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price
      spot_instance_type             = "one-time"
      instance_interruption_behavior = "terminate"
    }
  }

  user_data = <<-EOF
    <powershell>
    $progressPreference = 'silentlyContinue'
    New-Item -ItemType Directory -Force -Path "C:\Temp"
    Invoke-WebRequest -Uri "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi" -OutFile "C:\Temp\amazon-cloudwatch-agent.msi"
    Start-Process msiexec.exe -ArgumentList '/i C:\Temp\amazon-cloudwatch-agent.msi /qn' -Wait

    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" `
      -a fetch-config -m ec2 `
      -s -c ssm:${aws_ssm_parameter.cw_config.name}
    </powershell>
  EOF

  tags = { Name = "WinServer2025-Spot-Test" }
}
