# ---------- Key Pair ----------
# 優先使用呼叫端傳入的 key_pair_name（例如 module.vpc.key_pair_name）
# 若未提供，則：
#   - 有 public_key_content → 上傳該公鑰
#   - 都沒有 → 自動生成（私鑰存入 tfstate，僅建議測試環境）

locals {
  use_generated_key = var.key_pair_name == null && var.public_key_content == null
  resolved_key_name = var.key_pair_name != null ? var.key_pair_name : aws_key_pair.linux[0].key_name
}

resource "tls_private_key" "linux" {
  count     = local.use_generated_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "linux" {
  count      = var.key_pair_name == null ? 1 : 0
  key_name   = "${var.name_prefix}-key"
  public_key = var.public_key_content != null ? var.public_key_content : tls_private_key.linux[0].public_key_openssh
}

resource "local_file" "private_key" {
  count           = local.use_generated_key ? 1 : 0
  content         = tls_private_key.linux[0].private_key_pem
  filename        = "${path.module}/${var.name_prefix}-key.pem"
  file_permission = "0600"
}
