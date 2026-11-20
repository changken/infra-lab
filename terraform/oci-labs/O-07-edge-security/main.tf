#==============================================================
# Part A：網路層 + backend（已提供，不需要修改）
#
#   Internet ─► [LB public subnet] ─► [app private subnet: backend ×N]
#                                          │ 出站：預設走 NAT；TODO 3 改走 Network Firewall
#   你的電腦 ──Bastion（MANAGED_SSH）──────┘
#
# VCN / subnet / gateway / NSG 本身免費；backend instance 是付費 shape。
#==============================================================

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid # ⚠️ 用 tenancy，不是 compartment
}

data "oci_core_images" "ol9" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.backend_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "edgelab"
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-igw"
  freeform_tags  = local.common_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nat"
  freeform_tags  = local.common_tags
}

# --- Route tables ---

resource "oci_core_route_table" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-lb"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

# backend 的出站路由：預設走 NAT；enable_network_firewall = true 時改指向 firewall 的 private IP（TODO 3）
resource "oci_core_route_table" "app" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-app"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = var.enable_network_firewall ? data.oci_core_private_ips.fw[0].private_ips[0].id : oci_core_nat_gateway.this.id
  }
}

# firewall subnet 的出站：走 NAT（firewall 自己要能連外）
resource "oci_core_route_table" "fw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-fw"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }
}

# --- Subnets ---

resource "oci_core_subnet" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-subnet-lb"
  cidr_block     = local.lb_subnet_cidr
  dns_label      = "lbsub"
  route_table_id = oci_core_route_table.lb.id
  freeform_tags  = local.common_tags
}

resource "oci_core_subnet" "fw" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.name_prefix}-subnet-fw"
  cidr_block                 = local.fw_subnet_cidr
  dns_label                  = "fwsub"
  route_table_id             = oci_core_route_table.fw.id
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.common_tags
}

resource "oci_core_subnet" "app" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.name_prefix}-subnet-app"
  cidr_block                 = local.app_subnet_cidr
  dns_label                  = "appsub"
  route_table_id             = oci_core_route_table.app.id
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.common_tags
}

# --- NSG（與 Security List 疊加；VCN 預設 Security List 仍存在，兩邊都要想）---

resource "oci_core_network_security_group" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg-lb"
  freeform_tags  = local.common_tags
}

resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg-app"
  freeform_tags  = local.common_tags
}

# LB 入口：只開給你的 IP（80、443）
resource "oci_core_network_security_group_security_rule" "lb_in" {
  for_each = toset(["80", "443"])

  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.allowed_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

# LB → backend：80，來源限定為 LB 的 NSG
resource "oci_core_network_security_group_security_rule" "app_in_http" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

# Bastion → backend：22，來源為 VCN 內（Bastion 從 target subnet 內轉進來）
resource "oci_core_network_security_group_security_rule" "app_in_ssh" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_out" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = oci_core_network_security_group.app.id
  destination_type          = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "app_out" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# --- Backend instances（nginx，首頁印出 hostname，用來看 LB 的 round-robin）---

resource "oci_core_instance" "backend" {
  count = var.backend_count

  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.this.availability_domains[0].name
  display_name        = "${var.name_prefix}-backend-${count.index + 1}"
  shape               = var.backend_shape
  freeform_tags       = local.common_tags

  shape_config {
    ocpus         = var.backend_ocpus
    memory_in_gbs = var.backend_memory_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ol9.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.app.id
    nsg_ids          = [oci_core_network_security_group.app.id]
    assign_public_ip = false
  }

  # TODO 4 需要 Bastion plugin（MANAGED_SSH 靠它）
  agent_config {
    plugins_config {
      name          = "Bastion"
      desired_state = "ENABLED"
    }
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(<<-EOT
      #!/bin/bash
      dnf install -y nginx
      echo "backend: $(hostname)" > /usr/share/nginx/html/index.html
      firewall-cmd --permanent --add-service=http && firewall-cmd --reload
      systemctl enable --now nginx
    EOT
    )
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id, defined_tags]
  }
}

#==============================================================
# Part B：邊界安全
#==============================================================

#--------------------------------------------------------------
# TODO 1: Load Balancer（Flexible，public subnet）
#--------------------------------------------------------------
resource "oci_load_balancer_load_balancer" "this" {
  compartment_id             = var.compartment_id
  display_name               = "${var.name_prefix}-lb"
  shape                      = "flexible"
  subnet_ids                 = [oci_core_subnet.lb.id]
  network_security_group_ids = [oci_core_network_security_group.lb.id]
  is_private                 = false
  freeform_tags              = local.common_tags

  shape_details {
    minimum_bandwidth_in_mbps = var.lb_min_bandwidth_mbps
    maximum_bandwidth_in_mbps = var.lb_max_bandwidth_mbps
  }
}

resource "oci_load_balancer_backend_set" "this" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "backends"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTP"
    port        = 80
    url_path    = "/"
    return_code = 200
  }
}

resource "oci_load_balancer_backend" "this" {
  count = var.backend_count

  load_balancer_id = oci_load_balancer_load_balancer.this.id
  backendset_name  = oci_load_balancer_backend_set.this.name
  ip_address       = oci_core_instance.backend[count.index].private_ip
  port             = 80
}

resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.this.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.this.name
  protocol                 = "HTTP"
  port                     = 80
}

#--------------------------------------------------------------
# TODO 2: WAF（掛在 LB 上，var.enable_waf 控制）
#--------------------------------------------------------------
resource "oci_waf_web_app_firewall_policy" "this" {
  count = var.enable_waf ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-waf-policy"
  freeform_tags  = local.common_tags

  actions {
    name = "block403"
    type = "RETURN_HTTP_RESPONSE"
    code = 403

    body {
      type = "STATIC_TEXT"
      text = "blocked by WAF"
    }
  }

  # OWASP：SQLi（libinjection）、XSS（libinjection）
  request_protection {
    rules {
      name        = "owasp-sqli-xss"
      type        = "PROTECTION"
      action_name = "block403"

      protection_capabilities {
        key     = "942100"
        version = 1
      }

      protection_capabilities {
        key     = "941100"
        version = 2
      }
    }
  }

  # 每個 client IP 60 秒超過 50 次就擋 60 秒
  request_rate_limiting {
    rules {
      name        = "rate-limit"
      type        = "REQUEST_RATE_LIMITING"
      action_name = "block403"

      configurations {
        period_in_seconds          = 60
        requests_limit             = 50
        action_duration_in_seconds = 60
      }
    }
  }
}

resource "oci_waf_web_app_firewall" "this" {
  count = var.enable_waf ? 1 : 0

  compartment_id             = var.compartment_id
  display_name               = "${var.name_prefix}-waf"
  backend_type               = "LOAD_BALANCER"
  load_balancer_id           = oci_load_balancer_load_balancer.this.id
  web_app_firewall_policy_id = oci_waf_web_app_firewall_policy.this[0].id
  freeform_tags              = local.common_tags
}

#--------------------------------------------------------------
# TODO 3: Network Firewall（backend 出站，var.enable_network_firewall 控制）
#--------------------------------------------------------------
# 💰💰 最貴的資源。出站只放行：oracle.com 與 *.oraclecloud.com（Bastion plugin 需要）的 80/443，其餘 DROP。
# firewall 對出站做 source NAT（DIPP），回程流量才會回到 firewall，不必改 NAT gateway 的路由。
# ⚠️ 套用後 backend 連 example.com 等會被擋；apply 前確認 Bastion session 已建好。
# ⚠️ FQDN 規則、SNAT、路由導向都還沒實測，apply 後若不通，先查 firewall policy 與 route table。

resource "oci_network_firewall_network_firewall_policy" "this" {
  count = var.enable_network_firewall ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-fw-policy"
  freeform_tags  = local.common_tags
}

resource "oci_network_firewall_network_firewall_policy_address_list" "app" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "app-subnet"
  type                       = "IP"
  addresses                  = [local.app_subnet_cidr]
}

resource "oci_network_firewall_network_firewall_policy_address_list" "allowed_fqdn" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "allowed-fqdn"
  type                       = "FQDN"
  addresses                  = ["oracle.com", "www.oracle.com", "*.oraclecloud.com"]
}

resource "oci_network_firewall_network_firewall_policy_service" "http" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "tcp-80"
  type                       = "TCP_SERVICE"

  port_ranges {
    minimum_port = 80
    maximum_port = 80
  }
}

resource "oci_network_firewall_network_firewall_policy_service" "https" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "tcp-443"
  type                       = "TCP_SERVICE"

  port_ranges {
    minimum_port = 443
    maximum_port = 443
  }
}

resource "oci_network_firewall_network_firewall_policy_service_list" "web" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "web"
  services = [
    oci_network_firewall_network_firewall_policy_service.http[0].name,
    oci_network_firewall_network_firewall_policy_service.https[0].name,
  ]
}

resource "oci_network_firewall_network_firewall_policy_security_rule" "allow_web" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "allow-web-to-allowed-fqdn"
  action                     = "ALLOW"

  condition {
    source_address      = [oci_network_firewall_network_firewall_policy_address_list.app[0].name]
    destination_address = [oci_network_firewall_network_firewall_policy_address_list.allowed_fqdn[0].name]
    service             = [oci_network_firewall_network_firewall_policy_service_list.web[0].name]
  }
}

resource "oci_network_firewall_network_firewall_policy_security_rule" "drop_all" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "drop-all"
  action                     = "DROP"

  condition {}

  # 規則依建立順序評估：drop-all 必須排在 allow 之後
  depends_on = [oci_network_firewall_network_firewall_policy_security_rule.allow_web]
}

resource "oci_network_firewall_network_firewall_policy_nat_rule" "snat" {
  count = var.enable_network_firewall ? 1 : 0

  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  name                       = "snat-app"
  type                       = "NATV4"
  action                     = "DIPP_SRC_NAT"

  condition {
    source_address = [oci_network_firewall_network_firewall_policy_address_list.app[0].name]
  }
}

# firewall 的 NSG：收 app subnet 的所有流量
resource "oci_core_network_security_group" "fw" {
  count = var.enable_network_firewall ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg-fw"
  freeform_tags  = local.common_tags
}

resource "oci_core_network_security_group_security_rule" "fw_in" {
  count = var.enable_network_firewall ? 1 : 0

  network_security_group_id = oci_core_network_security_group.fw[0].id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = local.app_subnet_cidr
  source_type               = "CIDR_BLOCK"
}

resource "oci_core_network_security_group_security_rule" "fw_out" {
  count = var.enable_network_firewall ? 1 : 0

  network_security_group_id = oci_core_network_security_group.fw[0].id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

resource "oci_network_firewall_network_firewall" "this" {
  count = var.enable_network_firewall ? 1 : 0

  compartment_id             = var.compartment_id
  display_name               = "${var.name_prefix}-fw"
  subnet_id                  = oci_core_subnet.fw.id
  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.this[0].id
  network_security_group_ids = [oci_core_network_security_group.fw[0].id]
  freeform_tags              = local.common_tags

  # policy 的物件都建好才建 firewall
  depends_on = [
    oci_network_firewall_network_firewall_policy_security_rule.drop_all,
    oci_network_firewall_network_firewall_policy_nat_rule.snat,
  ]
}

# route rule 的目標要 private IP 的 OCID，不是 IP 字串
data "oci_core_private_ips" "fw" {
  count = var.enable_network_firewall ? 1 : 0

  subnet_id  = oci_core_subnet.fw.id
  ip_address = oci_network_firewall_network_firewall.this[0].ipv4address
}

#--------------------------------------------------------------
# TODO 4: Bastion（MANAGED_SSH，免費）
#--------------------------------------------------------------
resource "oci_bastion_bastion" "this" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_id
  target_subnet_id             = oci_core_subnet.app.id
  name                         = "${replace(var.name_prefix, "-", "")}bastion" # 只允許英數
  client_cidr_block_allow_list = [var.allowed_cidr]
  max_session_ttl_in_seconds   = 10800
  freeform_tags                = local.common_tags
}

resource "oci_bastion_session" "backend" {
  count = var.ssh_public_key == null ? 0 : var.backend_count

  bastion_id             = oci_bastion_bastion.this.id
  display_name           = "${var.name_prefix}-ssh-${count.index + 1}"
  session_ttl_in_seconds = 10800

  key_details {
    public_key_content = var.ssh_public_key
  }

  target_resource_details {
    session_type                               = "MANAGED_SSH"
    target_resource_id                         = oci_core_instance.backend[count.index].id
    target_resource_operating_system_user_name = "opc"
    target_resource_port                       = 22
  }
}
