locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Lab         = "05-dynamodb-basic"
  }

  # 欄位名稱定義在這裡，方便 table 和 GSI 共用，不用硬寫字串
  pk_name      = "user_id"   # Partition Key
  sk_name      = "order_id"  # Sort Key
  gsi_pk_name  = "status"    # GSI 的 Partition Key
  gsi_sk_name  = "created_at"
  ttl_attr     = "expires_at"
}
