#==============================================================
# TODO 3: 連線資訊
#
# 透過 DB Node 與 VNIC 查出 Public IP，並組合 Oracle 連線字串
#==============================================================

#--------------------------------------------------------------
# Data Sources: 查詢 DB Node 與 VNIC 公網 IP
#--------------------------------------------------------------
data "oci_database_db_nodes" "this" {
  compartment_id = var.compartment_id
  db_system_id   = oci_database_db_system.this.id
}

data "oci_core_vnic" "db_node_vnic" {
  vnic_id = data.oci_database_db_nodes.this.db_nodes[0].vnic_id
}

locals {
  public_ip        = data.oci_core_vnic.db_node_vnic.public_ip_address
  pdb_service_name = "${var.pdb_name}.${oci_database_db_system.this.domain}"
}

#--------------------------------------------------------------
# Outputs
#--------------------------------------------------------------
output "db_system_id" {
  description = "DB System OCID"
  value       = oci_database_db_system.this.id
}

output "public_ip" {
  description = "DB Node Public IP"
  value       = local.public_ip
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh -i <private_key> opc@${local.public_ip}"
}

output "sqlplus_command" {
  description = "連到 PDB 的 EZConnect 指令"
  value       = "sqlplus system/${var.db_admin_password}@//${local.public_ip}:1521/${local.pdb_service_name}"
  sensitive   = true
}

output "jdbc_url" {
  description = "JDBC Thin 連線字串"
  value       = "jdbc:oracle:thin:@//${local.public_ip}:1521/${local.pdb_service_name}"
}

output "ado_url" {
  description = "ADO.NET 連線字串"
  value       = "Data Source=${local.public_ip}:1521/${local.pdb_service_name};User Id=system;Password=${var.db_admin_password};"
  sensitive   = true
}
