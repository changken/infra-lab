#==============================================================
# TODO 5: 連線資訊與 PAR 網址
#==============================================================
# 提示：
#   (a) adb_id：給 CLI 驗證用
#
#   (b) tls_connect_string：不帶 wallet 的連線字串
#       - oci_database_autonomous_database.this.connection_strings[0].profiles
#         是一個 list，每個元素有 consumer_group、protocol、tls_authentication、value
#       - 用 for 運算式挑出「不需要客戶端憑證」且 consumer_group 是 LOW 的那一筆
#         （先用 terraform console 看 tls_authentication 有哪些值）
#       - 想一想：為什麼 lab 用 LOW 而不是 HIGH？（O-02 練過 consumer group）
#
#   (c) par_base_url：bucket 層級 PAR 的完整網址
#       - oci_objectstorage_preauthrequest 有 access_uri 與 full_path 兩個屬性，
#         哪一個才是可以直接貼進 SQL 的完整網址？
#       - ⚠️ 這個 output 一定要 sensitive = true
#
# output "adb_id" {}
# output "tls_connect_string" {}
# output "par_base_url" { sensitive = true }

output "adb_id" {
  value = oci_database_autonomous_database.this.id
}

output "tls_connect_string" {
  value = [for p in oci_database_autonomous_database.this.connection_strings[0].profiles : p.value if p.tls_authentication == "SERVER" && p.consumer_group == "LOW"][0]
}

output "par_base_url" {
  value     = oci_objectstorage_preauthrequest.this.full_path
  sensitive = true
}
