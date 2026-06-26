# ---------- CloudWatch Agent Config (Linux) ----------
resource "aws_ssm_parameter" "cw_config" {
  name = "/cloudwatch-agent/linux/${var.name_prefix}/config"
  type = "String"
  value = jsonencode({
    metrics = {
      namespace = "Custom/AL2023"
      metrics_collected = {
        cpu = {
          measurement                 = ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                    = true
        }
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        disk = {
          measurement                 = ["disk_used_percent"]
          metrics_collection_interval = 60
          resources                   = ["/"]
        }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path        = "/var/log/messages"
              log_group_name   = "/linux/messages"
              log_stream_name  = "{instance_id}"
              timezone         = "UTC"
            },
            {
              file_path        = "/var/log/secure"
              log_group_name   = "/linux/secure"
              log_stream_name  = "{instance_id}"
              timezone         = "UTC"
            }
          ]
        }
      }
    }
  })
}
