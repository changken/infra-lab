#==============================================================
# 學習目標：ElastiCache Redis + VPC 內部連線 + Lambda 測試
#
# 核心問題：ElastiCache 只能在 VPC 內存取，Lambda 怎麼連進去？
#
# ElastiCache 的重要限制：
#   ❌ 沒有公開端點（不像 RDS 有 publicly_accessible）
#   ❌ 不在 Free Tier（cache.t3.micro = $0.017/hr）
#   ✅ 必須在 VPC 內，透過 Security Group 控制存取
#
# Lambda 連 ElastiCache 的前提：
#   Lambda 必須部署在同一個 VPC（設定 vpc_config）
#   Lambda 需要能建立 ENI（需要 ec2:CreateNetworkInterface 等權限）
#   → 最簡單的做法：attach AWSLambdaVPCAccessExecutionRole 管理策略
#
# 測試策略（不需要 redis-py）：
#   用 Python 內建的 socket 模組直接送 Redis RESP 協定的 PING 指令：
#   → 送出：*1\r\n$4\r\nPING\r\n
#   → 期望回應：+PONG\r\n
#   這樣不需要安裝任何外部套件，Lambda 部署更簡單。
#
# ElastiCache Cluster Mode：
#   Cluster Mode OFF（本 lab）→ 單節點或 Primary+Replica，資料不分片
#   Cluster Mode ON          → 資料分片到多個 Shard，支援水平擴展
#   → 用 aws_elasticache_cluster (單節點) 或 aws_elasticache_replication_group
#
# ⚠️ 費用警示：
#   apply 後立刻開始計費（$0.017/hr for cache.t3.micro）
#   練完立刻 terraform destroy！
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：取得預設 VPC 和子網路
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 已完成：打包 Lambda 原始碼
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/src/handler.zip"
}


#--------------------------------------------------------------
# TODO 1: Security Groups（Lambda SG + Redis SG）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# 需要兩個 SG，並用獨立 aws_security_group_rule 建立互相引用的規則：
#
# [Lambda SG]
#   name        = "${var.project}-lambda-sg"
#   description = "Lambda outbound to Redis"
#   vpc_id      = data.aws_vpc.default.id
#   tags        = local.common_tags
#
#   # Lambda 不需要 inline ingress/egress，規則會拆到 aws_security_group_rule
#
# [Redis SG]
#   name        = "${var.project}-redis-sg"
#   description = "Redis inbound from Lambda"
#   vpc_id      = data.aws_vpc.default.id
#   tags        = local.common_tags
#
#   # Redis 不需要 inline ingress/egress，規則會拆到 aws_security_group_rule
#
# ⚠️ 注意：兩個 SG 若使用 inline ingress/egress 互相引用，會造成 cycle。
#    請使用 aws_security_group_rule 拆開，讓 Terraform 先建立 SG，再建立規則。

resource "aws_security_group" "lambda" {
  # TODO
  name        = "${var.project}-lambda-sg"
  description = "Lambda outbound to Redis"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.common_tags
}

resource "aws_security_group" "redis" {
  # TODO
  name        = "${var.project}-redis-sg"
  description = "Redis inbound from Lambda"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.common_tags
}

resource "aws_security_group_rule" "lambda_to_redis" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda.id
  source_security_group_id = aws_security_group.redis.id
}

resource "aws_security_group_rule" "redis_from_lambda" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = aws_security_group.lambda.id
}


#--------------------------------------------------------------
# TODO 2: ElastiCache Subnet Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group
#
# ElastiCache 需要一個 Subnet Group，指定它可以部署到哪些子網路。
# 類似 RDS 的 DB Subnet Group。
#
#   name       = "${var.project}-redis-subnet-group"
#   subnet_ids = data.aws_subnets.default.ids
#   # ← 使用預設 VPC 的所有子網路
#   tags       = local.common_tags

resource "aws_elasticache_subnet_group" "redis" {
  # TODO
  name       = "${var.project}-redis-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  tags       = local.common_tags
}

#--------------------------------------------------------------
# TODO 3: ElastiCache Redis Cluster（單節點）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_cluster
#
# ⚠️ 費用警示：apply 後立即開始計費！
#
#   cluster_id           = "${var.project}-redis"
#   engine               = "redis"
#   node_type            = var.redis_node_type   # "cache.t3.micro" = $0.017/hr
#   num_cache_nodes      = 1
#   # ← Redis 用 aws_elasticache_cluster 時 num_cache_nodes 只能是 1
#   #   如果要 Primary+Replica，要改用 aws_elasticache_replication_group
#
#   parameter_group_name = "default.redis7"
#   engine_version       = "7.1"
#   port                 = 6379
#
#   subnet_group_name    = aws_elasticache_subnet_group.redis.name
#   security_group_ids   = [aws_security_group.redis.id]
#   tags                 = local.common_tags
#
# 補充：生產環境建議改用 aws_elasticache_replication_group：
#   num_cache_clusters = 2  → 1 Primary + 1 Replica，支援自動 Failover

resource "aws_elasticache_cluster" "redis" {
  # TODO
  cluster_id           = "${var.project}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
  tags                 = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: Lambda IAM Role（含 VPC 存取權限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# Lambda 在 VPC 內執行需要建立 ENI（Elastic Network Interface）。
# 最簡單的做法是 attach AWS 管理的 AWSLambdaVPCAccessExecutionRole。
#
# [IAM Role]
#   name = "${var.project}-lambda-role"
#   tags = local.common_tags
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
# [附加 AWS 管理策略：CloudWatch Logs + VPC ENI 建立]
# resource "aws_iam_role_policy_attachment" "lambda_vpc" {
#   role       = aws_iam_role.lambda.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
#   # ← 這個 managed policy 包含：
#   #   logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
#   #   ec2:CreateNetworkInterface, ec2:DescribeNetworkInterfaces,
#   #   ec2:DeleteNetworkInterface 等 VPC 相關權限
# }

resource "aws_iam_role" "lambda" {
  # TODO
  name = "${var.project}-lambda-role"
  tags = local.common_tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  # TODO
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


#--------------------------------------------------------------
# TODO 5: Lambda Function（VPC 內執行，測試 Redis 連線）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
#   function_name = "${var.project}-redis-test"
#   runtime       = "python3.12"
#   handler       = "handler.handler"
#   role          = aws_iam_role.lambda.arn
#   filename      = data.archive_file.lambda.output_path
#   source_code_hash = data.archive_file.lambda.output_base64sha256
#   timeout       = 10
#   tags          = local.common_tags
#
#   environment {
#     variables = {
#       REDIS_HOST = aws_elasticache_cluster.redis.cache_nodes[0].address
#       # ← cache_nodes[0].address 取第一個（也是唯一一個）節點的 hostname
#       REDIS_PORT = "6379"
#     }
#   }
#
#   # Lambda 在 VPC 內執行的必要設定
#   vpc_config {
#     subnet_ids         = data.aws_subnets.default.ids
#     security_group_ids = [aws_security_group.lambda.id]
#   }

resource "aws_lambda_function" "redis_test" {
  # TODO
  function_name    = "${var.project}-redis-test"
  runtime          = "python3.12"
  handler          = "handler.handler"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10
  tags             = local.common_tags

  environment {
    variables = {
      REDIS_HOST = aws_elasticache_cluster.redis.cache_nodes[0].address
      REDIS_PORT = "6379"
    }
  }

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda.id]
  }
}
