# Lab 27: GitHub Actions + OIDC → AWS（零 Access Key）

> 用 OIDC 讓 GitHub Actions 直接 assume IAM Role，取得暫時性 AWS Credentials，完全不需要儲存 Access Key。

**費用等級**：🟢 安全（$0，IAM 和 OIDC 完全免費）

---

## 學習目標

- 理解 OIDC 在 CI/CD 中解決的核心問題：長效憑證洩漏風險
- 掌握 `AssumeRoleWithWebIdentity` 和 `AssumeRole` 的差異
- 設計 IAM Trust Policy 的 `Condition`（限制特定 repo + branch）
- 理解 `id-token: write` permission 在 GitHub Actions 中的作用
- 把 `workflows/deploy.yml` 套用到自己的 repo

---

## 架構

```
GitHub Actions Runner
    │
    │ 1. 向 GitHub OIDC Provider 取得 JWT Token
    │    (包含 repo、branch、workflow 等 claims)
    ▼
GitHub OIDC Provider
(token.actions.githubusercontent.com)
    │
    │ 2. 帶著 JWT 向 AWS STS 請求 AssumeRoleWithWebIdentity
    ▼
AWS STS
    │ 3. 驗證 JWT 簽名 + 檢查 Trust Policy Condition
    │    - aud == "sts.amazonaws.com" ✓
    │    - sub == "repo:ORG/REPO:ref:refs/heads/main" ✓
    ▼
暫時性 Credentials（15 分鐘 ~ 1 小時，用完自動失效）
    │
    ▼
GitHub Actions 用 Credentials 操作 AWS（ECR push、ECS deploy 等）
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_iam_openid_connect_provider.github` | 每帳號只需建一次；thumbprint_list 的意義 |
| 2 | `aws_iam_role.github_actions` | `Federated` Principal + `AssumeRoleWithWebIdentity` + Condition 限縮 repo/branch |
| 3 | `aws_iam_role_policy.github_actions` | ECR 推送 + ECS 部署的最小權限 |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars
# 填入 github_org 和 github_repo

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## 設定 GitHub Actions

### 1. 取得 Role ARN

```bash
terraform output role_arn
# arn:aws:iam::123456789012:role/oidc-lab-github-actions-role
```

### 2. 在 GitHub repo 設定 Variables

到 `Settings → Secrets and variables → Variables → New repository variable`：

| Name | Value |
|------|-------|
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | `arn:aws:iam::...（terraform output role_arn）` |
| `ECR_REPO_NAME` | 你的 ECR repo 名稱（選填）|

### 3. 複製 workflow 到 repo

```bash
mkdir -p ../../.github/workflows
cp workflows/deploy.yml ../../.github/workflows/deploy.yml
git add .github/workflows/deploy.yml
git commit -m "feat: add GitHub Actions OIDC deploy workflow"
git push origin main
```

---

## 驗證

### 1. 確認 OIDC Provider 建立成功

```bash
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[*].Arn'
```

### 2. 確認 Trust Policy 設定正確

```bash
ROLE_ARN=$(terraform output -raw role_arn)
ROLE_NAME=$(echo $ROLE_ARN | cut -d/ -f2)

aws iam get-role --role-name "$ROLE_NAME" \
  --query 'Role.AssumeRolePolicyDocument' | python3 -m json.tool
```

確認 Condition 的 `sub` 值是 `repo:你的ORG/你的REPO:ref:refs/heads/main`。

### 3. 觸發 GitHub Actions

push 任何 commit 到 main branch，觀察 Actions tab 的執行結果。

Workflow 中的 `aws sts get-caller-identity` 步驟成功的話，會看到：
```json
{
  "UserId": "AROA...:GitHubActions-1234567890",
  "Account": "123456789012",
  "Arn": "arn:aws:sts::123456789012:assumed-role/oidc-lab-github-actions-role/GitHubActions-1234567890"
}
```

`Arn` 中的 `GitHubActions-XXXXXXXX` 是 `role-session-name`，會出現在 CloudTrail，方便稽核。

### 4. 驗證安全限制

把 workflow 的 `branches` 改成非 main 的分支（例如 `develop`），push 後應該看到：

```
Error: Not authorized to perform AssumeRoleWithWebIdentity
```

這證明 Trust Policy 的 Condition 有效限制了哪些 branch 可以使用這個 Role。

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| IAM OIDC Provider | 免費 |
| IAM Role | 免費 |
| **合計** | **$0** |

---

## 核心概念釐清

### 舊方法 vs OIDC

| | Access Key 方法 | OIDC 方法 |
|--|---|---|
| 存在哪 | GitHub Secrets（長效）| 不需要存，每次動態產生 |
| 有效期限 | 永久（需手動 rotate）| 15 分鐘 ~ 1 小時，自動失效 |
| 洩漏風險 | 高（log 印出來就完了）| 低（短效 token，洩漏後很快失效）|
| 稽核 | 難（哪次 workflow 用？）| 易（CloudTrail 的 session name 含 run_id）|
| 設定複雜度 | 低（存兩個 Secret 就好）| 稍高（需要 Terraform + Trust Policy）|

### Trust Policy Condition 的重要性

```hcl
Condition = {
  StringLike = {
    "token.actions.githubusercontent.com:sub" = "repo:myorg/myrepo:ref:refs/heads/main"
  }
}
```

不加 Condition 的後果：**任何 GitHub 使用者**建立一個 workflow，都可以 assume 這個 Role！
因為 OIDC token 的驗證只確認「這是 GitHub 發的」，不確認「是你的 repo」。

### `id-token: write` 為何必要？

GitHub Actions 預設不允許 workflow 取得 OIDC token（防止意外洩漏）。
必須在 workflow 的 `permissions` 明確加上 `id-token: write`，
`aws-actions/configure-aws-credentials` 才能向 GitHub 請求 JWT。

### OIDC Subject（sub）格式

| 觸發情境 | sub 格式 |
|---------|---------|
| Push 到 main | `repo:ORG/REPO:ref:refs/heads/main` |
| Push tag | `repo:ORG/REPO:ref:refs/tags/v1.0.0` |
| Pull Request | `repo:ORG/REPO:pull_request` |
| GitHub Environment | `repo:ORG/REPO:environment:production` |

建議生產環境用 `environment` 限制，配合 GitHub Environment 的保護規則（需要審核才能部署）。

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `Error: Credentials could not be loaded` | workflow 缺少 `permissions: id-token: write` |
| `Not authorized to perform: sts:AssumeRoleWithWebIdentity` | Trust Policy Condition 的 sub 不符，或 branch 名稱和 `github_branch` 不一致 |
| `OIDC provider already exists` | 帳號已有 GitHub OIDC Provider → 用 `terraform import` 匯入 |
| `InvalidIdentityToken` | thumbprint 過期，到 AWS Console 更新 OIDC Provider 的 thumbprint |
| CloudTrail 找不到紀錄 | IAM 事件有延遲，等幾分鐘再查 |
