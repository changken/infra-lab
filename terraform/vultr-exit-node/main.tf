locals {
  tags = [
    "project:vultr-exit-node",
    "managed-by:opentofu",
  ]

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname           = var.hostname
    tailscale_auth_key = var.tailscale_auth_key
  })
}

resource "vultr_firewall_group" "exit_node" {
  description = "${var.hostname} Tailscale exit node"
}

# Optional direct Tailscale connectivity. No public SSH rule is created.
resource "vultr_firewall_rule" "tailscale_udp_ipv4" {
  count = var.allow_tailscale_udp_41641 ? 1 : 0

  firewall_group_id = vultr_firewall_group.exit_node.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "41641"
  notes             = "Optional Tailscale direct connectivity over IPv4"
}

resource "vultr_firewall_rule" "tailscale_udp_ipv6" {
  count = var.allow_tailscale_udp_41641 && var.enable_ipv6 ? 1 : 0

  firewall_group_id = vultr_firewall_group.exit_node.id
  protocol          = "udp"
  ip_type           = "v6"
  subnet            = "::"
  subnet_size       = 0
  port              = "41641"
  notes             = "Optional Tailscale direct connectivity over IPv6"
}

resource "vultr_instance" "exit_node" {
  region            = var.region
  plan              = var.plan
  os_id             = var.os_id
  hostname          = var.hostname
  label             = var.hostname
  tags              = local.tags
  enable_ipv6       = var.enable_ipv6
  backups           = "disabled"
  activation_email  = false
  firewall_group_id = vultr_firewall_group.exit_node.id
  user_data         = local.cloud_init

  # Attach the firewall rules before the VM starts cloud-init.
  depends_on = [
    vultr_firewall_rule.tailscale_udp_ipv4,
    vultr_firewall_rule.tailscale_udp_ipv6,
  ]
}
