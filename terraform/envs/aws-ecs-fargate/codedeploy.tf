#==============================================================
# AWS CodeDeploy — ECS Blue/Green Deployment
#
# 對比 Argo Rollouts（EKS）：
#   Argo Rollouts: K8s CRD + controller，需要 Helm 安裝
#   CodeDeploy:    AWS 原生，零安裝，直接整合 ALB + ECS
#
# 部署流程：
#   1. 觸發 CodeDeploy deployment（提供新 task definition ARN）
#   2. CodeDeploy 啟動新 tasks → 註冊到 Green TG
#   3. Green TG health check 通過
#   4. Production Listener（:80）切換指向 Green TG
#   5. 等待 termination_wait_time_in_minutes
#   6. 刪除舊 Blue tasks
#==============================================================

# ── IAM Role for CodeDeploy ─────────────────────────────────

resource "aws_iam_role" "codedeploy" {
  name = "${local.name_prefix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# ── CodeDeploy Application ───────────────────────────────────

resource "aws_codedeploy_app" "app" {
  name             = "${local.name_prefix}-app"
  compute_platform = "ECS"

  tags = local.common_tags
}

# ── CodeDeploy Deployment Group ──────────────────────────────

resource "aws_codedeploy_deployment_group" "app" {
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = "${local.name_prefix}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.codedeploy_config

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    # 健康檢查通過後自動切換流量（不需人工確認）
    # 改成 STOP_DEPLOYMENT 可讓你先測試 :8080 再手動 approve
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.blue_termination_wait_minutes
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_pair_info {
      # Production Listener：部署完成後流量切到這裡
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      # Test Listener：可在切換前用 :8080 預覽新版本
      test_traffic_route {
        listener_arns = [aws_lb_listener.test.arn]
      }

      target_group { name = aws_lb_target_group.blue.name }
      target_group { name = aws_lb_target_group.green.name }
    }
  }

  tags = local.common_tags
}
