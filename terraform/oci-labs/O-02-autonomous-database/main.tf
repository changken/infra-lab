#==============================================================
# Part A：網路層（已提供，不需要修改）
#
# 本 lab 的 ADB 只用 private endpoint（沒有公網 IP），連線一律走 Bastion。
# VCN / subnet / NSG 本身免費。
#==============================================================

resource "oci_core_vcn" "adb" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "adblab"
  freeform_tags  = local.common_tags
}

resource "oci_core_subnet" "adb" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.adb.id
  display_name               = "${var.name_prefix}-adb"
  cidr_block                 = local.adb_subnet_cidr
  dns_label                  = "adbsub"
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.common_tags
}

resource "oci_core_network_security_group" "adb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.adb.id
  display_name   = "${var.name_prefix}-nsg"
  freeform_tags  = local.common_tags
}

# ADB 用 1522（mTLS）與 1521（TLS），只開給 VCN 內部
resource "oci_core_network_security_group_security_rule" "adb_in" {
  for_each = toset(["1521", "1522"])

  network_security_group_id = oci_core_network_security_group.adb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

#==============================================================
# Part B：Autonomous Database（你要填的部分）
#==============================================================

#--------------------------------------------------------------
# TODO 1: Autonomous Database（付費 ECPU，private endpoint）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/database_autonomous_database
#
# 需要設定：
#   compartment_id          = var.compartment_id
#   db_name                 = var.db_name
#   display_name            = "${var.name_prefix}-db"
#   admin_password          = var.admin_password
#   db_workload             = var.db_workload
#   compute_model           = ???     # 💰 ECPU（與 O-01 的 ECPU 制一致）
#   compute_count           = var.compute_count
#   data_storage_size_in_gb = var.data_storage_gbs   # 注意欄位名稱，不是 in_tbs
#   is_free_tier            = ???     # ⚠️ 本 lab 要玩付費功能，這裡應為 false
#   license_model           = ???     # LICENSE_INCLUDED 或 BRING_YOUR_OWN_LICENSE
#   freeform_tags           = local.common_tags
#
# ⚠️ 注意：
#   - 建立約 5–15 分鐘（比 O-01 快很多）
#   - 付費 ADB 才有 auto scaling、Data Guard、clone；Always Free 沒有
#   - admin_password 是 sensitive，不要寫死；考慮 lifecycle ignore_changes
#   - 「停止」ADB 不等於不計費（儲存仍計費），lab 結束直接 destroy
#   - 以上欄位名稱請對照文件確認（provider 版本 ~> 7.0）

resource "oci_database_autonomous_database" "this" {
  # TODO 1
  compartment_id          = var.compartment_id
  db_name                 = var.db_name
  display_name            = "${var.name_prefix}-db"
  admin_password          = var.admin_password
  db_workload             = var.db_workload
  compute_model           = "ECPU" # 💰 ECPU（與 O
  compute_count           = var.compute_count
  data_storage_size_in_gb = var.data_storage_gbs # 注意欄位名稱，不是 in_tbs
  is_free_tier            = false                # ⚠️
  license_model           = "LICENSE_INCLUDED"   # LICENSE_INCLUDED 或 BRING_YOUR_OWN_LICENSE
  freeform_tags           = local.common_tags

  # TODO 2
  is_auto_scaling_enabled             = true # compute 最多自動擴到 3 倍 ECPU
  is_auto_scaling_for_storage_enabled = true # 💰 storage 自動擴

  # TODO 3
  is_local_data_guard_enabled = true

  # 允許 TLS（不需 wallet）連線；private endpoint 下仍只有 VCN 內／Bastion tunnel 能到達
  # ⚠️ 關閉 mTLS 後客戶端憑證不再是必要條件，安全性依賴 private endpoint + NSG
  is_mtls_connection_required = false

  # TODO 4: Private endpoint
  subnet_id = oci_core_subnet.adb.id
  nsg_ids   = [oci_core_network_security_group.adb.id]
}

#--------------------------------------------------------------
# TODO 2: Auto scaling（compute 與 storage 分開開關）
#--------------------------------------------------------------
# 在 TODO 1 的資源上加：
#   is_auto_scaling_enabled             = ???   # compute 最多自動擴到 3 倍 ECPU
#   is_auto_scaling_for_storage_enabled = ???   # 💰 storage 自動擴
#
# 想一想：auto scaling 開著，帳單上限是多少？lab 要不要開？
# 對比 AWS：Aurora Serverless v2 的 ACU min/max。

#--------------------------------------------------------------
# TODO 3: Local Data Guard（備援）
#--------------------------------------------------------------
# 在 TODO 1 的資源上加（欄位名稱請查文件）：
#   is_local_data_guard_enabled = ???
#
# ⚠️ 會多一份 standby 的計費；Singapore 只有 1 個 AD，只能做 local standby。
# 用 `oci db autonomous-database get` 看 standby 狀態，並試著做一次 switchover。
# 對比 AWS：Aurora replica／RDS Multi-AZ。

#--------------------------------------------------------------
# TODO 4: Private endpoint
#--------------------------------------------------------------
# 在 TODO 1 的資源上加：
#   subnet_id = ???    # 上面的 oci_core_subnet.adb
#   nsg_ids   = [???]  # 上面的 oci_core_network_security_group.adb
#
# ⚠️ private endpoint 沒有公網 IP，你的電腦連不進去，需要 VCN 內的跳板
#（見 TODO 7 的 Bastion）。不要為了驗證去改 envs/oci-vcn 或 envs/oci-linux。
# ⚠️ 不要同時設定 whitelisted_ips（ACL 是 public endpoint 的做法，本 lab 不用）。

#--------------------------------------------------------------
# TODO 5: 下載 Wallet
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/database_autonomous_database_wallet
#
#   autonomous_database_id = ???
#   password               = var.wallet_password
#   generate_type          = "SINGLE"
#
# 之後用 local_file 或 output 取得 content（base64 zip），解開後設定 TNS_ADMIN。
# ⚠️ wallet 含憑證，不要 commit；確認 .gitignore 有涵蓋 wallet 檔案。

resource "oci_database_autonomous_database_wallet" "this" {
  autonomous_database_id = oci_database_autonomous_database.this.id
  password               = var.wallet_password
  generate_type          = "SINGLE"
}

#--------------------------------------------------------------
# TODO 7: Bastion（連進 private endpoint 的跳板，免費）
#--------------------------------------------------------------
# ADB 在 private subnet、沒有公網 IP，你的電腦直接連不進去。
# 用 OCI Bastion service 開一條 port-forwarding tunnel：
#   你的電腦 ──SSH tunnel──> Bastion ──> ADB private IP:1522
#
# 文件:
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/bastion_bastion
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/bastion_session
#
# (a) oci_bastion_bastion 需要設定：
#   bastion_type                 = ???    # 這個 lab 用 STANDARD
#   compartment_id               = var.compartment_id
#   target_subnet_id             = ???    # 跟 ADB 同一個 subnet
#   name                         = ???    # 只允許英數，不能有連字號
#   client_cidr_block_allow_list = [???]  # 只放你的 IP
#   max_session_ttl_in_seconds   = ???    # session 最長存活時間，lab 不用太長
#
# (b) oci_bastion_session 需要設定：
#   bastion_id           = ???
#   key_details          { public_key_content = var.ssh_public_key }
#   target_resource_details {
#     session_type                       = ???   # port forwarding 的類型
#     target_resource_private_ip_address = ???   # ADB 的 private IP（看 ADB 資源有哪個屬性）
#     target_resource_port               = ???   # mTLS 用的 port
#   }
#   session_ttl_in_seconds = ???
#
# ⚠️ 注意：
#   - Bastion session 到期後 tunnel 就斷了，要重建 session
#   - ssh_public_key 用 var.ssh_public_key（要填進 tfvars），不要寫死
#   - 連線流程與驗證請看 README 的「連線到 private endpoint」
#   - Bastion 本身免費，但請在 destroy 時一起刪掉

resource "oci_bastion_bastion" "this" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_id
  target_subnet_id             = oci_core_subnet.adb.id
  name                         = "${var.name_prefix}bastion"
  client_cidr_block_allow_list = [var.allowed_cidr]
  max_session_ttl_in_seconds   = 10800 # 3 小時，Bastion 上限（超過 API 會拒絕）
}

resource "oci_bastion_session" "this" {
  bastion_id = oci_bastion_bastion.this.id

  key_details {
    public_key_content = var.ssh_public_key
  }

  target_resource_details {
    session_type                       = "PORT_FORWARDING"
    target_resource_private_ip_address = oci_database_autonomous_database.this.private_endpoint_ip
    target_resource_port               = 1522
  }

  session_ttl_in_seconds = 10800 # 不得超過 bastion 的 max_session_ttl_in_seconds
}