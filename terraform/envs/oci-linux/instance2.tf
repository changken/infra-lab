#--------------------------------------------------------------
# 第二台 Always Free A1 Flex（由既有資源 import 而來）
# 護欄同 a1_primary：A1 缺貨，prevent_destroy 阻止 destroy / replace。
# 注意：prevent_destroy 只擋 Terraform，擋不了 Console 手動刪除。
#--------------------------------------------------------------
resource "oci_core_instance" "a1_secondary" {
  compartment_id      = var.compartment_id
  availability_domain = "pimc:AP-SINGAPORE-1-AD-1"
  fault_domain        = "FAULT-DOMAIN-2"
  display_name        = var.instance_names.secondary
  shape               = "VM.Standard.A1.Flex"

  metadata = {
    ssh_authorized_keys = "${trimspace(var.ssh_public_key)}\n"
  }

  # A1 Always Free 總額 4 OCPU / 24 GB：兩台各 2 / 12，已用滿，不可再加 A1 資源。
  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    nsg_ids          = [var.nsg_id]
    assign_public_ip = "true"
    display_name     = var.instance_names.secondary
    hostname_label   = var.instance_names.secondary
    private_ip       = var.ocivm2_private_ip
  }

  source_details {
    source_type             = "bootVolume"
    source_id               = var.boot_volume_ids.ocivm2_k3s
    boot_volume_size_in_gbs = "47"
    boot_volume_vpus_per_gb = "10"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      defined_tags,
      metadata,       # 這台的 ssh key 與 var.ssh_public_key 不同，改 metadata 會強制重建
      source_details, # 換開機碟 / image 不應觸發重建
      create_vnic_details[0].defined_tags,
    ]
  }
}

#--------------------------------------------------------------
# Boot volumes（免費額度 block + boot 合計 200 GB；4 × 47 = 188 GB，勿再 clone）
# 已 TERMINATED 的舊碟不納管。
#--------------------------------------------------------------
locals {
  boot_volume_ad = "pimc:AP-SINGAPORE-1-AD-1"
}

# 使用中：第一台 A1 的開機碟（clone 出的 Ubuntu 26.04）
resource "oci_core_boot_volume" "ocivm_k3s" {
  compartment_id      = var.compartment_id
  availability_domain = local.boot_volume_ad
  display_name        = "${var.instance_names.primary}-k3s"
  size_in_gbs         = "47"
  vpus_per_gb         = "10"

  source_details {
    type = "bootVolume"
    id   = var.boot_volume_ids.clone_source
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags, source_details]
  }
}

# 使用中：第二台 A1 的開機碟
resource "oci_core_boot_volume" "ocivm2_k3s" {
  compartment_id      = var.compartment_id
  availability_domain = local.boot_volume_ad
  display_name        = "${var.instance_names.secondary}-k3s"
  size_in_gbs         = "47"
  vpus_per_gb         = "10"

  source_details {
    type = "bootVolume"
    id   = var.boot_volume_ids.clone_source
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags, source_details]
  }
}

# 閒置：舊開機碟，保留作回退（確認新碟穩定後可手動刪除）
resource "oci_core_boot_volume" "ocivm_old" {
  compartment_id      = var.compartment_id
  availability_domain = local.boot_volume_ad
  display_name        = "${var.instance_names.primary} (Boot Volume)"
  size_in_gbs         = "47"
  vpus_per_gb         = "10"

  source_details {
    # 原由 image 建立，資源不支援 image 型別；source_details 已 ignore_changes，此為佔位
    type = "bootVolume"
    id   = var.boot_volume_ids.ocivm_old
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags, source_details]
  }
}

resource "oci_core_boot_volume" "ocivm2_old" {
  compartment_id      = var.compartment_id
  availability_domain = local.boot_volume_ad
  display_name        = "${var.instance_names.secondary} (Boot Volume)"
  size_in_gbs         = "47"
  vpus_per_gb         = "10"

  source_details {
    # 原由 image 建立，資源不支援 image 型別；source_details 已 ignore_changes，此為佔位
    type = "bootVolume"
    id   = var.boot_volume_ids.ocivm2_old
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags, source_details]
  }
}

#--------------------------------------------------------------
# 手動 boot volume backup（免費額度 5 份）
#--------------------------------------------------------------
resource "oci_core_boot_volume_backup" "init_bk_1437" {
  boot_volume_id = oci_core_boot_volume.ocivm_k3s.id
  display_name   = var.backup_names.first
  type           = "FULL"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags]
  }
}

resource "oci_core_boot_volume_backup" "init_bk_1438" {
  boot_volume_id = oci_core_boot_volume.ocivm2_k3s.id
  display_name   = var.backup_names.second
  type           = "FULL"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [defined_tags]
  }
}
