#--------------------------------------------------------------
# Governance：compartment / IAM / budget（由既有資源 import 而來）
# IAM 與 Budget 都屬 tenancy 層級，只能在 home region 管理。
#--------------------------------------------------------------

#--- Compartment ---------------------------------------------------
resource "oci_identity_compartment" "homelab" {
  compartment_id = var.tenancy_id
  name           = "homelab"
  description    = "n100 homelab"

  lifecycle {
    prevent_destroy = true # compartment 內有資源時刪不掉，也避免誤刪
    ignore_changes  = [defined_tags]
  }
}

#--- Network Source：只允許從家裡 IP 呼叫 ---------------------------
resource "oci_identity_network_source" "homelab_source_ip" {
  compartment_id     = var.tenancy_id
  name               = "homelab_source_ip"
  description        = "n100 homelab 來源ip"
  public_source_list = [var.home_ip_cidr]
  services           = ["all"]

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

#--- Group（Identity Domain: Default）-------------------------------
# 注意：此 tenancy 使用 Identity Domains，group 要用 oci_identity_domains_group
resource "oci_identity_domains_group" "grab_bots" {
  idcs_endpoint = "https://idcs-28dcd57f3fdf42e3b572bc14275a764f.identity.oraclecloud.com:443"
  display_name  = "grab-bots"
  schemas = [
    "urn:ietf:params:scim:schemas:core:2.0:Group",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:group:Group",
  ]

  urnietfparamsscimschemasoracleidcsextensiongroup_group {
    description = "抓取vm的群組"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      urnietfparamsscimschemasoracleidcsextension_oci_tags,
      urnietfparamsscimschemasoracleidcsextensiondynamic_group,
    ]
  }
}

#--- Policy：授權 grab-bots 管理 compute，僅限 homelab_source_ip ----
# ⚠️ 修改 statements 前先確認 plan，寫錯可能讓 A1 搶機腳本失去權限
resource "oci_identity_policy" "grab_bot_policy" {
  compartment_id = var.tenancy_id
  name           = "grab-bot-policy"
  description    = "n100用"

  statements = [
    "Allow group 'Default'/'grab-bots' to manage instance-family in tenancy where request.networkSource.name='${oci_identity_network_source.homelab_source_ip.name}'",
    "Allow group 'Default'/'grab-bots' to read app-catalog-listing in tenancy where request.networkSource.name='${oci_identity_network_source.homelab_source_ip.name}'",
    "Allow group 'Default'/'grab-bots' to use volume-family in tenancy where request.networkSource.name='${oci_identity_network_source.homelab_source_ip.name}'",
    "Allow group 'Default'/'grab-bots' to use virtual-network-family in tenancy where request.networkSource.name='${oci_identity_network_source.homelab_source_ip.name}'",
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags]
  }
}

#--- Budget ---------------------------------------------------------
resource "oci_budget_budget" "my_budget" {
  compartment_id = var.tenancy_id
  display_name   = "my_budget"
  description    = "我的預算"
  amount         = 1 # SGD
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.tenancy_id]

  budget_processing_period_start_offset = 1
  processing_period_type                = "MONTH"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_budget_alert_rule" "alert_1" {
  budget_id      = oci_budget_budget.my_budget.id
  display_name   = "alertrule20261106060934"
  type           = "ACTUAL"
  threshold      = 1
  threshold_type = "ABSOLUTE"
  recipients     = var.budget_alert_email
  message        = "預算超過1新加坡幣了"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
