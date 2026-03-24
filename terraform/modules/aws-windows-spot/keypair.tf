# ---------- Key Pair (auto-generated) ----------
resource "tls_private_key" "win2025" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "win2025" {
  key_name   = "win2025-key"
  public_key = tls_private_key.win2025.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.win2025.private_key_pem
  filename        = "${path.module}/win2025-key.pem"
  file_permission = "0600"
}
