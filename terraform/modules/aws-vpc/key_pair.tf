#--------------------------------------------------------------
# SSH Key Pair for k3s nodes
#
# 安全說明：
# - 此 Terraform 配置僅使用 PUBLIC KEY，不會上傳或儲存 SSH Private Key
# - Private Key 仍然保留在您的本地機器 (~/.ssh/)
# - 使用 RSA-4096 金鑰對以獲得更好的安全性
#
# SSH Key 生成方式 (建議使用 RSA-4096)：
# ---------------------------------------------------
# 1. 執行此命令生成密鑰對 (若 ~/.ssh/id_rsa.pub 不存在)：
#    ssh-keygen -t rsa -b 4096 -C "your-email@example.com" -f ~/.ssh/id_rsa -N ""
#
# 2. 按 Enter 使用預設位置
#    會在 ~/.ssh/ 生成兩個檔案：
#    - id_rsa (Private Key，請妥善保管，勿上傳至雲端)
#    - id_rsa.pub (Public Key，會被上傳至 AWS)
#
# 3. 如果您已經有金鑰，請確認以下路徑存在：
#    ~/.ssh/id_rsa.pub
#
# 針對 autok3s 的用法，此金鑰對將用於 SSH 登入 EC2 節點
#--------------------------------------------------------------
resource "aws_key_pair" "k3s" {
  key_name   = "k3s-key-pair"
  public_key = file("./.ssh/id_rsa.pub")

  tags = merge(local.common_tags, {
    Name = "k3s-key-pair"
  })
}

#--------------------------------------------------------------
# 變數：若您想自訂 SSH 金鑰路徑，可以加入此變數
#
# variable "ssh_public_key_path" {
#   description = "路徑至 SSH 公鑰檔案"
#   type        = string
#   default     = "~/.ssh/id_rsa.pub"
# }
#
# 然後在資源中使用：
# public_key = file(var.ssh_public_key_path)
