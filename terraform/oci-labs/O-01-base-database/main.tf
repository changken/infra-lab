#==============================================================
# Part A：網路層（已提供，不需要修改）
#
# DB 放 private subnet（沒有公網 IP、沒有 Internet Gateway、沒有 NAT Gateway）。
# 對外只有 Service Gateway（免費）連 Oracle 服務；
# 你從電腦連進來一律走 OCI Bastion（見 Part C）。
#==============================================================

resource "oci_core_vcn" "db" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "dblab"
  freeform_tags  = local.common_tags
}

# Oracle Services Network（Service Gateway 的目的地）
data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.db.id
  display_name   = "${var.name_prefix}-sgw"
  freeform_tags  = local.common_tags

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.db.id
  display_name   = "${var.name_prefix}-private-rt"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.db.id
  }
}

resource "oci_core_security_list" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.db.id
  display_name   = "${var.name_prefix}-db-sl"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # 不對外開 22 / 1521；Bastion 從 VCN 內連到 DB node，靠下面「VCN 內全通」即可
  # VCN 內全通（Bastion、之後的 app server 連 DB 用）
  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "db" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.db.id
  display_name               = "${var.name_prefix}-db"
  cidr_block                 = local.db_subnet_cidr
  dns_label                  = "dbsub"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.db.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.common_tags
}

#==============================================================
# Part B：Base Database（你要填的部分）
#==============================================================

#--------------------------------------------------------------
# TODO 1: 查 Availability Domain
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains
#
# 需要設定：
#   compartment_id = ???   # ⚠️ 要用 tenancy OCID，不是 compartment
#
# 之後用 data.oci_identity_availability_domains.ads.availability_domains[0].name
# （Singapore 只有 1 個 AD）

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_id
}

#--------------------------------------------------------------
# TODO 2: DB System
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/database_db_system
#
# 需要設定（外層）：
#   compartment_id          = var.compartment_id
#   availability_domain     = ???      # TODO 1 的結果
#   subnet_id               = ???      # 本檔的 oci_core_subnet.db
#   shape                   = ???      # 此帳號只有 "VM.BaseDB.x86"（ECPU 制）
#   compute_count           = ???      # ECPU 數；ECPU shape 必須明確指定
#   database_edition        = var.database_edition
#   license_model           = ???      # LICENSE_INCLUDED（含授權費）或 BRING_YOUR_OWN_LICENSE
#   hostname                = ???      # ≤ 12 字元，小寫英數
#   ssh_public_keys         = [var.ssh_public_key]
#   data_storage_size_in_gb = var.data_storage_gbs
#   node_count              = 1        # 單節點；RAC 需 Enterprise + 多節點
#   display_name / freeform_tags
#
# 需要設定（db_home → database 區塊）：
#   db_version     = var.db_version
#   admin_password = var.db_admin_password
#   db_name        = var.db_name
#   pdb_name       = var.pdb_name
#   character_set / ncharacter_set   # 預設 AL32UTF8 / AL16UTF16
#   db_backup_config { auto_backup_enabled = ??? }  # 💰 備份會寫 Object Storage，lab 建議關閉
#
# ⚠️ 注意：
#   - 建立約 30–60 分鐘；destroy 約 10–20 分鐘（所以提早開始、提早刪）
#   - admin_password 是 sensitive，不要寫死在 .tf
#   - 若要避免 apply 後 plan 一直顯示差異，可考慮 lifecycle ignore_changes
#     （例如 db_home[0].database[0].admin_password）

resource "oci_database_db_system" "this" {
  compartment_id          = var.compartment_id
  availability_domain     = data.oci_identity_availability_domains.ads.availability_domains[0].name
  subnet_id               = oci_core_subnet.db.id
  shape                   = "VM.BaseDB.x86"
  compute_model           = "ECPU"
  compute_count           = var.compute_count
  database_edition        = var.database_edition
  license_model           = "LICENSE_INCLUDED"
  hostname                = var.name_prefix
  ssh_public_keys         = [var.ssh_public_key]
  data_storage_size_in_gb = var.data_storage_gbs
  node_count              = 1
  display_name            = "${var.name_prefix}-db"
  freeform_tags           = local.common_tags

  db_system_options {
    storage_management = "LVM"
  }

  db_home {
    display_name = "${var.name_prefix}-dbhome"
    db_version   = var.db_version

    database {
      admin_password = var.db_admin_password
      db_name        = var.db_name
      pdb_name       = var.pdb_name
      character_set  = "AL32UTF8"
      ncharacter_set = "AL16UTF16"

      db_backup_config {
        auto_backup_enabled = false
      }
    }
  }

  # admin_password 等巢狀欄位 provider 不一定回傳，避免 apply 後 plan 一直有差異
  lifecycle {
    ignore_changes = [db_home[0].database[0].admin_password]
  }
}

#==============================================================
# Part C：Bastion（你要填的部分）
#==============================================================

#--------------------------------------------------------------
# TODO 4: Bastion + 兩個 port-forwarding session
#--------------------------------------------------------------
# DB node 在 private subnet、沒有公網 IP，你的電腦直接連不進去。
# 用 OCI Bastion service（免費）開兩條 SSH tunnel：
#   你的電腦 localhost:<SSH port> ──> Bastion ──> DB node private IP:22
#   你的電腦 localhost:1521       ──> Bastion ──> DB node private IP:1521
#
# 文件:
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/bastion_bastion
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/bastion_session
#   可參考 ../O-02-autonomous-database/main.tf 的 TODO 7（同樣的 Bastion 做法）
#
# (a) oci_bastion_bastion 需要設定：
#   bastion_type                 = ???    # 這個 lab 用 STANDARD
#   compartment_id               = var.compartment_id
#   target_subnet_id             = ???    # 跟 DB 同一個 subnet
#   name                         = ???    # ⚠️ 只允許英數，不能有連字號（var.name_prefix 含連字號，要處理）
#   client_cidr_block_allow_list = [???]  # 只放你的 IP（來源 IP，不是 DB 的 IP）
#   max_session_ttl_in_seconds   = ???    # session 最長存活時間，lab 不用太長
#
# (b) oci_bastion_session 需要設定（要兩個：SSH 一個、SQL*Net 一個，可用 for_each）：
#   bastion_id           = ???
#   key_details          { public_key_content = var.ssh_public_key }
#   target_resource_details {
#     session_type                       = ???   # port forwarding 的類型（不要用 MANAGED_SSH，DB node 不一定有 Bastion plugin）
#     target_resource_private_ip_address = ???   # DB node 的 private IP（locals.tf 的 local.private_ip）
#     target_resource_port               = ???   # 22 或 1521
#   }
#   session_ttl_in_seconds = ???
#
# ⚠️ 注意：
#   - session 到期後 tunnel 就斷了，要重建 session
#   - 你的 IP 變了要更新 allowed_cidr 並 apply（Bastion allow list 原地更新）
#   - Bastion 本身免費，destroy 時會一起刪掉

resource "oci_bastion_bastion" "this" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_id
  target_subnet_id             = oci_core_subnet.db.id
  name                         = replace(var.name_prefix, "-", "")
  client_cidr_block_allow_list = [var.allowed_cidr]
  max_session_ttl_in_seconds   = 3600
  freeform_tags                = local.common_tags
}

resource "oci_bastion_session" "this" {
  for_each = {
    ssh    = { port = 22 }
    sqlnet = { port = 1521 }
  }

  bastion_id = oci_bastion_bastion.this.id

  key_details {
    public_key_content = var.ssh_public_key
  }

  target_resource_details {
    session_type                       = "PORT_FORWARDING"
    target_resource_private_ip_address = local.private_ip
    target_resource_port               = each.value.port
  }

  session_ttl_in_seconds = 3600
}