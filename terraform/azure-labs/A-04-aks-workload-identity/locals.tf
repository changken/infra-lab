data "azurerm_client_config" "current" {}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  name_prefix = "${var.project}-${var.environment}"

  # Key Vault 名稱：3-24 字元，英數與連字號，全域唯一
  key_vault_name = "${local.name_prefix}-kv"

  # Federated Credential subject：固定格式，對比 IRSA 的 Trust Policy condition
  # system:serviceaccount:<namespace>:<service-account-name>
  federated_subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}
