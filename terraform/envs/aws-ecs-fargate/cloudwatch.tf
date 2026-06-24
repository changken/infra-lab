#==============================================================
# CloudWatch Logs（容器日誌）
#
# EKS 通常用 Fluent Bit DaemonSet 把日誌送到 CloudWatch
# ECS Fargate 用 awslogs driver，ECS agent 原生支援，零設定
#==============================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}/app"
  retention_in_days = 7 # lab 環境短保留期，降低費用

  tags = local.common_tags
}
