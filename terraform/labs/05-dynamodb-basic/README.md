# Lab 05: DynamoDB Basic

建立 DynamoDB Table，理解 NoSQL 和 SQL 的設計差異。
**幾乎免費**，按量模式下空 table 幾乎 $0。

## 學習目標

- Partition Key + Sort Key 的設計思維（vs SQL Primary Key）
- Global Secondary Index（GSI）：讓非 PK 欄位也能查詢
- TTL：自動過期資料
- `aws_dynamodb_table_item`：用 Terraform 塞測試資料
- DynamoDB item 的特殊 JSON 格式（每個欄位要帶型別）

## 資料模型

模擬電商訂單：

```
Table: orders
┌──────────────────────────────────────────────────────┐
│  PK: user_id (String)  │  SK: order_id (String)     │
├──────────────────────────────────────────────────────┤
│  status     (String)  ← GSI Partition Key            │
│  created_at (String)  ← GSI Sort Key                 │
│  amount     (Number)                                 │
│  expires_at (Number)  ← TTL attribute                │
└──────────────────────────────────────────────────────┘

查詢方式：
  主表：user_id + order_id → 查特定用戶的特定訂單
  GSI： status + created_at → 查所有 PENDING 訂單，依時間排序
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_dynamodb_table` | Table + attribute 宣告 + GSI + TTL |
| 2 | `aws_dynamodb_table_item` | for_each 塞 3 筆資料（注意 JSON 格式）|

再補完 `outputs.tf` 的 2 個 TODO。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan    # 應該顯示 5 個 to add（1 table + 3 items + 1 random... 等等，其實是 4）
terraform apply
```

**預期 plan 數字：4 個 to add**（1 table + 3 items）

### 驗證

```bash
terraform output
```

然後去 AWS Console → DynamoDB → Tables → `orders` → Explore items，
應該看到 3 筆資料。試著切到 GSI tab，觀察資料怎麼被索引。

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

**< $0.01**。PAY_PER_REQUEST 模式下，3 筆資料 + 沒有查詢 = 幾乎 $0。

## DynamoDB vs SQL 速查

| SQL 概念 | DynamoDB 概念 |
|----------|---------------|
| Table | Table |
| Primary Key | Partition Key + Sort Key |
| Index | GSI / LSI |
| Column type | attribute type (S/N/B) |
| Row | Item |
| NULL column | 不存在（DynamoDB 沒有 schema） |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `attribute 'xxx' not defined` | 有個欄位被 GSI 用到，但沒在 `attribute` block 宣告 |
| `item` JSON 格式錯 | 忘了帶型別（要 `{"S": "value"}` 不是直接 `"value"`）|
| `for_each` 報錯 | map 的 value 型別不一致，確認每個 field 都是 string |
| apply 成功但 Console 看不到資料 | 重新整理，DynamoDB Console 有時需要幾秒 |

## 進階挑戰（選做）

- 把 `billing_mode` 改成 `PROVISIONED`，加上 `read_capacity = 5` 和 `write_capacity = 5`，觀察 plan 變化
- 改一筆 item 的 `amount`，`apply` 後觀察 plan 怎麼描述這個變更
- 把 `ttl_enabled` 改成 `false`，觀察 Terraform 怎麼處理 TTL 的 update
