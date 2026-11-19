#--------------------------------------------------------------
# CPU 自架 LLM 用的 E5 Flex 實例（由 Console 手動建立後 import）
#
# 💰 付費資源（無 Always Free），11/22 前必須 destroy。
# 現況規格（23 OCPU / 276 GB / boot 1024 GB ultra high）遠大於規劃
# （8 OCPU / 64 GB），建議 import 後先調小再跑 llama.cpp / Ollama。
#--------------------------------------------------------------
resource "oci_core_instance" "llm" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  fault_domain        = var.fault_domain
  display_name        = var.instance_name
  shape               = var.shape

  metadata = {
    ssh_authorized_keys = trimspace(var.ssh_public_key)
  }

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = "true"
    display_name     = var.hostname_label
    hostname_label   = var.hostname_label
    private_ip       = var.private_ip
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
    boot_volume_vpus_per_gb = var.boot_volume_vpus_per_gb
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
