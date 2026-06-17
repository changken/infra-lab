# ---------- Key Pair ----------
# 若提供 public_key_content，直接使用；否則自動生成（私鑰會存入 tfstate，僅建議於測試環境）
resource "tls_private_key" "win2025" {
  count     = var.public_key_content == null ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "win2025" {
  key_name   = "${var.name_prefix}-key"
  public_key = var.public_key_content != null ? var.public_key_content : tls_private_key.win2025[0].public_key_openssh
}

resource "local_file" "private_key" {
  count           = var.public_key_content == null ? 1 : 0
  content         = tls_private_key.win2025[0].private_key_pem
  filename        = "${path.module}/${var.name_prefix}-key.pem"
  file_permission = "0600"
}
