#==============================================================
# TODO 6: 連線資訊
#
# 從 TODO 1 的資源找出連線字串與 service name
#==============================================================
# 提示：
#   - oci_database_autonomous_database.this.connection_strings[0].profiles
#     有 high / medium / low / tp / tpurgent 等 consumer group
#   - 想一想：mTLS（需 wallet）與 TLS（不需 wallet）各是哪個 port？
#     `is_mtls_connection_required` 預設為 true，要不要改？
#
# output "adb_id" {}
# output "connection_urls" {}
# output "sqlplus_command" { sensitive = true }

output "adb_id" {
  value = oci_database_autonomous_database.this.id
}

output "connection_urls" {
  value = oci_database_autonomous_database.this.connection_strings
}

output "sqlplus_command" {
  value     = "sqlplus admin@'${oci_database_autonomous_database.this.connection_strings[0].high}'"
  sensitive = true
}

#--------------------------------------------------------------
# TODO 8: Bastion tunnel 指令
#--------------------------------------------------------------
# 把 TODO 7 的 session 組成可直接貼上的 SSH tunnel 指令。
# 提示：
#   - oci_bastion_session 有 `ssh_metadata` 屬性（map），裡面有現成的 command
#   - 想一想：本機 port 要對應 ADB 的哪個 port？
#   - 輸出結果要把 <privateKey> 換成你的私鑰路徑
#
# output "bastion_tunnel_command" {}

output "bastion_tunnel_command" {
  value = replace(oci_bastion_session.this.ssh_metadata["command"], "<privateKey>", "~/.ssh/id_rsa")
}