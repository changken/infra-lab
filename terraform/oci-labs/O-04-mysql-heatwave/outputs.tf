#==============================================================
# TODO 5: 連線資訊
#==============================================================
# 提示：
#   (a) db_system_id：給 CLI 驗證用（oci mysql db-system get）
#
#   (b) db_private_ip：DB system 的 private IP
#       - oci_mysql_mysql_db_system 有 ip_address 屬性；HA 開啟後另有 endpoints 清單
#         （想一想：read/write 與 read-only 是否是不同 endpoint？）
#
#   (c) bastion_tunnel_command：把 TODO 4 的 session 組成可直接貼上的 SSH tunnel 指令
#       - oci_bastion_session 的 ssh_metadata 是 map，裡面有現成的 command
#       - 想一想：本機 port 要對應 DB 的哪個 port？
#       - 結果要把 <privateKey> 換成你的私鑰路徑
#
#   (d) mysql_command：tunnel 開好後在本機連線的指令
#       - ⚠️ 不要把密碼寫進 output；用 -p 讓 client 互動式詢問
#
# output "db_system_id" {}
# output "db_private_ip" {}
# output "bastion_tunnel_command" {}
# output "mysql_command" {}

output "db_system_id" {
  value = oci_mysql_mysql_db_system.this.id
}

output "db_private_ip" {
  value = oci_mysql_mysql_db_system.this.ip_address
}

output "bastion_tunnel_command" {
  value = replace(oci_bastion_session.this.ssh_metadata["command"], "<privateKey>", "~/.ssh/id_rsa")
}

output "mysql_command" {
  value = "mysql -h 127.0.0.1 -P 3306 -u ${var.admin_username} -p"
}
