#==============================================================
# Poor Man's RAG — S3 Knowledge Base
#
# 做法：
#   1. S3 bucket 存放 .txt 知識文件
#   2. /rag endpoint 先 ListObjects + GetObject 抓所有文件
#   3. 塞進 Bedrock Converse 的 system prompt
#   4. 回傳 answer + sources（哪些文件被用到）
#
# 費用：S3 幾乎免費（< $0.01/月）
#==============================================================

resource "aws_s3_bucket" "rag_knowledge" {
  bucket = "${local.name_prefix}-rag-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "rag_knowledge" {
  bucket                  = aws_s3_bucket.rag_knowledge.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── IAM：讓 custom-app IRSA Role 可以讀取知識庫 ──────────────

resource "aws_iam_role_policy" "custom_app_s3_rag" {
  name = "${local.name_prefix}-custom-app-s3-rag"
  role = aws_iam_role.custom_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.rag_knowledge.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.rag_knowledge.arn}/knowledge/*"
      }
    ]
  })
}

# ── 預載知識文件（terraform apply 後自動上傳）────────────────

resource "aws_s3_object" "infra_lab_overview" {
  bucket  = aws_s3_bucket.rag_knowledge.id
  key     = "knowledge/infra-lab-overview.txt"
  content = <<-EOT
    Infra Lab - AWS EKS Learning Environment

    This is an infrastructure learning lab running on AWS EKS (Elastic Kubernetes Service).
    The cluster name is infra-lab-dev-eks running Kubernetes 1.36 in us-east-1.

    Key components:
    - EKS cluster: 2x t3.medium SPOT nodes in private subnets, behind NAT Gateway
    - AWS Load Balancer Controller: manages ALB Ingress resources
    - ArgoCD: GitOps controller, watches GitHub repo and auto-syncs manifests
    - ECR: container registry for custom-app images (v3 through v7)
    - IRSA: IAM Roles for Service Accounts, pod-level AWS permissions without hardcoded keys

    Applications running in the cluster:
    - custom-app (namespace: custom-app): Go HTTP service, demonstrates IRSA + Bedrock + RAG
    - podinfo (namespace: podinfo): reference microservice for traffic testing
    - ArgoCD (namespace: argocd): GitOps controller
    - kube-prometheus-stack (namespace: monitoring): Prometheus + Grafana observability

    Cost when running: approximately $5/day
    - EKS control plane: $0.10/hr ($2.40/day)
    - NAT Gateway: $0.045/hr ($1.08/day)
    - 2x t3.medium SPOT: ~$0.03/hr ($0.67/day)
    - ALBs: ~$0.03/hr ($0.77/day)

    To save cost: scale node group to 0 when not in use.
    To fully clean up: terraform destroy in terraform/envs/aws-eks/
  EOT
  etag    = md5(<<-EOT
    Infra Lab - AWS EKS Learning Environment

    This is an infrastructure learning lab running on AWS EKS (Elastic Kubernetes Service).
    The cluster name is infra-lab-dev-eks running Kubernetes 1.36 in us-east-1.

    Key components:
    - EKS cluster: 2x t3.medium SPOT nodes in private subnets, behind NAT Gateway
    - AWS Load Balancer Controller: manages ALB Ingress resources
    - ArgoCD: GitOps controller, watches GitHub repo and auto-syncs manifests
    - ECR: container registry for custom-app images (v3 through v7)
    - IRSA: IAM Roles for Service Accounts, pod-level AWS permissions without hardcoded keys

    Applications running in the cluster:
    - custom-app (namespace: custom-app): Go HTTP service, demonstrates IRSA + Bedrock + RAG
    - podinfo (namespace: podinfo): reference microservice for traffic testing
    - ArgoCD (namespace: argocd): GitOps controller
    - kube-prometheus-stack (namespace: monitoring): Prometheus + Grafana observability

    Cost when running: approximately $5/day
    - EKS control plane: $0.10/hr ($2.40/day)
    - NAT Gateway: $0.045/hr ($1.08/day)
    - 2x t3.medium SPOT: ~$0.03/hr ($0.67/day)
    - ALBs: ~$0.03/hr ($0.77/day)

    To save cost: scale node group to 0 when not in use.
    To fully clean up: terraform destroy in terraform/envs/aws-eks/
  EOT
  )
}

resource "aws_s3_object" "irsa_guide" {
  bucket  = aws_s3_bucket.rag_knowledge.id
  key     = "knowledge/irsa-guide.txt"
  content = <<-EOT
    IRSA (IAM Roles for Service Accounts) Quick Reference

    IRSA lets Kubernetes pods assume AWS IAM roles without any hardcoded credentials.

    How it works (trust chain):
    1. EKS creates an OIDC provider (one per cluster)
    2. A Kubernetes ServiceAccount is annotated with an IAM Role ARN
    3. When a pod starts, EKS mutating webhook injects a projected volume with a short-lived OIDC token
       (mounted at /var/run/secrets/eks.amazonaws.com/serviceaccount/token)
    4. The AWS SDK credential chain automatically finds this token
    5. SDK calls STS AssumeRoleWithWebIdentity to exchange the token for temporary credentials
    6. Pod uses these credentials to call AWS APIs

    IAM Role trust policy requirements:
    - Principal: the EKS OIDC provider ARN
    - Condition StringEquals on two keys:
      - <oidc-issuer>:aud = "sts.amazonaws.com"
      - <oidc-issuer>:sub = "system:serviceaccount:<namespace>:<serviceaccount-name>"

    The sub condition locks the role to a specific namespace + serviceaccount combination.
    Other pods cannot assume this role even if they are in the same cluster.

    Advantages over hardcoded Access Keys:
    - No long-lived credentials to rotate or accidentally commit to Git
    - Temporary credentials auto-rotate every hour
    - Minimum privilege at pod level, not node level
    - CloudTrail shows the full pod identity, not just an opaque key ID

    In this lab:
    - Role ARN: arn:aws:iam::661515655645:role/infra-lab-dev-custom-app-role
    - ServiceAccount: custom-app in namespace custom-app
    - Policies: s3:ListAllMyBuckets, bedrock:Converse, s3:GetObject on knowledge bucket
  EOT
  etag = md5("irsa-guide-v1")
}

resource "aws_s3_object" "bedrock_models" {
  bucket  = aws_s3_bucket.rag_knowledge.id
  key     = "knowledge/bedrock-models.txt"
  content = <<-EOT
    Bedrock Models Available in This Lab

    All models use cross-region inference profiles (us.* prefix).
    This routes requests across us-east-1, us-east-2, and us-west-2 for on-demand throughput.
    Direct foundation-model invocation is not used because some models (DeepSeek, Llama 4)
    do not support on-demand throughput without provisioned capacity.

    Model aliases:
    - nova     → us.amazon.nova-lite-v1:0
                 Amazon's own model. Fast and cost-effective. Good for Q&A and summarization.

    - llama    → us.meta.llama3-1-8b-instruct-v1:0
                 Meta's open-source model. 8B parameters, efficient for instruction following.

    - deepseek → us.deepseek.r1-v1:0
                 Reasoning-focused model. Uses chain-of-thought. Good for complex analysis.

    - llama4   → us.meta.llama4-scout-17b-instruct-v1:0
                 Meta's latest model. 17B parameters with improved reasoning.

    API endpoints:
    - GET /chat?q=<question>&model=<alias>   Single-turn chat
    - GET /rag?q=<question>&model=<alias>    RAG using S3 knowledge base
    - GET /models                            List all aliases
    - GET /aws                               S3 bucket list (IRSA demo)
    - GET /metrics                           Prometheus metrics

    Authentication: X-API-Key header required for /chat and /rag.
  EOT
  etag = md5("bedrock-models-v1")
}

output "rag_knowledge_bucket" {
  description = "S3 bucket name for RAG knowledge base（deployment.yaml KNOWLEDGE_BUCKET 用）"
  value       = aws_s3_bucket.rag_knowledge.id
}
