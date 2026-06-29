# admin_ssh_public_key 未填時自動生成金鑰對（私鑰存入本地檔案）
# ⚠️ 自動生成的私鑰會進入 tfstate，僅建議測試環境使用

resource "tls_private_key" "linux" {
  count     = local.use_generated_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  count           = local.use_generated_key ? 1 : 0
  content         = tls_private_key.linux[0].private_key_pem
  filename        = "${path.module}/${var.name_prefix}-key.pem"
  file_permission = "0600"
}
