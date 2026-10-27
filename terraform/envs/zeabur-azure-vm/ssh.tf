resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

# OpenSSH 格式（-----BEGIN OPENSSH PRIVATE KEY-----），Zeabur 只吃這格式
resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/.ssh/${local.name_prefix}_ed25519"
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.ssh.public_key_openssh
  filename        = "${path.module}/.ssh/${local.name_prefix}_ed25519.pub"
  file_permission = "0644"
}
