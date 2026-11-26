# Lab 30: ElastiCache Redis + Lambda VPC 連線測試

> 在 VPC 內建立 ElastiCache Redis，並用 Lambda（也在 VPC 內）發送 Redis PING 驗證連線。完全不需要安裝 redis-py。

**費用等級**：🔴 危險（cache.t3.micro = **$0.017/hr**，apply 後立刻計費，練完當天 destroy）

---

## 學習目標

- 理解 ElastiCache 只能在 VPC 內存取（無公開端點）
- 掌握兩個 Security Group 互相引用的設計（Lambda SG ↔ Redis SG）
- 設定 Lambda 的 `vpc_config`，讓 Lambda 能連接 VPC 內的資源
- 理解 `AWSLambdaVPCAccessExecutionRole` 管理策略的用途（ENI 建立權限）
- 學會用 Redis RESP 協定裸 socket 測試連線（不需要外部套件）

---

## 架構

```
Default VPC
    │
    ├── Lambda（vpc_config）
    │       │ Security Group: lambda-sg
    │       │   egress: 6379 → redis-sg
    │       │
    │       └──(6379/tcp)──► ElastiCache Redis
    │                               │ Security Group: redis-sg
    │                               │   ingress: 6379 from lambda-sg
    │                               └── Subnet Group（default VPC subnets）
    │
    └── ⚠️ 無公開端點：外部無法直連 Redis
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_security_group` × 2 | Lambda SG（egress 6379）+ Redis SG（ingress 6379 from Lambda SG）|
| 2 | `aws_elasticache_subnet_group` | 指定 ElastiCache 可部署的子網路 |
| 3 | `aws_elasticache_cluster` | `engine = "redis"`、`num_cache_nodes = 1`、掛上 SG 和 subnet group |
| 4 | `aws_iam_role` + `aws_iam_role_policy_attachment` | `AWSLambdaVPCAccessExecutionRole`（VPC ENI 建立權限）|
| 5 | `aws_lambda_function` | `vpc_config` block + `REDIS_HOST` 環境變數 |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

> ⚠️ ElastiCache 建立約需 **5-10 分鐘**，這是正常的。Lambda 在 VPC 首次部署也需要 1-2 分鐘建立 ENI。

---

## 驗證

### 1. 觸發 Lambda 測試 Redis 連線

```bash
FUNC=$(terraform output -raw lambda_function_name)

aws lambda invoke \
  --function-name "$FUNC" \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json

cat response.json
```

**期望輸出：**
```json
{
  "statusCode": 200,
  "body": "{\"status\": \"success\", \"redis_host\": \"redis-lab-redis.xxxxx.cfg.use1.cache.amazonaws.com\", \"redis_port\": 6379, \"response\": \"+PONG\"}"
}
```

`+PONG` 代表 Redis 已回應，連線成功。

### 2. 確認 Redis 端點（VPC 內限定）

```bash
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)
echo "Redis endpoint: $REDIS_ENDPOINT"

# 嘗試從外部連線應該失敗（因為沒有公開端點）
# curl -v telnet://$REDIS_ENDPOINT:6379  # 這會 timeout，正確行為
```

### 3. 確認 Security Group 設定

```bash
# 查看 Lambda SG 的 egress 規則
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=redis-lab-lambda-sg" \
  --query 'SecurityGroups[0].IpPermissionsEgress'

# 查看 Redis SG 的 ingress 規則
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=redis-lab-redis-sg" \
  --query 'SecurityGroups[0].IpPermissions'
```

### 4. 查看 Lambda 執行日誌

```bash
LOG_GROUP="/aws/lambda/$FUNC"
aws logs tail "$LOG_GROUP" --since 5m
```

---

## 結束

```bash
terraform destroy -auto-approve
```

> **請務必確認 destroy 成功**，執行後確認 ElastiCache cluster 已消失：
> ```bash
> aws elasticache describe-cache-clusters --query 'CacheClusters[*].{ID:CacheClusterId,Status:CacheClusterStatus}'
> ```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| ElastiCache cache.t3.micro | **$0.017/hr**（不在 Free Tier！）|
| Lambda（測試幾次）| ~$0 |
| 資料傳輸（VPC 內）| $0 |
| **合計（apply → destroy 約 1 小時）** | **~$0.02** |

---

## 核心概念釐清

### ElastiCache 和 RDS 的存取方式差異

| | ElastiCache | RDS |
|--|---|---|
| 公開端點 | ❌ 永遠在 VPC 內 | ✅ 可選 `publicly_accessible = true` |
| Free Tier | ❌ 無 | ✅ db.t3.micro 750hr/月 |
| 連線方式 | 必須在同 VPC（EC2/Lambda/ECS）| 可從外部連（若公開）|

### aws_elasticache_cluster vs aws_elasticache_replication_group

```hcl
# 單節點（本 lab，最便宜）
resource "aws_elasticache_cluster" "redis" {
  engine          = "redis"
  num_cache_nodes = 1  # Redis 這個 resource 只能是 1
  ...
  # endpoint: aws_elasticache_cluster.redis.cache_nodes[0].address
}

# Primary + Replica（生產環境，自動 Failover）
resource "aws_elasticache_replication_group" "redis" {
  num_cache_clusters         = 2  # 1 primary + 1 replica
  automatic_failover_enabled = true
  ...
  # endpoint: aws_elasticache_replication_group.redis.primary_endpoint_address
}
```

### Lambda 在 VPC 的限制（面試常考）

```
Lambda 在 VPC 內 → 可以連 ElastiCache / RDS / 私有資源
                 → 預設無法連外部網際網路

如果 Lambda 需要同時連 VPC 資源 AND 外部 API：
  方案 A：VPC Endpoint（S3/DynamoDB 等 AWS 服務免費）
  方案 B：NAT Gateway（$0.045/hr，貴但通用）

本 lab 只需連 ElastiCache（同 VPC），不需要 NAT Gateway。
```

### Redis RESP 協定（為何 socket 測試可行）

```
Redis 使用純文字的 RESP（Redis Serialization Protocol）：

PING 指令的 RESP 格式：
  *1\r\n     ← 有 1 個參數
  $4\r\n     ← 第一個參數長度為 4 bytes
  PING\r\n   ← 參數內容

Redis 回應：
  +PONG\r\n  ← 簡單字串回應（+ 開頭）
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Lambda 回傳 `Timeout connecting` | Security Group 的 egress/ingress 設定錯誤，或 Lambda/Redis 不在同一 VPC |
| Lambda 建立很慢（5+ 分鐘）| 正常，VPC Lambda 首次建立 ENI 需要時間 |
| ElastiCache apply 卡住（10+ 分鐘）| 正常，ElastiCache 啟動本來就慢；若超過 20 分鐘才異常 |
| `InvalidSubnet` | Subnet Group 的 subnet_ids 必須在同一 VPC 且至少 2 個不同 AZ |
| `destroy` 後 ElastiCache 還在 | 狀態可能是 `deleting`，等幾分鐘再確認 |
| `ENI limit exceeded` | 帳號 ENI 數量達上限，先清理其他 VPC Lambda |
