# ---------- CloudWatch Agent Config ----------
resource "aws_ssm_parameter" "cw_config" {
  name = "/cloudwatch-agent/windows/config"
  type = "String"
  value = jsonencode({
    metrics = {
      namespace = "Custom/WinServer2025"
      metrics_collected = {
        Memory = {
          measurement                 = ["% Committed Bytes In Use"]
          metrics_collection_interval = 60
        }
        LogicalDisk = {
          measurement                 = ["% Free Space"]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
        Processor = {
          measurement                 = ["% Processor Time"]
          metrics_collection_interval = 60
          resources                   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name     = "System"
              event_levels   = ["ERROR", "WARNING"]
              log_group_name = "/windows/system"
            },
            {
              event_name     = "Application"
              event_levels   = ["ERROR", "WARNING"]
              log_group_name = "/windows/application"
            }
          ]
        }
      }
    }
  })
}
