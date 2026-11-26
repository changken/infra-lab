# Lab 38: 自動化部署流水線（GitHub Actions + ECS Blue/Green）

> git push → GitHub Actions（OIDC 零 Access Key）→ 建置 Docker image 推到 ECR → 上傳 deployment artifact 到 S3 → CodePipeline 偵測 → CodeDeploy ECS Blue/Green 零停機部署。

**費用等級**：🟡 注意（~$0.50，ALB ~$0.02/hr，Fargate ~$0.003/hr；練完當天 destroy）

---

## 學習目標

- 整合 **GitHub Actions OIDC + ECR + S3 + CodePipeline + CodeDeploy + ECS** 完整 CI/CD 流程
- 理解 **ECS Blue/Green 部署** 與 Rolling Update 的根本差異
- 掌握 **ALB 雙 Listener（80 生產 / 8080 測試）**在 Blue/Green 中的作用
- 設定 `deployment_controller { type = "CODE_DEPLOY" }` 並正確使用 `lifecycle { ignore_changes }`
- 理解 **GitHub Actions 如何透過 OIDC 取得 AWS 權限**（複習 Lab 27）
- 能從三個維度解釋此架構：成本、零停機、可回滾

---

## 架構

```
git push → main branch
    │
    ▼
GitHub Actions（OIDC → IAM Role，無 Access Key）
    ├── docker build + push ──────────────────→ ECR
    └── zip(appspec.yaml + taskdef.json) ────→ S3 Artifact Bucket
                                                    │
                                            CodePipeline（S3 polling）
                                                    │ Source Stage
                                                    ▼
                                            CodeDeploy（ECS Blue/Green）
                                                    │
                    ┌───────────────────────────────┘
                    ▼
           ALB Listener :80（生產）    ALB Listener :8080（測試）
                    │                           │
                    ▼                           ▼
          Blue Target Group            Green Target Group
          [舊版 ECS Task]              [新版 ECS Task]

  部署流程：
  1. 啟動 Green Tasks（新版本）
  2. 健康檢查通過後，切換 :80 → Green
  3. 5 分鐘後終止 Blue Tasks（舊版本）
  4. 若失敗 → 自動回滾到 Blue
```

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼用 Blue/Green 而不是 Rolling Update？

| | Rolling Update（ECS 預設）| Blue/Green（CodeDeploy）|
|--|--------------------------|------------------------|
| 部署期間 | 舊新版本混跑，可能影響部分用戶 | 新版本 100% 就緒後才切流量 |
| 回滾速度 | 慢（需要重新部署舊版本）| 快（切換 ALB Listener 即可）|
| 需要 | 無額外資源 | 雙倍 Task（短暫）|
| 適合場景 | 成本優先、可容忍短暫混版 | **零停機、快速回滾優先** |
| **結論** | 開發 / 低流量環境 | **選擇此方案** |

### ADR-2：為什麼 GitHub Actions 上傳 artifact 到 S3 而不直接觸發 CodeDeploy？

| | GitHub Actions 直接呼叫 CodeDeploy | S3 → CodePipeline → CodeDeploy |
|--|----------------------------------|-------------------------------|
| 責任分離 | CI 和 CD 耦合（GitHub 知道 CodeDeploy 細節）| CI 只管 build + push，CD 完全由 AWS 管 |
| 可見性 | 在 GitHub Actions 查部署狀態 | 在 AWS Console CodePipeline 查 |
| 彈性 | 難以在中間加審核、測試 Stage | 可在 Pipeline 加 Manual Approval、Test Stage |
| **結論** | 適合小團隊簡單場景 | **選擇此方案**（符合企業實踐）|

### ADR-3：為什麼 OIDC 而不是 Access Key？

| | Access Key | OIDC |
|--|-----------|------|
| 存放位置 | GitHub Secrets（長效憑證）| 不存放（短效 JWT）|
| 洩漏風險 | 高（Secrets 洩漏 = 永久 Access）| 低（JWT 15 分鐘過期）|
| 輪換 | 需要手動 rotate | 自動（每次 workflow 重新取得）|
| **結論** | 不推薦 | **選擇此方案**（AWS 官方推薦）|

---

## 你要做的事

| TODO | 資源 | 關鍵概念 |
|------|------|---------|
| 1 | `aws_ecr_repository` | `force_delete = true`，`scan_on_push = true` |
| 2 | VPC + 2 Subnets + IGW + Route Table | ALB 需要 2 個 AZ |
| 3 | `aws_security_group` × 2 | ALB SG 開 80 + 8080；ECS SG 只接受 ALB SG |
| 4 | ALB + Blue/Green TG + Listener × 2 | Fargate 的 `target_type = "ip"` |
| 5 | ECS Cluster + Task Execution Role + Log Group + Task Definition + Service | `deployment_controller { type = "CODE_DEPLOY" }` + `lifecycle { ignore_changes }` |
| 6 | CodeDeploy App + Deployment Group | Blue/Green config + `load_balancer_info` |
| 7 | OIDC Provider + GitHub Actions IAM Role | `repo:${var.github_repo}:*` 限制 Condition |
| 8 | S3 Bucket（含 Versioning）+ CodePipeline + IAM | S3 Source 需要 Versioning；Pipeline 第一次執行會失敗（正常）|

---

## 操作步驟

### 一、準備 GitHub Repo

在你的 GitHub Repo 中：
```bash
# 確認以下路徑存在（複製 lab 中的對應檔案）
.github/workflows/deploy.yml    ← 複製自 deploy/github-actions-workflow.yml
app/Dockerfile
app/index.html
deploy/appspec.yaml
deploy/taskdef.json             ← 先保留佔位符，terraform apply 後再填入
```

### 二、Terraform 部署

```bash
# 1. 複製變數（填入你的 GitHub repo 名稱）
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化
terraform fmt

# 4. 語法驗證
terraform validate

# 5. 預覽（確認將建立約 25 個資源）
terraform plan

# 6. 部署（約需 3-5 分鐘，ECS Service 建立較慢）
terraform apply
```

### 三、apply 後更新設定

```bash
# 查詢需要填入 GitHub Secrets 的值
terraform output github_secrets_summary

# 查詢 ECS Execution Role ARN（更新 deploy/taskdef.json 用）
terraform output ecs_execution_role_arn
```

**更新 `deploy/taskdef.json`**：
把 `<EXECUTION_ROLE_ARN>` 替換為上面輸出的 ARN：
```bash
EXEC_ROLE=$(terraform output -raw ecs_execution_role_arn)
sed -i "s|<EXECUTION_ROLE_ARN>|$EXEC_ROLE|g" deploy/taskdef.json
```

**在 GitHub 設定 Secrets**（Settings → Secrets and variables → Actions）：
```
AWS_ROLE_ARN     = <terraform output -raw github_actions_role_arn>
ECR_REPOSITORY   = <terraform output -raw ecr_repo_url | cut -d'/' -f2>
ARTIFACT_BUCKET  = <terraform output -raw artifact_bucket_name>
AWS_REGION       = us-east-1
```

### 四、觸發第一次部署

```bash
git add .
git commit -m "chore: trigger first pipeline run"
git push origin main
```

---

## 驗證

### 1. 確認 GitHub Actions 成功

在 GitHub → Actions 查看 workflow 執行結果，確認：
- AWS credentials 取得成功（OIDC）
- Docker image push 到 ECR 成功
- `deployment.zip` 上傳 S3 成功

### 2. 確認 CodePipeline 執行

```bash
eval "$(terraform output -raw pipeline_status_command)"
```

**期望輸出**：兩個 Stage 都是 `Succeeded`

### 3. 確認 ECS 服務正常

```bash
curl -s "$(terraform output -raw alb_prod_url)"
```

**期望輸出**：你的 index.html 內容（Lab 38: ECS Blue/Green Deploy - v1）

### 4. 觸發 Blue/Green 部署（修改 index.html 觀察）

```bash
# 修改 app/index.html，把 v1 改成 v2
sed -i 's/v1/v2/' app/index.html

git add app/index.html
git commit -m "feat: update to v2"
git push origin main
```

在 AWS Console → CodeDeploy → Deployments 觀察流量切換過程：
- 測試流量（`:8080`）先切到 Green
- 確認 Green 正常後，生產流量（`:80`）切到 Green
- 5 分鐘後 Blue Tasks 終止

```bash
# 部署期間，測試 listener 先看到新版本
curl -s "$(terraform output -raw alb_test_url)"  # 應顯示 v2
curl -s "$(terraform output -raw alb_prod_url)"  # 可能還是 v1（切換前）
```

---

## 可觀測性設計

| 問題 | 如何知道 | 查看位置 |
|------|---------|---------|
| GitHub Actions 失敗 | Workflow run 顯示紅燈 | GitHub → Actions |
| Pipeline 卡住 | Stage status 非 Succeeded | `terraform output pipeline_status_command` |
| ECS Task 不健康 | Target Group unhealthy count > 0 | AWS Console → EC2 → Target Groups |
| CodeDeploy 回滾 | Deployment status = Stopped | AWS Console → CodeDeploy → Deployments |
| ECS 容器 log | CloudWatch Logs | `/ecs/cicd-lab-web` |

---

## 結束

```bash
terraform destroy -auto-approve
```

> **注意**：ECS Service 使用 `CODE_DEPLOY` controller，destroy 可能需要額外 2-3 分鐘。若卡住，先在 AWS Console 手動刪除 ECS Service，再重試 `terraform destroy`。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| ALB | $0.008/hr |
| Fargate（256 CPU, 512 MB）| ~$0.003/hr |
| ECR 儲存（< 1 GB）| < $0.10/月 |
| CodePipeline | 第一條免費，之後 $1/月 |
| S3、CloudWatch Logs | < $0.01 |
| **合計（2 小時練習）** | **~$0.04（🟡 注意，練完當天 destroy）** |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| OIDC Provider 已存在 | Lab 27 已建過，執行 `terraform import aws_iam_openid_connect_provider.github arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com` |
| GitHub Actions: `not authorized to perform sts:AssumeRoleWithWebIdentity` | `github_repo` 變數格式錯誤（需要 `owner/repo`），或 Condition 設定有誤 |
| CodePipeline 第一次執行失敗 | 正常！S3 bucket 是空的，GitHub Actions push 後自動重試 |
| ECS Task 啟動後立即失敗 | `taskdef.json` 中的 `<EXECUTION_ROLE_ARN>` 未替換 |
| Blue/Green 部署卡在 `Deployment In Progress` | ECS 健康檢查失敗；確認 `nginx:alpine` 預設回應 200，且 ALB SG 允許 Health Check |
| `terraform destroy` 超時 | ECS Service（CODE_DEPLOY controller）需先手動在 Console 刪除 |
| Target Group unhealthy | `target_type` 必須是 `"ip"`（Fargate 不用 `"instance"`）|
| CodeDeploy role 缺少權限 | 確認附加了 `AWSCodeDeployRoleForECS` managed policy |

---

## 面試故事

> 「我設計過一個 CI/CD 流水線。開發者 push 到 main，GitHub Actions 透過 OIDC 取得暫時性 AWS credentials（完全不存 Access Key），build Docker image 推到 ECR，再把 deployment artifact 上傳 S3。CodePipeline 偵測到 S3 變更後，觸發 CodeDeploy 做 ECS Blue/Green 部署。新版本的 Task 啟動後，先通過 ALB 測試 Listener 的健康檢查，確認正常才把生產流量從 Blue 切到 Green，全程零停機。如果新版本有問題，CodeDeploy 會自動回滾。整個架構的好處是 CI 和 CD 完全解耦——GitHub 只管 build 和 artifact，AWS 這邊負責 deployment 的審批和執行。」
