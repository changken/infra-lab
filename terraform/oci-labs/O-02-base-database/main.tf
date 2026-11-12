#==============================================================
# Part A：網路層（已提供，不需要修改）
#
# 為了省錢，不建 NAT Gateway / Private subnet；DB 放 public subnet，
# 只靠 Security List 限制 allowed_cidr。正式環境請改 private subnet + bastion。
#==============================================================

resource "oci_core_vcn" "db" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "dblab"
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.db.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
  freeform_tags  = local.common_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.db.id
  display_name   = "${var.name_prefix}-public-rt"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.db.id
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

  # SSH 與 SQL*Net，只開給你的 IP
  dynamic "ingress_security_rules" {
    for_each = [22, 1521]
    content {
      protocol = "6"
      source   = var.allowed_cidr
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
  # VCN 內全通（之後加 app server 連 DB 用）
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
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.db.id]
  prohibit_public_ip_on_vnic = false
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
