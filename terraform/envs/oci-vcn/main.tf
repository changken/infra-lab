#--------------------------------------------------------------
# 由既有資源 import 而來（brownfield）。
# Oracle-Tags.* 是 OCI 自動寫入的 defined_tags，用 ignore_changes 避免永久 diff。
#--------------------------------------------------------------

resource "oci_core_vcn" "ken_vcn" {
  compartment_id = var.compartment_id
  display_name   = "ken-vcn"
  cidr_blocks    = ["10.87.0.0/16"]
  dns_label      = "kenvcn"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_internet_gateway" "ken_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ken_vcn.id
  display_name   = "ken-igw"
  enabled        = true

  lifecycle {
    ignore_changes = [defined_tags, route_table_id]
  }
}

# VCN 建立時自動產生的 default route table，由 Terraform 接管（不會被刪除）
resource "oci_core_default_route_table" "default" {
  manage_default_resource_id = oci_core_vcn.ken_vcn.default_route_table_id
  display_name               = "Default Route Table for ken-vcn"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_route_table" "ken_routetable" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ken_vcn.id
  display_name   = "ken-routetable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.ken_igw.id
  }

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

# ⚠️ 目前對 0.0.0.0/0 開放 SSH（22），與 NSG 的 IP 限制疊加後等於沒限制
resource "oci_core_default_security_list" "default" {
  manage_default_resource_id = oci_core_vcn.ken_vcn.default_security_list_id
  display_name               = "Default Security List for ken-vcn"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 22
      max = 22
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
    source      = "10.87.0.0/16"
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

resource "oci_core_subnet" "public_subnet_one" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.ken_vcn.id
  display_name      = "public-subnet-one"
  cidr_block        = "10.87.0.0/24"
  dns_label         = "publicsubnetone"
  route_table_id    = oci_core_route_table.ken_routetable.id
  security_list_ids = [oci_core_default_security_list.default.id]
  dhcp_options_id   = oci_core_vcn.ken_vcn.default_dhcp_options_id

  prohibit_public_ip_on_vnic = false

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group" "my_sg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.ken_vcn.id
  display_name   = "my-sg"

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_network_security_group_security_rule" "ssh_from_home" {
  network_security_group_id = oci_core_network_security_group.my_sg.id
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

resource "oci_core_network_security_group_security_rule" "icmp_all" {
  network_security_group_id = oci_core_network_security_group.my_sg.id
  direction                 = "INGRESS"
  protocol                  = "1"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false
}

resource "oci_core_network_security_group_security_rule" "icmpv6_all" {
  network_security_group_id = oci_core_network_security_group.my_sg.id
  direction                 = "INGRESS"
  protocol                  = "58"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false
}
