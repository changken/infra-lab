#==============================================================
# 學習目標：IAM 進階概念
#
# 回顧：前面每個 Lab 都用了 IAM，但都是最基本的 AssumeRole + 附加 Managed Policy。
# 本 Lab 深入四個在前面被省略的進階概念：
#
# ⭐ 概念 1：Condition 條件（aws:RequestedRegion）← TODO 1
#      讓 Allow 只在特定 Region 才生效
#      例：允許 EC2 操作，但只限 us-east-1
#
# ⭐ 概念 2：ABAC（Attribute-Based Access Control）← TODO 2
#      根據資源的 Tag 決定是否允許存取
#      例：只允許存取標有 Team=dev 的 S3 bucket
#      比起 ARN 清單，Tag-based 更靈活，不需要每次更新 policy
#
# ⭐ 概念 3：Explicit Deny（顯式拒絕）← TODO 3
#      Deny 永遠勝過 Allow（無論其他 policy 給了多少權限）
#      用來防止特權昇級（privilege escalation）
#
# ⭐ 概念 4：Permission Boundary（權限邊界）← TODO 4 + 5
#      設定 Role 的最大有效權限上限
#      即使 Role 附加了 AdminAccess，Boundary 決定實際可以做什麼
#      公式：有效權限 = (身份政策) ∩ (Permission Boundary)
#
# ⭐ 費用等級：🟢 安全（IAM 完全免費，S3 空 bucket 幾乎免費）
#==============================================================


#--------------------------------------------------------------
# Data Sources（已預填）
#--------------------------------------------------------------
data "aws_caller_identity" "current" {}


#--------------------------------------------------------------
# S3 Buckets（已預填）
# 兩個 bucket，Tag 不同，用來示範 ABAC 的效果
#--------------------------------------------------------------
resource "aws_s3_bucket" "dev" {
  bucket        = "${var.project}-dev-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = merge(local.common_tags, { Team = "dev" })
}

resource "aws_s3_bucket" "ops" {
  bucket        = "${var.project}-ops-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = merge(local.common_tags, { Team = "ops" })
}


#--------------------------------------------------------------
# Policy Attachments（已預填）
# TODO 1-3 的三個 policy 都附加到 developer role 上
#--------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "developer_ec2" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.allow_ec2_read_regional.arn
}

resource "aws_iam_role_policy_attachment" "developer_s3" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.allow_s3_tagged.arn
}

resource "aws_iam_role_policy_attachment" "developer_deny" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.deny_privilege_escalation.arn
}


#--------------------------------------------------------------
# TODO 1: IAM Policy — Region-Restricted EC2 Read（Condition）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
# Condition keys: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html
#
# ⭐ aws:RequestedRegion 是全域 condition key，可用於任何服務。
#    讓同一個 policy 在 us-east-1 允許，在其他 region 拒絕。
#
# 需要設定：
#   name        = "${var.project}-ec2-read-regional"
#   description = "Allow EC2 read-only in ${var.region} only"
#   tags        = local.common_tags
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Sid      = "AllowEC2ReadInRegion"
#       Effect   = "Allow"
#       Action   = ["ec2:Describe*"]
#       Resource = "*"
#       Condition = {
#         StringEquals = {
#           "aws:RequestedRegion" = var.region   # ← 全域 condition key
#         }
#       }
#     }]
#   })
#
# ⚠️ 沒有 Condition 的 Allow 對所有 region 都生效；加了 Condition 才限制 region

resource "aws_iam_policy" "allow_ec2_read_regional" {
  # TODO
  name        = "${var.project}-ec2-read-regional"
  description = "Allow EC2 read-only in ${var.region} only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowEC2ReadInRegion"
      Effect   = "Allow"
      Action   = ["ec2:Describe*"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.region
        }
      }
    }]
  })

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: IAM Policy — Tag-Based S3 Access（ABAC）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
# S3 condition keys: https://docs.aws.amazon.com/AmazonS3/latest/userguide/list_amazons3.html
#
# ⭐ ABAC（Attribute-Based Access Control）：
#    根據資源的 Tag 動態決定是否允許存取，比起維護 ARN 清單更靈活。
#    本 Lab 有兩個 bucket：Team=dev（允許）和 Team=ops（拒絕）
#
# 需要設定：
#   name        = "${var.project}-s3-tagged-access"
#   description = "Allow S3 access to buckets tagged with Team=dev only"
#   tags        = local.common_tags
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid      = "ListAllBuckets"
#         Effect   = "Allow"
#         Action   = ["s3:ListAllMyBuckets"]
#         Resource = "*"                  # ListAllMyBuckets 必須是 *
#       },
#       {
#         Sid    = "AllowTaggedBucketAccess"
#         Effect = "Allow"
#         Action = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
#         Resource = "*"
#         Condition = {
#           StringEquals = {
#             "aws:ResourceTag/Team" = "dev"   # ← 只允許 Team=dev 的資源
#           }
#         }
#       }
#     ]
#   })
#
# ⚠️ aws:ResourceTag/<key> 用於存取資源時的 tag 條件（與 aws:RequestTag 不同）
# ⚠️ aws:RequestTag 是「建立資源時必須帶的 tag」，這裡用 ResourceTag 是「存取已有資源」

resource "aws_iam_policy" "allow_s3_tagged" {
  # TODO
  name        = "${var.project}-s3-tagged-access"
  description = "Allow S3 access to buckets tagged with Team=dev only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListAllBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Sid      = "AllowTaggedBucketAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Team" = "dev"
          }
        }
      }
    ]
  })
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 3: IAM Policy — Explicit Deny（防止特權昇級）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
#
# ⭐ IAM 評估優先順序：Explicit Deny > Allow > Implicit Deny
#    只要有一個 Deny，無論其他 policy 給了多少 Allow，都無法執行。
#    這是防止「某人取得 Developer Role 後再建立新的 Admin Role」的標準做法。
#
# 需要設定：
#   name        = "${var.project}-deny-privilege-escalation"
#   description = "Deny IAM write actions to prevent privilege escalation"
#   tags        = local.common_tags
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Sid    = "DenyIAMWrite"
#       Effect = "Deny"         # ← Deny，不是 Allow！
#       Action = [
#         "iam:CreateRole",
#         "iam:DeleteRole",
#         "iam:AttachRolePolicy",
#         "iam:DetachRolePolicy",
#         "iam:PutRolePolicy",
#         "iam:CreatePolicy",
#         "iam:DeletePolicy",
#         "iam:CreateUser",
#         "iam:DeleteUser",
#         "iam:UpdateAssumeRolePolicy",
#       ]
#       Resource = "*"
#     }]
#   })
#
# ⚠️ Explicit Deny 沒有 Condition，對所有情況都生效

resource "aws_iam_policy" "deny_privilege_escalation" {
  # TODO
  name        = "${var.project}-deny-privilege-escalation"
  description = "Deny IAM write actions to prevent privilege escalation"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyIAMWrite"
      Effect = "Deny"
      Action = [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:UpdateAssumeRolePolicy",
      ]
      Resource = "*"
    }]
  })
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: IAM Policy — Permission Boundary（權限上限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
#
# ⭐ Permission Boundary 是 Role 的「最大權限天花板」。
#    即使 Role 附加了 AdministratorAccess，Boundary 也會限制實際有效權限。
#    有效權限 = (身份政策 Allow) ∩ (Permission Boundary Allow)
#
#    本 Boundary 定義：
#    - 最多只能讀 EC2（限 var.region）
#    - 最多只能讀 S3
#    - 禁止所有 IAM 操作（防止邊界被繞過）
#
# 需要設定：
#   name        = "${var.project}-developer-boundary"
#   description = "Permission boundary: max EC2/S3 read, no IAM"
#   tags        = local.common_tags
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid      = "BoundaryEC2Read"
#         Effect   = "Allow"
#         Action   = ["ec2:Describe*"]
#         Resource = "*"
#         Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
#       },
#       {
#         Sid      = "BoundaryS3Read"
#         Effect   = "Allow"
#         Action   = ["s3:Get*", "s3:List*"]
#         Resource = "*"
#       },
#       {
#         Sid      = "BoundaryDenyIAM"
#         Effect   = "Deny"
#         Action   = ["iam:*"]
#         Resource = "*"
#       }
#     ]
#   })
#
# ⚠️ Boundary 本身是普通 IAM Policy，但需要在 Role 上以 permissions_boundary 引用（TODO 5）

resource "aws_iam_policy" "permission_boundary" {
  # TODO
  name        = "${var.project}-developer-boundary"
  description = "Permission boundary: max EC2/S3 read, no IAM"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "BoundaryEC2Read"
        Effect    = "Allow"
        Action    = ["ec2:Describe*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
      },
      {
        Sid      = "BoundaryS3Read"
        Effect   = "Allow"
        Action   = ["s3:Get*", "s3:List*"]
        Resource = "*"
      },
      {
        Sid      = "BoundaryDenyIAM"
        Effect   = "Deny"
        Action   = ["iam:*"]
        Resource = "*"
      }
    ]
  })
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 5: IAM Role — Developer Role with Permission Boundary
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# ⭐ permissions_boundary 是 aws_iam_role 的特殊屬性，
#    設定後這個 Role 的有效權限永遠不超過 Boundary Policy。
#
# 需要設定：
#   name                 = "${var.project}-developer-role"
#   permissions_boundary = aws_iam_policy.permission_boundary.arn   # ← 這是關鍵屬性！
#   tags                 = local.common_tags
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Action    = "sts:AssumeRole"
#       Principal = {
#         AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
#       }
#     }]
#   })
#
# ⚠️ Principal 設為帳號 root（任何有 sts:AssumeRole 權限的 IAM entity 都能 assume）
# ⚠️ permissions_boundary 必須填 Policy ARN，不是 Policy Name

resource "aws_iam_role" "developer" {
  # TODO
  name                 = "${var.project}-developer-role"
  permissions_boundary = aws_iam_policy.permission_boundary.arn
  tags                 = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }]
  })
}
