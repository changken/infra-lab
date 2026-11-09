#--------------------------------------------------------------
# Always Free A1 Flex 實例（由既有資源 import 而來）
#
# ⚠️ A1 在 ap-singapore-1 常缺貨（Out of host capacity），一旦被刪除
#    可能無法再建立。因此：
#    - prevent_destroy 阻止 destroy / replace
#    - source_details 改 image 會觸發 replace，故 ignore_changes
#    - 任何 plan 出現 "must be replaced" 都不要 apply
#--------------------------------------------------------------
resource "oci_core_instance" "changken_ocivm" {
  compartment_id      = var.compartment_id
  availability_domain = "pimc:AP-SINGAPORE-1-AD-1"
  fault_domain        = "FAULT-DOMAIN-2"
  display_name        = "changken-ocivm"
  shape               = "VM.Standard.A1.Flex"

  metadata = {
    ssh_authorized_keys = "${trimspace(var.ssh_public_key)}\n"
  }

  # 2026-11 在 Console 由 1 OCPU / 6 GB 擴大為 2 OCPU / 12 GB，程式碼對齊現況。
  # A1 Always Free 總額 4 OCPU / 24 GB，這台佔一半；其他 A1 資源（如 OKE 節點）
  # 合計最多只剩 2 OCPU / 12 GB。
  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    nsg_ids          = [var.nsg_id]
    assign_public_ip = "true"
    display_name     = "a1-sg"
    hostname_label   = "a1-sg"
    private_ip       = "10.87.0.131"
  }

  source_details {
    source_type             = "image"
    source_id               = "ocid1.image.oc1.ap-singapore-1.aaaaaaaairq4jlswlm4ejbrfgqh7zxrnn7mch624ctqqhwmilmik6hbc6c6a"
    boot_volume_size_in_gbs = "47"
    boot_volume_vpus_per_gb = "10"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      defined_tags,
      source_details, # image 更新不應觸發重建
      create_vnic_details[0].defined_tags,
    ]
  }
}
