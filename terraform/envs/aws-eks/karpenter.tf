#==============================================================
# Karpenter — 自動節點佈建
#
# 架構：
#   Pending Pod
#     └── Karpenter Controller 偵測（無法排程）
#           └── EC2 API → 選最佳機型啟動 Node
#                 └── Node 加入 cluster → Pod 排程成功
#
# 與 Managed Node Group 的差異：
#   MNG：預先定好機型 + 數量 → Cluster Autoscaler 調整副本數
#   Karpenter：按需選最適機型 → bin-packing → 省 40-60% 費用
#
# Terraform 負責（基礎設施層）：
#   1. Karpenter Node IAM Role（與 Managed Node Group 分開）
#   2. Controller IRSA Role（讓 Karpenter Pod 呼叫 EC2/SQS API）
#   3. SQS Interruption Queue（接收 SPOT 中斷通知，優雅驅逐 Pod）
#   4. EventBridge Rules → SQS（4 種 AWS 系統事件）
#   5. EKS Access Entry（讓 Karpenter 啟動的 Node 能加入 cluster）
#
# Helm + K8s 設定（apply 後手動，見 docs/karpenter-demo.md）：
#   - helm install karpenter
#   - kubectl apply EC2NodeClass + NodePool
#==============================================================

# ── 1. Karpenter Node IAM Role ───────────────────────────────
# Karpenter 啟動的 EC2 用此 role（獨立於 Managed Node Group 的 node role）
# 這樣兩種 node 的權限可以分開管理

resource "aws_iam_role" "karpenter_node" {
  name = "${local.name_prefix}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── 2. Karpenter Controller IRSA Role ────────────────────────

resource "aws_iam_role" "karpenter" {
  name = "${local.name_prefix}-karpenter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          # Karpenter 安裝在 karpenter namespace，SA 名稱為 karpenter
          "${local.oidc_issuer}:sub" = "system:serviceaccount:karpenter:karpenter"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "karpenter" {
  name        = "${local.name_prefix}-karpenter-policy"
  description = "Karpenter controller: EC2 node lifecycle + SQS interruption + EKS discovery"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── EC2: 讀取（Describe 不需要資源條件）
      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Resource = "*"
      },
      # ── EC2: 啟動所需的靜態資源（AMI、SG、Subnet 等）
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
        ]
        Resource = [
          "arn:aws:ec2:*::image/*",
          "arn:aws:ec2:*::snapshot/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:key-pair/*",
          "arn:aws:ec2:*:*:volume/*",
        ]
      },
      # ── EC2: 新建 launch-template（RequestTag：建立時才設的 tag）
      {
        Sid      = "AllowCreateLaunchTemplate"
        Effect   = "Allow"
        Action   = ["ec2:CreateLaunchTemplate"]
        Resource = ["arn:aws:ec2:*:*:launch-template/*"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      # ── EC2: RunInstances / CreateFleet 使用已存在的 launch-template
      # launch-template 是既有資源，需用 ResourceTag（而非 RequestTag）驗證
      {
        Sid    = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
        ]
        Resource = ["arn:aws:ec2:*:*:launch-template/*"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      # ── EC2: 建立新的 fleet / instance / volume 等資源（RequestTag）
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
        ]
        Resource = [
          "arn:aws:ec2:*:*:fleet/*",
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      # ── EC2: 建立資源時打 tag（RequestTag：RunInstances / CreateFleet 同時設的 tag）
      {
        Sid    = "AllowScopedResourceTagging"
        Effect = "Allow"
        Action = ["ec2:CreateTags"]
        Resource = [
          "arn:aws:ec2:*:*:fleet/*",
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      # ── EC2: 對已存在的 Karpenter 資源打 tag（ResourceTag：資源已有 cluster tag）
      # Karpenter 啟動 instance 後會再發一次 CreateTags，用 ResourceTag 驗證既有資源
      {
        Sid    = "AllowTaggingKarpenterOwnedResources"
        Effect = "Allow"
        Action = ["ec2:CreateTags"]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
        }
      },
      # ── EC2: 刪除（只能刪有 cluster + nodepool tag 的資源）
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
        ]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:launch-template/*",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      # ── IAM: PassRole（把 Node IAM Role 傳給 EC2，讓 Node 能認識自己的身份）
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.karpenter_node.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" }
        }
      },
      # ── IAM: Instance Profile（Karpenter v1.x 在 managed access mode 自行管理 profile）
      # v1.x 命名格式：{cluster_name}_{hash}，不再用 KarpenterNodeInstanceProfile- 前綴
      {
        Sid    = "AllowInstanceProfileActions"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
        ]
        Resource = "arn:aws:iam::*:instance-profile/*"
      },
      # ── EKS: DescribeCluster（讀 endpoint + CA，產生 node bootstrap config）
      {
        Sid      = "AllowEKSAccess"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.main.arn
      },
      # ── SSM: GetParameter（查 AL2023 / Bottlerocket 最新 AMI ID）
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:*::parameter/aws/service/*"
      },
      # ── Pricing: GetProducts（計算 bin-packing 時比較各機型價格）
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      # ── SQS: 消費中斷事件（Karpenter 讀到後優雅 cordon + drain Node）
      {
        Sid    = "AllowInterruptionQueueActions"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

# ── 3. SQS Interruption Queue ────────────────────────────────
# SPOT 中斷前 AWS 會發送 warning；Karpenter 收到後優雅驅逐 Pod（cordon → drain）
# 目標：Pod 在 Node 消失前就搬到其他 Node，避免 502 / 服務中斷
#
# TODO: 調整 message_retention_seconds
#   提示：EC2 Spot Instance Interruption Warning 提前幾分鐘發送？
#         設定略大於警告窗口即可（太大沒意義，Karpenter 收到就會處理）
#   參考：https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html

resource "aws_sqs_queue" "karpenter_interruption" {
  name = "${local.name_prefix}-karpenter-interruption"

  # TODO: 根據 SPOT 警告窗口調整此值
  message_retention_seconds = 300

  tags = local.common_tags
}

# SQS Resource Policy：允許 EventBridge 推送訊息到此 queue
resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:events:${var.region}:${data.aws_caller_identity.current.account_id}:rule/*"
        }
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# ── 4. EventBridge → SQS（4 種 AWS 事件）────────────────────
# Karpenter 透過訂閱這些事件，提早知道「某個 Node 即將消失」
# 讓它有時間優雅驅逐 Pod，而不是等 Node 突然斷線
#
# 事件種類：
#   a. EC2 Spot Instance Interruption Warning（最常見，SPOT 回收）
#   b. EC2 Instance Rebalance Recommendation（AWS 建議主動換 SPOT）
#   c. EC2 Instance State-change Notification（instance 狀態變化）
#   d. AWS Health Event（排程維護，如硬體退役）

# a. SPOT 中斷（提前 2 分鐘通知）
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name        = "${local.name_prefix}-karpenter-spot-interruption"
  description = "Karpenter: EC2 Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# b. Rebalance Recommendation（AWS 暗示 SPOT 快被收回，建議主動換）
resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name        = "${local.name_prefix}-karpenter-rebalance"
  description = "Karpenter: EC2 Instance Rebalance Recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule = aws_cloudwatch_event_rule.karpenter_rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# c. Instance State-change（running → shutting-down 等狀態轉換）
resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  name        = "${local.name_prefix}-karpenter-instance-state"
  description = "Karpenter: EC2 Instance State-change Notification"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_state.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# d. AWS Health Event（排程維護、硬體退役等系統級事件）
#
# TODO: 查詢 AWS Health EventBridge 格式，補完 event_pattern
#   提示：source 不再是 "aws.ec2"
#         可以加 detail.service filter 只收 EC2 相關 health event
#   參考：https://docs.aws.amazon.com/health/latest/ug/cloudwatch-events-health.html

resource "aws_cloudwatch_event_rule" "karpenter_health" {
  name        = "${local.name_prefix}-karpenter-health"
  description = "Karpenter: AWS Health Event"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
    # TODO: 可選擇加上 detail.service = ["EC2"] 過濾非 EC2 事件
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "karpenter_health" {
  rule = aws_cloudwatch_event_rule.karpenter_health.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# ── 5. EKS Access Entry for Karpenter Nodes ─────────────────
# Karpenter 啟動的 Node 使用 karpenter_node role；
# 透過 Access Entry（type = EC2_LINUX）讓這個 role 能加入 cluster
# 注意：Managed Node Group 使用的是另一個 role（aws_iam_role.node）

resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"

  tags = local.common_tags
}
