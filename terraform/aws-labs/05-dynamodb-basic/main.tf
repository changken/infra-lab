#==============================================================
# 學習目標：建立 DynamoDB Table，理解 NoSQL 的設計思維
#
# 資料模型（模擬電商訂單）：
#
#   Table: orders
#   ┌──────────────────────────────────────────────────────┐
#   │  PK: user_id (String)  │  SK: order_id (String)     │
#   ├──────────────────────────────────────────────────────┤
#   │  status     (String)  ← GSI PK                      │
#   │  created_at (String)  ← GSI SK                      │
#   │  amount     (Number)                                 │
#   │  expires_at (Number)  ← TTL attribute                │
#   └──────────────────────────────────────────────────────┘
#
#   GSI: status-created_at-index
#   → 讓你查「所有 PENDING 訂單，依時間排序」
#
# DynamoDB vs SQL 觀念對照：
#   Partition Key  ≈  決定資料存在哪台機器（hash）
#   Sort Key       ≈  同一個 PK 下的「排序欄位」，可 range query
#   GSI            ≈  另建一個「以不同欄位為 PK」的虛擬索引
#   TTL            ≈  自動 delete 過期資料（非同步，有幾分鐘延遲）
#
# 完成順序：1 → 2
#==============================================================


#--------------------------------------------------------------
# TODO 1: DynamoDB Table
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table
#
# 需要設定的屬性（每個都有學習重點，仔細看）：
#
# ── 基本 ──
#   name         → var.table_name
#   billing_mode → "PAY_PER_REQUEST"（按量付費，練習用最安全）
#
# ── Keys（只定義「被索引用到的欄位」，其他欄位 DynamoDB 不管） ──
#   hash_key  → local.pk_name   （Partition Key）
#   range_key → local.sk_name   （Sort Key，可選但強烈建議設）
#
# ── attribute 區塊（每個被 PK/SK/GSI 用到的欄位都要宣告） ──
#   attribute { name = local.pk_name    type = "S" }   # S = String
#   attribute { name = local.sk_name    type = "S" }
#   attribute { name = local.gsi_pk_name type = "S" }
#   attribute { name = local.gsi_sk_name type = "S" }
#   # ⚠️ amount 不用宣告，它不是任何索引的 key
#
# ── GSI（Global Secondary Index） ──
#   global_secondary_index {
#     name            = "status-created_at-index"
#     hash_key        = local.gsi_pk_name
#     range_key       = local.gsi_sk_name
#     projection_type = "ALL"   # ALL = 把所有欄位都複製到索引
#   }
#
# ── TTL ──
#   ttl {
#     attribute_name = local.ttl_attr
#     enabled        = var.ttl_enabled
#   }
#
# ── tags ──
#   tags = merge(local.common_tags, { Name = var.table_name })

resource "aws_dynamodb_table" "orders" {
  # TODO
  name = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key = local.pk_name
  range_key = local.sk_name
  attribute {
    name = local.pk_name
    type = "S"
  }
  attribute {
    name = local.sk_name
    type = "S"
  }
  attribute {
    name = local.gsi_pk_name
    type = "S"
  }
  attribute{
    name = local.gsi_sk_name
    type = "S"
  }
  global_secondary_index {
    name = "status-created_at-index"
    hash_key = local.gsi_pk_name
    range_key = local.gsi_sk_name
    projection_type = "ALL"
  }
  ttl{
    attribute_name = local.ttl_attr
    enabled = var.ttl_enabled
  }
  tags = merge(local.common_tags, { Name = var.table_name })
}


#--------------------------------------------------------------
# TODO 2: 塞測試資料（3 筆訂單）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item
#
# 每個 item 需要設定：
#   - table_name → aws_dynamodb_table.orders.name
#   - hash_key   → aws_dynamodb_table.orders.hash_key
#   - range_key  → aws_dynamodb_table.orders.range_key
#   - item       → JSON 字串，描述一筆資料（格式見下）
#
# DynamoDB item 的 JSON 格式：
#   每個欄位要宣告「型別」，不能只給值：
#   {
#     "user_id":    { "S": "user-001" },        # S = String
#     "order_id":   { "S": "order-abc123" },
#     "status":     { "S": "PENDING" },
#     "created_at": { "S": "2025-01-15T10:00:00Z" },
#     "amount":     { "N": "299" },              # N = Number（但要用字串表示）
#     "expires_at": { "N": "9999999999" }        # TTL，Unix timestamp
#   }
#
# 你要建立 3 筆，建議用 for_each + map：
#
#   resource "aws_dynamodb_table_item" "sample" {
#     for_each = {
#       "order-1" = { user = "user-001", status = "PENDING",   amount = "299" }
#       "order-2" = { user = "user-001", status = "COMPLETED", amount = "599" }
#       "order-3" = { user = "user-002", status = "PENDING",   amount = "149" }
#     }
#     table_name = aws_dynamodb_table.orders.name
#     hash_key   = aws_dynamodb_table.orders.hash_key
#     range_key  = aws_dynamodb_table.orders.range_key
#     item = jsonencode({
#       "user_id"    = { "S" = each.value.user }
#       "order_id"   = { "S" = each.key }
#       "status"     = { "S" = each.value.status }
#       "created_at" = { "S" = "2025-01-15T10:00:00Z" }
#       "amount"     = { "N" = each.value.amount }
#       "expires_at" = { "N" = "9999999999" }
#     })
#   }
#
# 提示：`for_each` 的 key 就是 order_id（SK），直接用 `each.key`

resource "aws_dynamodb_table_item" "sample" {
  # TODO
  for_each = {
    "order-1" = {user = "user-001", status = "PENDING", amount = "299"}
    "order-2" = {user = "user-001", status = "COMPLETED", amount = "599"}
    "order-3" = {user = "user-002", status = "PENDING", amount = "149"}
  }
  table_name = aws_dynamodb_table.orders.name
  hash_key = aws_dynamodb_table.orders.hash_key
  range_key = aws_dynamodb_table.orders.range_key
  item = jsonencode({
    "user_id" = { "S" = each.value.user }
    "order_id" = { "S" = each.key }
    "status" = { "S" = each.value.status }
    "created_at" = { "S" = "2026-05-20T17:10:00Z" }
    "amount" = { "N" = each.value.amount }
    "expires_at" = { "N" = "9999999999" }
  })
}
