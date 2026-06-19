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
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  subnet_id                   = local.resolved_subnet_id
  vpc_security_group_ids      = [aws_security_group.win2025.id]
  key_name                    = aws_key_pair.win2025.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  # market_type = "spot"：使用 Spot 定價，成本較低
  #   - persistent：價格回落後 AWS 自動重啟 instance
  #   - stop：價格超過 max_price 時進入 stopped 狀態，EBS 資料保留
  #   - max_price：null 表示接受 on-demand 價格上限
  #   ⚠️ 手動 terminate 後需至 AWS Console 取消 Spot Request
  # market_type = "on-demand"：固定價格，不會被中斷
  dynamic "instance_market_options" {
    for_each = var.market_type == "spot" ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.spot_max_price
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
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

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-spot" })
}
