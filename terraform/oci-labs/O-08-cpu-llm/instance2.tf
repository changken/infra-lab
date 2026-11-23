#--------------------------------------------------------------
# 第二台 E5 Flex（Terraform 直接建立，不是 import）
#
# 💰 付費資源（無 Always Free），11/21 前 terraform destroy。
# 用途：與 oci_core_instance.llm 同題比較（不同規格 / 量化模型）。
# 規格、名稱、hostname 都在 var.instance2。
# 內網 IP 交給 DHCP 分配（不固定），公網 IP 為 ephemeral。
#--------------------------------------------------------------
resource "oci_core_instance" "llm2" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  fault_domain        = var.instance2.fault_domain
  display_name        = var.instance2.name
  shape               = var.instance2.shape

  metadata = {
    ssh_authorized_keys = trimspace(var.ssh_public_key)
  }

  shape_config {
    ocpus         = var.instance2.ocpus
    memory_in_gbs = var.instance2.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = "true"
    display_name     = var.instance2.hostname_label
    hostname_label   = var.instance2.hostname_label
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.instance2.boot_volume_size_in_gbs
    boot_volume_vpus_per_gb = var.instance2.boot_volume_vpus_per_gb
  }

  freeform_tags = local.common_tags

  lifecycle {
    ignore_changes = [
      defined_tags,
      source_details[0].source_id, # image 更新不應觸發重建
      create_vnic_details[0].defined_tags,
    ]
  }
}
