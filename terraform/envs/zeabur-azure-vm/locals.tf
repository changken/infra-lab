locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge({
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)

  # Zeabur dedicated server 需要的 inbound ports
  # priority 從 100 開始，每條 +10
  inbound_rules = {
    http      = { priority = 110, port = "80" }
    https     = { priority = 120, port = "443" }
    nats      = { priority = 130, port = "4222" }
    k8s_api   = { priority = 140, port = "6443" }
    node_port = { priority = 150, port = "30000-32767" }
  }
  inbound_rule_ssh = {
    ssh       = { priority = 100, port = "22" }
    /*forgejo   = { priority = 160, port = "3000" }
    forgejo_ssh   = { priority = 170, port = "2222" }
    valkey   = { priority = 180, port = "6379" }
    rabbitmq   = { priority = 190, port = "5672" }
    rabbitmq_management   = { priority = 200, port = "15672" }*/
  }
}
