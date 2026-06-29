#==============================================================
# env: hetzner-linux — Hetzner Cloud Linux Server
#
# 拓樸：
#   你的電腦 --SSH (22)--> Hetzner Server (Public IP)
#
# 資源：
#   - hcloud_ssh_key  : 上傳 SSH 公鑰
#   - hcloud_firewall : 防火牆（僅允許你的 IP SSH + ICMP）
#   - hcloud_server   : Ubuntu 24.04 Cloud Server
#==============================================================

# ── 1. SSH Key ─────────────────────────────────────────────

resource "hcloud_ssh_key" "main" {
  name       = "${var.project}-${var.environment}-key"
  public_key = var.ssh_public_key
  labels     = local.labels
}

# ── 2. Firewall ────────────────────────────────────────────
# Hetzner Firewall 僅需設定 inbound rules；outbound 預設全部放行。

resource "hcloud_firewall" "main" {
  name   = "${var.project}-${var.environment}-fw"
  labels = local.labels

  # 僅允許你的 IP SSH 連入
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.my_ip]
    description = "Allow SSH from my IP only"
  }

  # 允許 ICMP（ping）
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "Allow ICMP from anywhere"
  }
}

# ── 3. Server ──────────────────────────────────────────────

resource "hcloud_server" "main" {
  name         = var.server_name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.main.name]
  firewall_ids = [hcloud_firewall.main.id]
  backups      = var.backups
  labels       = local.labels

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  shutdown_before_deletion = true
}
