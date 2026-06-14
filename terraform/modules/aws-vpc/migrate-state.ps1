# migrate-state.ps1
# 將 aws-vpc module 的 subnet state 從舊的硬編碼命名遷移到 for_each key
#
# 使用方式：
#   1. 在你的 terraform env 目錄下執行（有 .terraform/ 的那個目錄）
#   2. 修改下方 $AzA / $AzB 為你實際使用的 AZ
#   3. .\path\to\migrate-state.ps1

$ErrorActionPreference = "Stop"

# ── 請依實際情況修改 ──────────────────────────────────────────
$AzA = "us-east-1a"
$AzB = "us-east-1b"

# 如果是透過 module 呼叫，prefix 為 "module.<module_name>."
# 直接使用 module root 則設為 ""
#$Prefix = ""
$Prefix = "module.aws-vpc.module.vpc."
# ──────────────────────────────────────────────────────────────

Write-Host "==> Migrating subnet state..."

terraform state mv "${Prefix}aws_subnet.public_a"  "${Prefix}aws_subnet.public[`"$AzA`"]"
terraform state mv "${Prefix}aws_subnet.public_b"  "${Prefix}aws_subnet.public[`"$AzB`"]"
terraform state mv "${Prefix}aws_subnet.private_a" "${Prefix}aws_subnet.private[`"$AzA`"]"
terraform state mv "${Prefix}aws_subnet.private_b" "${Prefix}aws_subnet.private[`"$AzB`"]"

Write-Host "==> Migrating route table association state..."

terraform state mv "${Prefix}aws_route_table_association.public_a"  "${Prefix}aws_route_table_association.public[`"$AzA`"]"
terraform state mv "${Prefix}aws_route_table_association.public_b"  "${Prefix}aws_route_table_association.public[`"$AzB`"]"
terraform state mv "${Prefix}aws_route_table_association.private_a" "${Prefix}aws_route_table_association.private[`"$AzA`"]"
terraform state mv "${Prefix}aws_route_table_association.private_b" "${Prefix}aws_route_table_association.private[`"$AzB`"]"

Write-Host "==> Done. Run 'terraform plan' to verify no destructive changes."
