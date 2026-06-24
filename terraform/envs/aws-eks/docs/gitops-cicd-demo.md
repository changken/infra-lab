# GitOps CI/CD Demo — GitHub Actions OIDC + ECR + ArgoCD

## 架構概覽

```
Developer
   │
   │  git push (main)
   ▼
GitHub (eks-app repo)
   │
   │  OIDC token
   ▼
AWS STS ──────── IAM Role (infra-lab-dev-github-actions-role)
   │                  └── 鎖定 sub: repo:changken/eks-app:ref:refs/heads/main
   │
   │  臨時憑證（TTL 1hr）
   ▼
Amazon ECR
   │  docker push :SHA + :latest
   ▼
eks-app/k8s/deployment.yaml  ←── Actions bot 自動 commit image tag
   │
   │  ArgoCD 偵測 git diff
   ▼
EKS Cluster
   └── kubectl rollout → 新 Pod（版本: v8）
```

**核心設計**：CI Pipeline 完全 passwordless — 不存任何 AWS Access Key，改用 OIDC 短命 token。

---

## 元件清單

| 元件 | 說明 |
|------|------|
| `github_oidc.tf` | GitHub OIDC Provider + IAM Role + ECR Policy |
| `.github/workflows/deploy.yml` | CI 流程（build → push → 更新 manifest） |
| `k8s/deployment.yaml` | GitOps 來源，image tag 由 CI 自動更新 |
| ArgoCD Application | 監聽 `eks-app` repo，自動 sync |

---

## Terraform 資源（github_oidc.tf）

### OIDC Provider
```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
```
每個 AWS 帳號只需要一個，讓 AWS 信任 GitHub 簽發的 OIDC token。

### IAM Role（Assume Policy 關鍵）
```hcl
Condition = {
  StringEquals = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
  }
  StringLike = {
    # 鎖定到特定 repo + branch，其他 repo 無法 assume
    "token.actions.githubusercontent.com:sub" = "repo:changken/eks-app:ref:refs/heads/main"
  }
}
```

### ECR Policy（最小權限）
| Sid | Action | Resource |
|-----|--------|----------|
| `AllowECRLogin` | `ecr:GetAuthorizationToken` | `*`（API 限制，無法縮小） |
| `AllowECRPush` | BatchCheck / InitiateUpload / PutImage 等 | 僅 `infra-lab-dev-app` repo ARN |

---

## GitHub Actions Workflow（deploy.yml）

```
on:
  push:
    branches: [main]

permissions:
  id-token: write   # OIDC token
  contents: write   # 寫回 deployment.yaml
```

### 執行步驟

```
1. actions/checkout@v4
2. aws-actions/configure-aws-credentials@v4  ← OIDC → STS → 臨時憑證
3. aws-actions/amazon-ecr-login@v2
4. docker build + push :SHA + :latest
5. sed -i 更新 deployment.yaml 的 image tag
6. git commit + push  ← "ci: update image tag to <SHA[:7]>"
```

### 實際執行記錄

```
Commit: 4e22004  (ci: bump version to v8)
  │
  ├── GitHub Actions Job: "deploy"
  │     ├── OIDC Auth    → OK (role: infra-lab-dev-github-actions-role)
  │     ├── ECR Login    → OK
  │     ├── docker build → OK (go1.24.13, multi-stage)
  │     ├── docker push  → 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:4e22004
  │     │                  661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:latest
  │     └── git push     → commit 92240a7 "ci: update image tag to 4e22004"
  │
  └── ArgoCD detected diff @ 92240a7
        └── kubectl rollout → custom-app-6d6678d665 (2/2 Running)
```

---

## ArgoCD Application 設定

```yaml
# k8s/argocd/custom-app-app.yaml
spec:
  source:
    repoURL: https://github.com/changken/eks-app
    targetRevision: HEAD
    path: k8s
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

ArgoCD 每 3 分鐘 poll 一次（或 webhook 觸發），偵測到 `deployment.yaml` 的 image tag 有 diff 就自動 sync。

---

## 驗證結果

### ECR Image
```
Repository : infra-lab-dev-app
Tags       : 4e220048ea7d6258a2e7078541f0bc91c6d93327, latest
Pushed     : 2026-06-24T08:33:18+08:00
Digest     : sha256:15720d4f503a53ab254b669a3403162b81b6508bda98185aec2df90dc96782de
```

### ArgoCD Status
```
NAME         SYNC STATUS   HEALTH STATUS
custom-app   Synced        Healthy
Revision: 92240a705067c97b3799b711cb5b34f1adcecc82
```

### App Response
```bash
$ curl http://k8s-eksdemo-abd6a613bf-2113898471.us-east-1.elb.amazonaws.com/
{
  "hostname":   "custom-app-6d6678d665-v8xjw",
  "node_name":  "ip-10-0-11-111.ec2.internal",
  "namespace":  "custom-app",
  "version":    "v8",
  "uptime":     "8m2s",
  "go_version": "go1.24.13"
}
```

---

## 安全重點

### OIDC vs Access Key 對比

| 項目 | OIDC（本 Lab） | 傳統 Access Key |
|------|--------------|----------------|
| 憑證存放 | 無（不存任何 key） | GitHub Secrets |
| 有效期 | 每次 Job 自動輪換，TTL 1hr | 永久（手動 rotate） |
| 洩漏風險 | 極低（無靜態 key） | 高（secrets 一旦洩漏可長期使用） |
| 範圍控制 | sub condition 鎖定 repo + branch | 無法鎖定來源 |
| 稽核 | CloudTrail 顯示 `AssumeRoleWithWebIdentity` | 顯示 `AssumeRole` |

### Sub Condition 說明
```
repo:changken/eks-app:ref:refs/heads/main
```
- `fork` 的 PR 無法 assume（不同 repo）
- `feature/*` branch 也無法 assume（不同 ref）
- 若要允許所有 branch 改成 `repo:changken/eks-app:*`（較寬鬆）

---

## 完整流程時序

```
t=0s   git push (main)
t=10s  GitHub Actions 啟動
t=30s  OIDC token → STS → 臨時憑證取得
t=60s  docker build 完成
t=90s  ECR push :SHA + :latest 完成
t=100s Actions bot commit k8s/deployment.yaml
t=110s git push 92240a7 回 main
t=180s ArgoCD 偵測到 diff（3min poll cycle）
t=190s kubectl rollout 開始
t=210s 新 Pod Running，舊 Pod Terminating
t=220s Deployment Healthy ✅
```

---

## 延伸閱讀

- [karpenter-demo.md](./karpenter-demo.md) — Node 自動擴縮（配合本 Lab 的 Pod 自動部署）
- [argocd-demo.md](./argocd-demo.md) — ArgoCD 基礎安裝與設定
- [irsa-demo.md](./irsa-demo.md) — IRSA（Pod 層級的 OIDC，與本 Lab 的 CI 層級 OIDC 互補）
- AWS 官方：[GitHub OIDC with AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
