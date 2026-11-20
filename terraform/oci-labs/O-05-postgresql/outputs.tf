#==============================================================
# TODO 5: 連線資訊
#==============================================================

output "db_system_id" {
  value = oci_psql_db_system.this.id
}

output "db_private_ip" {
  description = "writer（primary）endpoint 的 private IP"
  value       = oci_psql_db_system.this.network_details[0].primary_db_endpoint_private_ip
}

output "instances" {
  description = "各 instance 的名稱與狀態（instances 屬性沒有 private IP；reader endpoint 的 IP 請看 Console）"
  value       = [for i in oci_psql_db_system.this.instances : "${i.display_name} (${i.state})"]
}

output "bastion_tunnel_command" {
  value = replace(oci_bastion_session.this.ssh_metadata["command"], "<privateKey>", "~/.ssh/id_rsa")
}

output "psql_command" {
  value = "psql \"host=127.0.0.1 port=5432 user=${var.admin_username} dbname=postgres sslmode=require\""
}
