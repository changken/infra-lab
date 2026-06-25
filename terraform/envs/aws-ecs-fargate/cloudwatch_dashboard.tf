#==============================================================
# CloudWatch Dashboard
#
# 對比 EKS lab 的 Grafana + Prometheus：
#   EKS:  自建 Prometheus stack（Helm）→ Grafana Dashboard（自定義）
#   ECS:  Container Insights 原生輸出 → CloudWatch Dashboard（零設定）
#
# Container Insights 已在 ECS Cluster 開啟（containerInsights = "enabled"）
# 自動收集：CpuUtilized、MemoryUtilized、RunningTaskCount 等指標
#==============================================================

locals {
  alb_arn_suffix      = aws_lb.main.arn_suffix
  blue_tg_arn_suffix  = aws_lb_target_group.blue.arn_suffix
  green_tg_arn_suffix = aws_lb_target_group.green.arn_suffix
  cluster_name        = aws_ecs_cluster.main.name
  service_name        = aws_ecs_service.app.name
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name_prefix

  dashboard_body = jsonencode({
    widgets = [

      # ── Header ──────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# ECS Fargate — ${local.name_prefix}\n**Cluster**: `${local.cluster_name}` | **Service**: `${local.service_name}` | **Region**: `${var.region}`"
        }
      },

      # ── Row 1: ECS Task Metrics（Container Insights）────────

      # CPU 使用率（%）— metric math: CpuUtilized / CpuReserved * 100
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "CPU Utilization (%)"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "m1/m2*100", label = "CPU %", id = "e1", color = "#1f77b4" }],
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { id = "m1", visible = false }],
            ["ECS/ContainerInsights", "CpuReserved", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { id = "m2", visible = false }],
          ]
          annotations = {
            horizontal = [{ label = "Scale-out threshold", value = 70, color = "#ff7f0e" }]
          }
        }
      },

      # Memory 使用率（%）
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Memory Utilization (%)"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          yAxis  = { left = { min = 0, max = 100 } }
          metrics = [
            [{ expression = "m1/m2*100", label = "Memory %", id = "e1", color = "#2ca02c" }],
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { id = "m1", visible = false }],
            ["ECS/ContainerInsights", "MemoryReserved", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { id = "m2", visible = false }],
          ]
          annotations = {
            horizontal = [{ label = "Scale-out threshold", value = 80, color = "#ff7f0e" }]
          }
        }
      },

      # Running Task Count vs Desired（觀察 Auto Scaling）
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Task Count（Running vs Desired）"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Running", color = "#2ca02c" }],
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Desired", color = "#aec7e8" }],
          ]
        }
      },

      # ── Row 2: ALB Metrics ───────────────────────────────────

      # Request Count
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ALB Request Count"
          view   = "timeSeries"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_arn_suffix, { label = "Total Requests", color = "#1f77b4" }],
          ]
        }
      },

      # 5xx Errors
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "5xx Errors（Target + ELB）"
          view   = "timeSeries"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_arn_suffix, { label = "Target 5xx", color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb_arn_suffix, { label = "ELB 5xx", color = "#ff9896" }],
          ]
        }
      },

      # Target Response Time（P50 / P99）
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Target Response Time（秒）"
          view   = "timeSeries"
          region = var.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix, { stat = "p50", label = "P50", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix, { stat = "p99", label = "P99", color = "#ff7f0e" }],
          ]
        }
      },

      # ── Row 3: Blue/Green Target Group Health ────────────────

      # Blue TG
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Blue TG — Healthy Hosts"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.blue_tg_arn_suffix, "LoadBalancer", local.alb_arn_suffix, { label = "Healthy", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.blue_tg_arn_suffix, "LoadBalancer", local.alb_arn_suffix, { label = "Unhealthy", color = "#d62728" }],
          ]
        }
      },

      # Green TG
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Green TG — Healthy Hosts（部署期間新版本）"
          view   = "timeSeries"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.green_tg_arn_suffix, "LoadBalancer", local.alb_arn_suffix, { label = "Healthy", color = "#17becf" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.green_tg_arn_suffix, "LoadBalancer", local.alb_arn_suffix, { label = "Unhealthy", color = "#d62728" }],
          ]
        }
      },

    ]
  })
}
