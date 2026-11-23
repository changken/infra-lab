output "stream_pool_id" {
  description = "Stream Pool OCID；Kafka Connection Settings 會用到"
  value       = oci_streaming_stream_pool.this.id
}

output "stream_id" {
  description = "OCI Stream OCID"
  value       = oci_streaming_stream.integration_events.id
}

output "stream_name" {
  description = "Kafka topic／OCI Stream 名稱"
  value       = oci_streaming_stream.integration_events.name
}
