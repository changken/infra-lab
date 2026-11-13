#==============================================================
# Part A：網路層（已提供，不需要修改）
#
# 架構：Flannel overlay CNI + 公開 API endpoint + 公開 worker subnet
# 為了省錢，不建 NAT Gateway / Private subnet；正式環境請改用 private nodes。
#==============================================================

resource "oci_core_vcn" "oke" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "okelab"
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "oke" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
  freeform_tags  = local.common_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-public-rt"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.oke.id
  }
}

# --- Security List：K8s API endpoint ---------------------------
resource "oci_core_security_list" "api" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-api-sl"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # 你的電腦 → kubectl
  ingress_security_rules {
    protocol = "6"
    source   = var.allowed_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # worker nodes → API server
  ingress_security_rules {
    protocol = "6"
    source   = local.node_subnet_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  # worker nodes → control plane（kubelet 註冊用）
  ingress_security_rules {
    protocol = "6"
    source   = local.node_subnet_cidr
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  # Path MTU discovery
  ingress_security_rules {
    protocol = "1"
    source   = local.node_subnet_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }
}

# --- Security List：Worker nodes -------------------------------
resource "oci_core_security_list" "node" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-node-sl"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # VCN 內全通：node↔node、pod↔pod（overlay）、API→kubelet(10250)、LB→NodePort
  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }
  ingress_security_rules {
    protocol = "6"
    source   = var.allowed_cidr
    tcp_options {
      min = 22
      max = 22
    }
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

# --- Security List：Load Balancer ------------------------------
resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-lb-sl"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = [80, 443]
    content {
      protocol = "6"
      source   = var.allowed_cidr
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
}

resource "oci_core_subnet" "api" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.oke.id
  display_name      = "${var.name_prefix}-api"
  cidr_block        = local.api_subnet_cidr
  dns_label         = "api"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.api.id]
  freeform_tags     = local.common_tags
}

resource "oci_core_subnet" "node" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.oke.id
  display_name      = "${var.name_prefix}-node"
  cidr_block        = local.node_subnet_cidr
  dns_label         = "node"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.node.id]
  freeform_tags     = local.common_tags
}

resource "oci_core_subnet" "lb" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.oke.id
  display_name      = "${var.name_prefix}-lb"
  cidr_block        = local.lb_subnet_cidr
  dns_label         = "lb"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.lb.id]
  freeform_tags     = local.common_tags
}

#==============================================================
# Part B：OKE（你要填的部分）
#==============================================================

#--------------------------------------------------------------
# TODO 1: 查詢 Availability Domain
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains
#
# 需要設定：
#   compartment_id = ???    # 查 AD 要用 tenancy（root compartment），不是 homelab
#
# 💡 Singapore 只有 1 個 AD，之後用 data.<name>.availability_domains[0].name 取用
#
# ⚠️ 注意：AD 名稱含 tenancy 前綴（例如 pimc:AP-SINGAPORE-1-AD-1），不要手寫

data "oci_identity_availability_domains" "ads" {
  # TODO
  compartment_id = var.tenancy_id
}

#--------------------------------------------------------------
# TODO 2: OKE Cluster（control plane）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/containerengine_cluster
#
# 需要設定：
#   compartment_id     = ???                  # homelab
#   name               = "${var.name_prefix}-cluster"
#   vcn_id             = ???                  # 上面建好的 VCN
#   kubernetes_version = ???                  # var.kubernetes_version
#   type               = ???                  # var.cluster_type（BASIC 免費 / ENHANCED 收費）
#
#   endpoint_config {                         # K8s API endpoint
#     subnet_id            = ???              # api subnet
#     is_public_ip_enabled = ???              # 要從家裡 kubectl，需要公開
#   }
#
#   cluster_pod_network_options {             # CNI 類型
#     cni_type = ???                          # 本 lab 用 overlay：FLANNEL_OVERLAY
#   }
#
#   options {
#     service_lb_subnet_ids = [???]           # Service type=LoadBalancer 建 LB 的 subnet
#     kubernetes_network_config {
#       pods_cidr     = "10.244.0.0/16"
#       services_cidr = "10.96.0.0/16"        # ⚠️ 不可與 VCN CIDR 重疊
#     }
#   }
#
#   freeform_tags = local.common_tags
#
# ⚠️ 注意：建立約需 5–10 分鐘，apply 看似卡住是正常的

resource "oci_containerengine_cluster" "this" {
  # TODO
  compartment_id     = var.compartment_id
  name               = "${var.name_prefix}-cluster"
  vcn_id             = oci_core_vcn.oke.id
  kubernetes_version = var.kubernetes_version
  type               = var.cluster_type

  endpoint_config {
    subnet_id            = oci_core_subnet.api.id
    is_public_ip_enabled = true
  }

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.lb.id]
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16" # ⚠️ 不可與 VCN CIDR 重疊
    }
  }

  freeform_tags = local.common_tags
}

#--------------------------------------------------------------
# TODO 3: 查詢節點可用的 image
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/containerengine_node_pool_option
#
# 步驟：
#   (a) data "oci_containerengine_node_pool_option"：
#         node_pool_option_id = ???      # 傳入 cluster 的 id
#         compartment_id      = ???
#   (b) 在 locals 區塊挑出 image_id。.sources 是 list，每個元素有
#       source_name 與 image_id。條件需同時符合：
#         - 架構要和 shape 對得上（見下方「image 命名」）
#         - source_name 含 "OKE-<版本號>"（版本號不含開頭的 v）
#       提示：for 運算式 + length(regexall(...)) 判斷；清單由新到舊，取 [0] 即最新
#
# image 命名（以 OKE-1.36.4 為例）：
#   ARM（A1 用）：Oracle-Linux-9.8-aarch64-2026.10.16-0-OKE-1.36.4-2067   → 名稱含 "aarch64"
#   GPU        ：Oracle-Linux-9.8-Gen2-GPU-2026.10.16-0-OKE-1.36.4-2067   → 名稱含 "GPU"
#   x86（E4 用）：Oracle-Linux-9.8-2026.10.16-0-OKE-1.36.4-2067            → 沒有任何架構字樣！
#
# ⚠️ 注意：
#   - x86 image 名稱不含 "amd64" / "x86"，用它們篩選會得到空 list → "Invalid index"。
#     x86 要用「排除法」：不含 aarch64、也不含 GPU。
#   - 放錯架構的 image 到 shape 會建立失敗；image 版本要和 kubernetes_version 對得上
#
# 💡 也可以先用 CLI 看有哪些 image：
#      oci ce node-pool-options get --node-pool-option-id all -c <compartment_id>

data "oci_containerengine_node_pool_option" "this" {
  # TODO
  node_pool_option_id = oci_containerengine_cluster.this.id
  compartment_id      = var.compartment_id
}

locals {
  # TODO: node_image_id = ...
  node_image_id = [
    for s in data.oci_containerengine_node_pool_option.this.sources : s.image_id
    if length(regexall("aarch64|GPU", s.source_name)) == 0 &&
    length(regexall("OKE-${trimprefix(var.kubernetes_version, "v")}", s.source_name)) > 0
  ][0]
}

#--------------------------------------------------------------
# TODO 4: Node Pool（worker nodes）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/containerengine_node_pool
#
# 需要設定：
#   compartment_id     = ???
#   cluster_id         = ???
#   name               = "${var.name_prefix}-pool"
#   kubernetes_version = ???                  # 要和 cluster 一致
#   node_shape         = ???                  # A1.Flex（Always Free，ARM，常缺貨）或 E4.Flex（x86，💰 收費）
#   ssh_public_key     = ???
#
#   node_shape_config {                       # Flex shape 必填
#     ocpus         = ???
#     memory_in_gbs = ???
#   }
#
#   node_source_details {
#     source_type             = "IMAGE"
#     image_id                = ???           # TODO 3 的結果
#     boot_volume_size_in_gbs = ???           # var.node_boot_volume_gbs
#   }
#
#   node_config_details {
#     size = ???                              # var.node_count
#     placement_configs {
#       availability_domain = ???             # TODO 1 的結果
#       subnet_id           = ???             # node subnet
#       # fault_domains     = ["FAULT-DOMAIN-1"]   # 缺貨時可指定／輪流嘗試
#     }
#   }
#
#   freeform_tags = local.common_tags
#
# ⚠️ 注意：
#   - 出現 "Out of host capacity" 是 A1 缺貨，不是你寫錯。換 fault_domains 或稍後重試。
#   - 用 A1 時 ocpus × size 不可超過 3（variables.tf 的 validation 擋住；改用 E4 時要把它註解掉）。
#   - 💰 E4.Flex 不在 Always Free 內，直接用 credit 扣款（見 README「成本」），練完當天 destroy。
#   - 節點 Ready 要 3–5 分鐘；cluster 之外還要等節點加入。

resource "oci_containerengine_node_pool" "this" {
  # TODO
  compartment_id     = var.compartment_id
  cluster_id         = oci_containerengine_cluster.this.id
  name               = "${var.name_prefix}-pool"
  kubernetes_version = var.kubernetes_version
  node_shape         = "VM.Standard.E4.Flex" #"VM.Standard.A1.Flex"
  ssh_public_key     = var.ssh_public_key
  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gbs
  }
  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.node_image_id
    boot_volume_size_in_gbs = var.node_boot_volume_gbs
  }
  node_config_details {
    size = var.node_count
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.node.id
      # fault_domains     = ["FAULT-DOMAIN-1"]   # 缺貨時可指定／輪流嘗試
    }
  }
  freeform_tags = local.common_tags
}
