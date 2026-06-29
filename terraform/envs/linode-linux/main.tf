#==============================================================
# env: linode-linux — Linode (Akamai Cloud) Linux Instance
#
# 拓樸：
#   你的電腦 --SSH (22)--> Linode Instance (Public IP)
#
# 資源：
#   - linode_firewall : 防火牆（預設 DROP inbound，指定規則 ACCEPT）
#   - linode_instance : Ubuntu 24.04 Instance（SSH Key 直接注入）
#
# 注意：Linode 不需要獨立的 SSH Key resource，
#       public key 直接透過 authorized_keys 傳入 instance。
#==============================================================

# ── 1. Firewall ────────────────────────────────────────────
# Linode Firewall 採「白名單」模式：
#   - inbound_policy  = "DROP"   → 預設拒絕所有入站
#   - outbound_policy = "ACCEPT" → 預設放行所有出站
# 需要放行的 inbound 流量需明確加 ACCEPT rule。

resource "linode_firewall" "main" {
  label = "${var.project}-${var.environment}-fw"
  tags  = local.tags

  # 僅允許你的 IP SSH 連入
  inbound {
    label    = "allow-ssh-from-my-ip"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = [var.my_ip]
  }

  # 允許 ICMP（ping）
  inbound {
    label    = "allow-icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [linode_instance.main.id]
}

# ── 2. Linode Instance ─────────────────────────────────────

resource "linode_instance" "main" {
  label           = var.label
  region          = var.region
  type            = var.type
  image           = var.image
  authorized_keys = [var.ssh_public_key]
  tags            = local.tags
  backups_enabled = var.backups_enabled
  swap_size       = var.swap_size
}
