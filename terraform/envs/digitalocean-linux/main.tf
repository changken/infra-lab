#==============================================================
# env: digitalocean-linux — DigitalOcean Droplet Linux VM
#
# 拓樸：
#   你的電腦 --SSH (22)--> Droplet (Public IP)
#
# 資源：
#   - digitalocean_ssh_key : 上傳 SSH 公鑰
#   - digitalocean_firewall: Cloud Firewall（限制 SSH 來源 + 放行全部 outbound）
#   - digitalocean_droplet : Ubuntu 22.04 Droplet
#==============================================================

# ── 1. SSH Key ─────────────────────────────────────────────

resource "digitalocean_ssh_key" "main" {
  name       = "${var.project}-${var.environment}-key"
  public_key = var.ssh_public_key
}

# ── 2. Cloud Firewall ──────────────────────────────────────

resource "digitalocean_firewall" "main" {
  name        = "${var.project}-${var.environment}-fw"
  droplet_ids = [digitalocean_droplet.main.id]

  # 僅允許你的 IP SSH 連入
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [var.my_ip]
  }

  # 允許 ICMP（ping）
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # 放行全部對外流量
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# ── 3. Droplet ─────────────────────────────────────────────

resource "digitalocean_droplet" "main" {
  name       = local.droplet_name
  region     = var.region
  size       = var.size
  image      = var.image
  ssh_keys   = [digitalocean_ssh_key.main.fingerprint]
  ipv6       = var.ipv6
  monitoring = var.monitoring
  backups    = var.backups
  tags       = local.tags
}
