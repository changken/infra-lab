#==============================================================
# env: gcp-linux — GCP Compute Engine Linux VM
#
# 拓樸：
#   你的電腦 --SSH (22)--> GCP VM (Ephemeral Public IP)
#
# 資源：
#   - google_compute_firewall : VPC Firewall rule（依 network tag 套用）
#   - google_compute_instance : Ubuntu 24.04 VM（SSH Key 透過 metadata 注入）
#
# GCP Firewall 設計：
#   - Firewall rule 掛在 VPC 層（非 instance 層）
#   - 透過 target_tags 指定套用到有對應 tag 的 VM
#   - SSH Key 不需獨立 resource，透過 metadata["ssh-keys"] 注入
#   - GCP 不允許直接 root SSH，需指定一般使用者（ssh_user）
#==============================================================

# ── 1. Firewall Rule（SSH） ────────────────────────────────
# 使用 default VPC network，只允許你的 IP 透過 tag 存取 VM

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project}-${var.environment}-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # 僅允許你的 IP
  source_ranges = [var.my_ip]

  # 只套用到有此 tag 的 VM
  target_tags = [local.ssh_tag]

  description = "Allow SSH from my IP to tagged instances"
}

# ── 2. Compute Instance ────────────────────────────────────

resource "google_compute_instance" "main" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  labels       = local.labels

  # 套用 SSH firewall rule 的 network tag
  tags = [local.ssh_tag]

  boot_disk {
    initialize_params {
      image  = var.boot_image
      size   = var.disk_size_gb
      labels = local.labels
    }
  }

  network_interface {
    network = "default"

    # 配置 Ephemeral 公網 IP（空 access_config 表示自動分配）
    access_config {}
  }

  # SSH Key 透過 metadata 注入
  # 格式：<使用者名稱>:<ssh public key>
  metadata = {
    "ssh-keys" = "${var.ssh_user}:${var.ssh_public_key}"
  }

  # 啟動時自動更新套件清單
  metadata_startup_script = "apt-get update -y"
}
