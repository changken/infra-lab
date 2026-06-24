#==============================================================
# ECS Service Auto Scaling
#
# EKS vs ECS 彈性伸縮對比：
#   EKS HPA:      kubectl autoscale → metrics-server → 調整 Pod replicas
#   EKS Karpenter: 節點自動擴縮（補 node 給 Pod）
#
#   ECS Fargate:  Application Auto Scaling → 直接調整 service desired_count
#                 無需管理 Node（Fargate 自動分配算力）
#                 只有一層 scaling，比 EKS 簡單
#==============================================================

# ── Scalable Target（告訴 Application Auto Scaling 要控制誰）

resource "aws_appautoscaling_target" "ecs_service" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.app]
}

# ── Scale on CPU（目標追蹤策略）────────────────────────────

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name_prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 300 # 縮容冷卻 5 分鐘，避免 flapping
    scale_out_cooldown = 60  # 擴容快速反應
  }
}

# ── Scale on Memory ─────────────────────────────────────────

resource "aws_appautoscaling_policy" "memory" {
  name               = "${local.name_prefix}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.autoscaling_memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
