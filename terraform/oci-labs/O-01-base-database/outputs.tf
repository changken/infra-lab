#==============================================================
# TODO 3: 連線資訊
#
# 透過 DB Node 與 VNIC 查出 Private IP，並組合 Oracle 連線字串
# （DB 在 private subnet，連線一律走 Bastion tunnel → localhost）
#==============================================================

#--------------------------------------------------------------
# Data Sources: 查詢 DB Node 與 VNIC private IP
#--------------------------------------------------------------
data "oci_database_db_nodes" "this" {
  compartment_id = var.compartment_id
  db_system_id   = oci_database_db_system.this.id
}

data "oci_core_vnic" "db_node_vnic" {
  vnic_id = data.oci_database_db_nodes.this.db_nodes[0].vnic_id
}

locals {
  private_ip       = data.oci_core_vnic.db_node_vnic.private_ip_address
  pdb_service_name = "${var.pdb_name}.${oci_database_db_system.this.domain}"
}

#--------------------------------------------------------------
# Outputs
#--------------------------------------------------------------
output "db_system_id" {
  description = "DB System OCID"
  value       = oci_database_db_system.this.id
}

output "private_ip" {
  description = "DB Node Private IP（Bastion session 的 target）"
  value       = local.private_ip
}

#--------------------------------------------------------------
# TODO 5: Bastion tunnel 指令（做完 TODO 4 再解開）
#--------------------------------------------------------------
# 提示：
#   - oci_bastion_session 有 `ssh_metadata` 屬性（map），裡面有現成的 command
#   - command 內有 <privateKey>、<localPort> 佔位字串，用 replace() 換成
#     你的私鑰路徑與 local port（SSH 用 2222、SQL*Net 用 1521）
#   - 兩個 session 各出一個 output：
#       ssh_tunnel_command / sql_tunnel_command
#
# output "ssh_tunnel_command" {}
# output "sql_tunnel_command" {}

output "ssh_tunnel_command" {
  description = "SSH tunnel（本機 2222 → DB node :22）開啟指令"
  value = replace(
    replace(oci_bastion_session.this["ssh"].ssh_metadata["command"], "<privateKey>", var.private_key_path),
    "<localPort>", "2222"
  )
}

output "sql_tunnel_command" {
  description = "SQL*Net tunnel（本機 1521 → DB node :1521）開啟指令"
  value = replace(
    replace(oci_bastion_session.this["sqlnet"].ssh_metadata["command"], "<privateKey>", var.private_key_path),
    "<localPort>", "1521"
  )
}

# 以下連線字串都假設 tunnel 已開，連 localhost
output "ssh_command" {
  description = "SSH tunnel（本機 2222 → DB node :22）開好後的登入指令"
  value       = replace("ssh -i <private_key> -p 2222 opc@localhost", "<private_key>", var.private_key_path)
}

output "sqlplus_command" {
  description = "tunnel 開好後，連到 PDB 的 EZConnect 指令"
  value       = "sqlplus system/${var.db_admin_password}@//localhost:1521/${local.pdb_service_name}"
  sensitive   = true
}

output "jdbc_url" {
  description = "JDBC Thin 連線字串（走 tunnel）"
  value       = "jdbc:oracle:thin:@//localhost:1521/${local.pdb_service_name}"
}

output "ado_url" {
  description = "ADO.NET 連線字串（走 tunnel）"
  value       = "Data Source=localhost:1521/${local.pdb_service_name};User Id=system;Password=${var.db_admin_password};"
  sensitive   = true
}
