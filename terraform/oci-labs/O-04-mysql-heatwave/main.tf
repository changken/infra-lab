#==============================================================
# Part A：網路層（已提供，不需要修改）
#
# MySQL DB system 只放 private subnet（沒有公網 IP），連線一律走 Bastion。
# VCN / subnet / NSG 本身免費。
#==============================================================

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid # ⚠️ 用 tenancy，不是 compartment
}

resource "oci_core_vcn" "mysql" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "mysqllab"
  freeform_tags  = local.common_tags
}

resource "oci_core_subnet" "mysql" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.mysql.id
  display_name               = "${var.name_prefix}-subnet"
  cidr_block                 = local.mysql_subnet_cidr
  dns_label                  = "mysqlsub"
  prohibit_public_ip_on_vnic = true
  security_list_ids          = [oci_core_security_list.mysql.id]
  freeform_tags              = local.common_tags
}

# NSG 掛上 DB system 時建立會 FAILED（AuthorizationFailed），所以改用 subnet 的 security list 放行 3306／33060。
# 來源只開 VCN CIDR；Bastion 的 private endpoint 也在這個 subnet 內。
resource "oci_core_security_list" "mysql" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.mysql.id
  display_name   = "${var.name_prefix}-sl"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = toset(["3306", "33060"])
    content {
      protocol = "6"
      source   = var.vcn_cidr

      tcp_options {
        min = tonumber(ingress_security_rules.value)
        max = tonumber(ingress_security_rules.value)
      }
    }
  }
}

resource "oci_core_network_security_group" "mysql" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.mysql.id
  display_name   = "${var.name_prefix}-nsg"
  freeform_tags  = local.common_tags
}

# 3306 = MySQL classic protocol；33060 = X protocol。只開給 VCN 內部
resource "oci_core_network_security_group_security_rule" "mysql_in" {
  for_each = toset(["3306", "33060"])

  network_security_group_id = oci_core_network_security_group.mysql.id
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
# Part B：MySQL HeatWave（你要填的部分）
#==============================================================

#--------------------------------------------------------------
# TODO 1: MySQL DB system（單節點，先不開 HA、不開 HeatWave）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/mysql_mysql_db_system
#
# 需要設定：
#   compartment_id          = var.compartment_id
#   display_name            = "${var.name_prefix}-db"
#   availability_domain     = ???    # data.oci_identity_availability_domains.this 的第幾個？
#   shape_name              = var.mysql_shape
#   subnet_id               = ???    # Part A 的 subnet
#   nsg_ids                 = [???]  # Part A 的 NSG
#   admin_username          = var.admin_username
#   admin_password          = var.admin_password
#   data_storage_size_in_gb = var.data_storage_gbs
#   freeform_tags           = local.common_tags
#
# 建議一併設定（欄位名稱請查文件）：
#   - backup_policy：lab 資料不重要，想一想要不要關自動備份？保留天數多少？
#   - deletion_policy：destroy 時要不要自動做 final backup？（lab 結束要乾淨 destroy）
#   - lifecycle ignore_changes = [admin_password]
#
# ⚠️ 注意：
#   - 建立約 10–20 分鐘
#   - 用 `oci mysql shape list -c <compartment> --all` 確認 mysql_shape 名稱
#   - Singapore 只有 1 個 AD；HA 靠的是 fault domain，不是 AD
#   - 對比 AWS：aws_db_instance（engine = mysql）；OCI 的 MySQL 儲存與 compute 分開計費

resource "oci_mysql_mysql_db_system" "this" {
  # TODO 1
  compartment_id      = var.compartment_id
  display_name        = "${var.name_prefix}-db"
  availability_domain = data.oci_identity_availability_domains.this.availability_domains[0].name
  shape_name          = var.mysql_shape
  subnet_id           = oci_core_subnet.mysql.id
  # nsg_ids 暫時拿掉：排查 AuthorizationFailed 是否由 NSG 造成
  # nsg_ids                 = [oci_core_network_security_group.mysql.id]
  admin_username          = var.admin_username
  admin_password          = var.admin_password
  data_storage_size_in_gb = var.data_storage_gbs
  freeform_tags           = local.common_tags

  # TODO 2
  is_highly_available = var.enable_ha

  # lab 資料不重要：關自動備份；destroy 時不留 final backup
  backup_policy {
    is_enabled        = false
    retention_in_days = 1
  }

  deletion_policy {
    automatic_backup_retention = "DELETE"
    final_backup               = "SKIP_FINAL_BACKUP"
    is_delete_protected        = false
  }

  lifecycle {
    ignore_changes = [admin_password]
  }
}

#--------------------------------------------------------------
# TODO 2: High Availability
#--------------------------------------------------------------
# 在 TODO 1 的資源上加（欄位名稱請查文件）：
#   is_highly_available = var.enable_ha
#
# 驗證步驟（做完要記錄在 README）：
#   1. enable_ha = true 後 apply，觀察 DB system 變成幾個 instance
#   2. 觸發一次 failover／switchover，記錄應用端斷線秒數
#      （持續寫入並記錄時間戳，量測中斷時間）
#   3. 比較：HA 的費用是單節點的幾倍？lab 值不值得常駐？
#
# ⚠️ 從單節點改成 HA 是 in-place 還是 replace？先看 plan，不要直接 apply。
# 對比 AWS：RDS Multi-AZ；OCI 的 HA 用 Group Replication，且有 read/write 與 read-only endpoint。

#--------------------------------------------------------------
# TODO 3: HeatWave cluster
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/mysql_heat_wave_cluster
#
# 需要設定：
#   db_system_id = ???                      # TODO 1 的 DB system
#   shape_name   = var.heatwave_shape
#   cluster_size = var.heatwave_cluster_size
#
# 想一想：
#   - 這個資源要不要用 count 依 var.enable_heatwave 開關？為什麼要能單獨關掉？
#   - HeatWave 節點關掉後，資料表上的 SECONDARY_ENGINE 設定會怎樣？
#
# ⚠️ 注意：
#   - 💰 HeatWave 是整個 lab 最貴的資源，按小時計費；練完這一段先把 enable_heatwave 改回 false
#   - 並非所有 DB system shape 都能掛 HeatWave；apply 被拒時回頭檢查 shape
#   - 資料要 SECONDARY_LOAD 之後才會在 HeatWave 節點上被查詢（見 sql/02_heatwave_load.sql）
#   - 對比 AWS：沒有直接對應；最接近的是 Aurora + Redshift zero-ETL，但 HeatWave 是同一個 endpoint 自動分流

resource "oci_mysql_heat_wave_cluster" "this" {
  # TODO 3
  count = var.enable_heatwave ? 1 : 0

  db_system_id = oci_mysql_mysql_db_system.this.id
  shape_name   = var.heatwave_shape
  cluster_size = var.heatwave_cluster_size
}

#--------------------------------------------------------------
# TODO 4: Bastion（連進 private subnet 的跳板，免費）
#--------------------------------------------------------------
# DB system 在 private subnet、沒有公網 IP，你的電腦直接連不進去。
# 用 OCI Bastion service 開一條 port-forwarding tunnel：
#   你的電腦 ──SSH tunnel──> Bastion ──> DB system private IP:3306
#
# 文件:
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/bastion_bastion
#   https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/bastion_session
#
# (a) oci_bastion_bastion 需要設定：
#   bastion_type                 = ???    # 這個 lab 用 STANDARD
#   compartment_id               = var.compartment_id
#   target_subnet_id             = ???    # 跟 DB system 同一個 subnet
#   name                         = ???    # 只允許英數，不能有連字號
#   client_cidr_block_allow_list = [???]  # 只放你的 IP
#   max_session_ttl_in_seconds   = ???    # 上限 10800（3 小時）
#
# (b) oci_bastion_session 需要設定：
#   bastion_id           = ???
#   key_details          { public_key_content = var.ssh_public_key }
#   target_resource_details {
#     session_type                       = ???   # port forwarding 的類型
#     target_resource_private_ip_address = ???   # DB system 的 private IP（看資源有哪個屬性）
#     target_resource_port               = ???   # classic protocol 的 port
#   }
#   session_ttl_in_seconds = ???
#
# ⚠️ 注意：
#   - session 到期後 tunnel 就斷了，要重建 session
#   - HA 開啟後有 read/write 與 read-only 兩種 endpoint，想一想 tunnel 該指向哪一個
#   - 連線流程請看 README 的「連線」
#   - 設計和 O-02 相同，請自己寫，不要直接複製

resource "oci_bastion_bastion" "this" {
  # TODO 4 (a)
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_id
  target_subnet_id             = oci_core_subnet.mysql.id
  name                         = "${replace(var.name_prefix, "-", "")}bastion" # 只允許英數
  client_cidr_block_allow_list = [var.allowed_cidr]
  max_session_ttl_in_seconds   = 10800 # 3 小時，Bastion 上限
  freeform_tags                = local.common_tags
}

resource "oci_bastion_session" "this" {
  # TODO 4 (b)
  bastion_id = oci_bastion_bastion.this.id

  key_details {
    public_key_content = var.ssh_public_key
  }

  target_resource_details {
    session_type                       = "PORT_FORWARDING"
    target_resource_private_ip_address = oci_mysql_mysql_db_system.this.ip_address
    target_resource_port               = 3306
  }

  session_ttl_in_seconds = 10800 # 不得超過 bastion 的 max_session_ttl_in_seconds
}
