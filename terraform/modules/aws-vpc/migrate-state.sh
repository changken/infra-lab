#!/usr/bin/env bash
# migrate-state.sh
# 將 aws-vpc module 的 subnet state 從舊的硬編碼命名遷移到 for_each key
#
# 使用方式：
#   1. 在你的 terraform env 目錄下執行（有 .terraform/ 的那個目錄）
#   2. 修改下方 AZ_A / AZ_B 為你實際使用的 AZ
#   3. bash /path/to/migrate-state.sh

set -euo pipefail

# ── 請依實際情況修改 ──────────────────────────────────────────
AZ_A="us-east-1a"
AZ_B="us-east-1b"

# 如果是透過 module 呼叫，prefix 為 module.<module_name>
# 直接使用 module root 則留空字串 ""
MODULE_PREFIX=""   # 例：module.vpc.  or ""
# ──────────────────────────────────────────────────────────────

echo "==> Migrating subnet state..."

terraform state mv \
  "${MODULE_PREFIX}aws_subnet.public_a" \
  "${MODULE_PREFIX}aws_subnet.public[\"${AZ_A}\"]"

terraform state mv \
  "${MODULE_PREFIX}aws_subnet.public_b" \
  "${MODULE_PREFIX}aws_subnet.public[\"${AZ_B}\"]"

terraform state mv \
  "${MODULE_PREFIX}aws_subnet.private_a" \
  "${MODULE_PREFIX}aws_subnet.private[\"${AZ_A}\"]"

terraform state mv \
  "${MODULE_PREFIX}aws_subnet.private_b" \
  "${MODULE_PREFIX}aws_subnet.private[\"${AZ_B}\"]"

echo "==> Migrating route table association state..."

terraform state mv \
  "${MODULE_PREFIX}aws_route_table_association.public_a" \
  "${MODULE_PREFIX}aws_route_table_association.public[\"${AZ_A}\"]"

terraform state mv \
  "${MODULE_PREFIX}aws_route_table_association.public_b" \
  "${MODULE_PREFIX}aws_route_table_association.public[\"${AZ_B}\"]"

terraform state mv \
  "${MODULE_PREFIX}aws_route_table_association.private_a" \
  "${MODULE_PREFIX}aws_route_table_association.private[\"${AZ_A}\"]"

terraform state mv \
  "${MODULE_PREFIX}aws_route_table_association.private_b" \
  "${MODULE_PREFIX}aws_route_table_association.private[\"${AZ_B}\"]"

echo "==> Done. Run 'terraform plan' to verify no destructive changes."
