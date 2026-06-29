#==============================================================
# env: vultr-linux — Vultr Cloud Compute Linux VM
#
# 拓樸：
#   你的電腦 --SSH (22)--> Vultr Instance (Public IP)
#
# 資源：
#   - vultr_ssh_key       : 上傳 SSH 公鑰
#   - vultr_firewall_group: 防火牆群組
#   - vultr_firewall_rule : 僅允許你的 IP SSH 進入
#   - vultr_instance      : Ubuntu 22.04 Cloud Compute VM
#==============================================================

# ── 1. SSH Key ─────────────────────────────────────────────

resource "vultr_ssh_key" "main" {
  name    = "${local.instance_label}-key"
  ssh_key = var.ssh_public_key
}

# ── 2. Firewall Group ──────────────────────────────────────

resource "vultr_firewall_group" "main" {
  description = "${local.instance_label} firewall"
}

# ── 3. Firewall Rules ──────────────────────────────────────

resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.main.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = cidrhost(var.my_ip, 0)
  subnet_size       = tonumber(split("/", var.my_ip)[1])
  port              = "22"
  notes             = "Allow SSH from my IP only"
}

# ── 4. Vultr Instance ──────────────────────────────────────

resource "vultr_instance" "main" {
  region            = var.region
  plan              = var.plan
  os_id             = var.os_id
  hostname          = var.hostname
  label             = local.instance_label
  tags              = local.tags
  ssh_key_ids       = [vultr_ssh_key.main.id]
  firewall_group_id = vultr_firewall_group.main.id
  enable_ipv6       = var.enable_ipv6
  backups           = var.backups
  activation_email  = false
}
