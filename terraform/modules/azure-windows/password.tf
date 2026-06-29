# admin_password 未填時自動生成（結果存入 tfstate）
# ⚠️ 僅建議測試環境使用；生產環境請明確傳入 admin_password

resource "random_password" "win" {
  count            = local.use_generated_password ? 1 : 0
  length           = 20
  special          = true
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+"
}

resource "local_sensitive_file" "password" {
  count    = local.use_generated_password ? 1 : 0
  content  = random_password.win[0].result
  filename = "${path.module}/${var.name_prefix}-password.txt"
}
