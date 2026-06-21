#!/usr/bin/env bash
# 用法（從 envs/aws-eks/ 目錄執行）：
#   bash scripts/deploy.sh v1
#   bash scripts/deploy.sh v2

set -euo pipefail

TAG="${1:-v1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")"

# ── 取得 Terraform outputs ──────────────────────────────────
echo ">>> 讀取 Terraform outputs..."
cd "$ENV_DIR"

ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null) || {
  echo "Error: 找不到 ECR URL，請先執行 terraform apply"
  exit 1
}
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
IMAGE="$ECR_URL:$TAG"

# ── ECR 登入 ────────────────────────────────────────────────
echo ">>> 登入 ECR..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_URL"

# ── Build + Push ─────────────────────────────────────────────
echo ">>> Building $IMAGE..."
docker build -t "$IMAGE" "$ENV_DIR/app"

echo ">>> Pushing $IMAGE..."
docker push "$IMAGE"

# ── Deploy 到 EKS ───────────────────────────────────────────
echo ">>> Deploying to EKS..."
K8S_DIR="$ENV_DIR/k8s/custom-app"

kubectl apply -f "$K8S_DIR/namespace.yaml"

# 替換 placeholder 後 apply（不修改原始 yaml）
sed "s|REPLACE_WITH_ECR_URL|$IMAGE|g" "$K8S_DIR/deployment.yaml" \
  | kubectl apply -f -

kubectl apply -f "$K8S_DIR/service.yaml"
kubectl apply -f "$K8S_DIR/ingress.yaml"

# ── 等待部署完成 ──────────────────────────────────────────────
echo ">>> 等待 rollout..."
kubectl rollout status deployment/custom-app -n custom-app --timeout=120s

echo ""
echo "✓ 部署完成：$IMAGE"
echo ""
echo "等待 ALB（約 2 分鐘後）："
echo "  kubectl get ingress custom-app -n custom-app"
