#==============================================================
# Part A：網路層（已提供，不需要修改）
#
# PostgreSQL DB system 只放 private subnet（沒有公網 IP），連線一律走 Bastion。
# VCN / subnet / NSG 本身免費。
#==============================================================

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid # ⚠️ 用 tenancy，不是 compartment
}

resource "oci_core_vcn" "psql" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "psqllab"
  freeform_tags  = local.common_tags
}

resource "oci_core_subnet" "psql" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.psql.id
  display_name               = "${var.name_prefix}-subnet"
  cidr_block                 = local.psql_subnet_cidr
  dns_label                  = "psqlsub"
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.common_tags
}

resource "oci_core_network_security_group" "psql" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.psql.id
  display_name   = "${var.name_prefix}-nsg"
  freeform_tags  = local.common_tags
}

# 5432 = PostgreSQL。只開給 VCN 內部（Bastion 從 subnet 內轉進來）
resource "oci_core_network_security_group_security_rule" "psql_in" {
  network_security_group_id = oci_core_network_security_group.psql.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 5432
      max = 5432
    }
  }
}

#==============================================================
# Part B：OCI Database with PostgreSQL（你要填的部分）
#==============================================================

#--------------------------------------------------------------
# TODO 1: PostgreSQL DB system（先單節點）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/psql_db_system
#
# 需要設定：
#   compartment_id = var.compartment_id
#   display_name   = "${var.name_prefix}-db"
#   db_version     = var.db_version
#   shape          = var.psql_shape   # PostgreSQL.VM.Standard.E5.Flex（不含 .2.32GB）
#   freeform_tags  = local.common_tags
#
#   network_details { subnet_id / nsg_ids }
#   storage_details { is_regionally_durable / system_type / availability_domain }
#   credentials { username / password_details { password_type / password } }
#   instance_count / instance_ocpu_count / instance_memory_size_in_gbs
#   management_policy：lab 資料不重要，關自動備份
#
# ⚠️ 注意：
#   - 建立約 5–20 分鐘
#   - Singapore 只提供 E5／E6／Standard3 shape（沒有 E4）：`oci psql shape-summary list-shapes --all`
#   - 對比 AWS：aws_db_instance（engine = postgres）／Aurora PostgreSQL

resource "oci_psql_db_system" "this" {
  # TODO 1
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-db"
  db_version     = var.db_version
  shape          = var.psql_shape
  freeform_tags  = local.common_tags

  network_details {
    subnet_id = oci_core_subnet.psql.id
    nsg_ids   = [oci_core_network_security_group.psql.id]

    # TODO 3
    is_reader_endpoint_enabled = var.enable_reader_endpoint
  }

  storage_details {
    system_type = "OCI_OPTIMIZED_STORAGE"

    # TODO 2：Singapore 只有 1 個 AD，regional 儲存（is_regionally_durable = true）只支援 3 AD region
    # （apply 會被 400-InvalidParameter 拒絕），所以一律 false 並指定 AD
    is_regionally_durable = false
    availability_domain   = data.oci_identity_availability_domains.this.availability_domains[0].name
  }

  credentials {
    username = var.admin_username
    password_details {
      password_type = "PLAIN_TEXT" # lab 用；正式環境請改 VAULT_SECRET
      password      = var.admin_password
    }
  }

  # TODO 2
  instance_count              = var.instance_count
  instance_ocpu_count         = var.instance_ocpu_count
  instance_memory_size_in_gbs = var.instance_memory_gbs

  # lab 資料不重要：關自動備份
  management_policy {
    backup_policy {
      kind = "NONE"
    }
  }

  lifecycle {
    ignore_changes = [credentials]
  }
}

#--------------------------------------------------------------
# TODO 2: High Availability（多 instance）
#--------------------------------------------------------------
# 調整 instance_count（1 → 3）。
# ⚠️ Singapore 只有 1 個 AD：is_regionally_durable 只能是 false，instance 之間靠 fault domain 分散。
# ⚠️ 先看 plan，單節點改多 instance 是 in-place 還是 replace？（replace 會先 destroy，資料與 Bastion
#    session 都會消失）
#
# 驗證步驟（做完要記錄在 README）：
#   1. apply 後觀察 DB system 有幾個 instance（`oci psql db-system get`）
#   2. 持續寫入（見 sql/01_failover_probe.sql），再用 `oci psql db-system failover` 觸發一次，記錄應用端中斷秒數
#   3. 比較：HA 的費用是單節點的幾倍？lab 值不值得常駐？
#
# 對比 AWS：RDS Multi-AZ 的 standby 不能讀；Aurora 是 1 writer + N reader。

#--------------------------------------------------------------
# TODO 3: Reader endpoint（讀寫分離）
#--------------------------------------------------------------
# network_details 的 is_reader_endpoint_enabled = var.enable_reader_endpoint
#
# 驗證步驟：
#   1. 取得 reader endpoint 的 private IP（Console）
#   2. 從 writer 連線 INSERT，從 reader 連線 SELECT，記錄 replication lag
#   3. 對 reader 嘗試寫入，記錄錯誤訊息
#
# ⚠️ instance_count = 1 時開 reader endpoint 會怎樣？先看 plan。

#--------------------------------------------------------------
# TODO 4: Bastion（連進 private subnet 的跳板，免費）
#--------------------------------------------------------------
# 你的電腦 ──SSH tunnel──> Bastion ──> DB system private IP:5432
#
# ⚠️ 注意：
#   - session 到期後 tunnel 就斷了，要重建 session
#   - DB system 被 replace 後 session 也會跟著重建（target IP 變了）
#   - tunnel 的私鑰要對應 var.ssh_public_key

resource "oci_bastion_bastion" "this" {
  # TODO 4 (a)
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_id
  target_subnet_id             = oci_core_subnet.psql.id
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
    target_resource_private_ip_address = oci_psql_db_system.this.network_details[0].primary_db_endpoint_private_ip
    target_resource_port               = 5432
  }

  session_ttl_in_seconds = 10800 # 不得超過 bastion 的 max_session_ttl_in_seconds
}
