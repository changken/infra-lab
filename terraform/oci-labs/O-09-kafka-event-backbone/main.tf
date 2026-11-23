#==============================================================
# OCI Streaming：Kafka-compatible event backbone
#
# 不建立 VM 或 VCN。Producer / consumer 在本機執行，透過
# Kafka protocol + SASL_SSL 連到 OCI Streaming。
#==============================================================

#--------------------------------------------------------------
# Stream Pool
#--------------------------------------------------------------
# 文件:
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/streaming_stream_pool
#
# 目前先用小型 lab 設定。確認 OCI Kafka compatibility、topic 自動建立、
# retention 與 partition 的意義，再依你的實驗目標調整。
#
# 注意：OCI Streaming 的 Kafka 相容設定屬於 Stream Pool；Terraform 建立的
# oci_streaming_stream 對應一個可由 Kafka client 存取的 topic。

resource "oci_streaming_stream_pool" "this" {
  compartment_id = var.compartment_id
  name           = "${var.name_prefix}-pool"
  freeform_tags  = local.common_tags

  kafka_settings {
    auto_create_topics_enable = false
    log_retention_hours       = var.retention_in_hours
    num_partitions            = var.partitions
  }
}

#--------------------------------------------------------------
# integration-events Stream
#--------------------------------------------------------------
# 文件:
# https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/streaming_stream
#
# 觀察 partitions 與 retention_in_hours 如何影響事件排序、擴展與成本。
# Terraform 管理 topic，因此 Kafka client 不需要也不應自動建立 topic。

resource "oci_streaming_stream" "integration_events" {
  compartment_id     = var.compartment_id
  name               = var.stream_name
  partitions         = var.partitions
  retention_in_hours = var.retention_in_hours
  stream_pool_id     = oci_streaming_stream_pool.this.id
  freeform_tags      = local.common_tags
}
