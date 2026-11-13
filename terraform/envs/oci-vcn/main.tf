#--------------------------------------------------------------
# 由既有資源 import 而來（brownfield）。
# Oracle-Tags.* 是 OCI 自動寫入的 defined_tags，用 ignore_changes 避免永久 diff。
#--------------------------------------------------------------

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = var.vcn_name
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = var.vcn_dns_label

  # Console 啟用 Oracle 配發的 IPv6 前綴（subnet 的 /64 放在 tfvars）
  is_ipv6enabled = true

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = var.igw_name
  enabled        = true

  lifecycle {
    ignore_changes = [defined_tags, route_table_id]
  }
}

# VCN 建立時自動產生的 default route table，由 Terraform 接管（不會被刪除）
resource "oci_core_default_route_table" "default" {
  manage_default_resource_id = oci_core_vcn.main.default_route_table_id
  display_name               = "Default Route Table for ${var.vcn_name}"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = var.route_table_name

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# SSH（22）已收緊為 var.ssh_allowed_cidr。
# 注意：Security List 與 NSG 規則是「疊加」的，兩邊都要限制才有效。
resource "oci_core_default_security_list" "default" {
  manage_default_resource_id = oci_core_vcn.main.default_security_list_id
  display_name               = "Default Security List for ${var.vcn_name}"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    protocol    = "6" # TCP：SSH 僅允許指定來源（與 NSG 一致）
    source      = var.ssh_allowed_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # RDP（3389）：在 Console 手動新增，程式碼對齊現況。
  # 沿用 ssh_allowed_cidr 限制來源；不需要時請移除此區塊再 apply。
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.ssh_allowed_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 3389
      max = 3389
    }
  }

  # k3s（Console 手動新增，程式碼對齊現況）：僅允許 subnet 內節點互通。
  ingress_security_rules {
    description = "agent 連 server 的 API"
    protocol    = "6" # TCP
    source      = var.subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    description = "flannel VXLAN，節點間 Pod 網路"
    protocol    = "17" # UDP
    source      = var.subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    udp_options {
      min = 8472
      max = 8472
    }
  }

  ingress_security_rules {
    description = "kubelet（server 對 agent 做 logs、exec、metrics）"
    protocol    = "6" # TCP
    source      = var.subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 10250
      max = 10250
    }
  }

  ingress_security_rules {
    protocol    = "1" # ICMP: fragmentation needed
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol    = "1" # ICMP: destination unreachable（VCN 內）
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      type = 3
      code = -1
    }
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  display_name      = var.subnet_name
  cidr_block        = var.subnet_cidr
  ipv6cidr_block    = var.subnet_ipv6_cidr_block
  dns_label         = var.subnet_dns_label
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_default_security_list.default.id]
  dhcp_options_id   = oci_core_vcn.main.default_dhcp_options_id

  prohibit_public_ip_on_vnic = false

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = var.nsg_name

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group_security_rule" "ssh_from_home" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.ssh_allowed_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "允許ssh連線"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "rdp_from_home" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.ssh_allowed_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}

# k3s 節點互通（Console 手動新增，程式碼對齊現況）
resource "oci_core_network_security_group_security_rule" "k3s_api" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.subnet_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "agent 連 server 的 API"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "k3s_kubelet" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.subnet_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "kubelet（server 對 agent 做 logs、exec、metrics）"

  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

resource "oci_core_network_security_group_security_rule" "k3s_flannel_vxlan" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = var.subnet_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "flannel VXLAN，節點間 Pod 網路"

  udp_options {
    destination_port_range {
      min = 8472
      max = 8472
    }
  }
}

resource "oci_core_network_security_group_security_rule" "icmp_all" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "1"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false
}

resource "oci_core_network_security_group_security_rule" "icmpv6_all" {
  network_security_group_id = oci_core_network_security_group.main.id
  direction                 = "INGRESS"
  protocol                  = "58"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false
}
