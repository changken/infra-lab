# Lab 25: CodeBuild + ECR Image Build

> 用 CodeBuild 自動建置 Docker image 並推送到 ECR，理解 buildspec.yml 結構和 IAM 最小權限設計。

**費用等級**：🟢 安全（< $0.10，BUILD_GENERAL1_SMALL $0.005/分鐘，一次建置約 2-3 分鐘）

---

## 學習目標

- 理解 CodeBuild Project 的組成：Source、Environment、IAM Role、buildspec.yml
- 掌握 `buildspec.yml` 的 phases 結構（pre_build / build / post_build）
- 理解 `privileged_mode = true` 的必要性（容器內跑 Docker）
- 設計 CodeBuild IAM Policy 最小權限（ECR 登入 vs ECR 推送的權限差異）
- 為 Lab 26 CodePipeline 打基礎（`imagedefinitions.json` artifact）

---

## 架構

```
terraform apply
    │
    ├── 打包 app/ → source.zip → S3 Source Bucket
    └── 建立 CodeBuild Project（讀取 S3）
                        │
aws codebuild start-build
                        │
                        ▼
              CodeBuild 執行環境
              （LINUX_CONTAINER + privileged_mode）
                        │
              buildspec.yml phases
              ┌─────────────────────────────────┐
              │ pre_build:                      │
              │   aws ecr get-login-password    │
              │   docker login                  │
              │ build:                          │
              │   docker build -t ...           │
              │   docker tag                    │
              │ post_build:                     │
              │   docker push :tag              │
              │   docker push :latest           │
              │   生成 imagedefinitions.json    │
              └─────────────────────────────────┘
                        │
                        ▼
                  ECR Repository
                  (image 存放處)
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_ecr_repository.app` | `scan_on_push = true`，自動掃漏洞 |
| 2 | `aws_cloudwatch_log_group.codebuild` | 先建 log group，destroy 時才會清乾淨 |
| 3 | `aws_iam_role.codebuild` + `aws_iam_role_policy.codebuild` | 4 個權限區塊，注意 `ecr:GetAuthorizationToken` 只能 Resource `"*"` |
| 4 | `aws_codebuild_project.main` | `privileged_mode = true` 是關鍵，`source.location` 格式要注意 |

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

---

## 驗證

### 1. 手動觸發建置

```bash
PROJECT=$(terraform output -raw codebuild_project_name)

BUILD_ID=$(aws codebuild start-build \
  --project-name "$PROJECT" \
  --query 'build.id' --output text)

echo "Build ID: $BUILD_ID"
```

### 2. 查看建置狀態

```bash
# 輪詢直到完成（約 2-4 分鐘）
aws codebuild batch-get-builds --ids "$BUILD_ID" \
  --query 'builds[0].{status:buildStatus,phase:currentPhase}'
```

### 3. 即時觀看 log

```bash
LOG_GROUP=$(terraform output -raw log_group)

aws logs tail "$LOG_GROUP" --follow
```

預期看到：
```
=== 登入 Amazon ECR ===
Login Succeeded
=== 開始建置 Docker image ===
Successfully built xxxxxxxx
=== 推送到 ECR ===
latest: digest: sha256:... size: ...
=== 建置完成 ===
```

### 4. 確認 Image 已在 ECR

```bash
ECR_URL=$(terraform output -raw ecr_repository_url)

aws ecr describe-images \
  --repository-name "$(echo $ECR_URL | cut -d/ -f2)" \
  --query 'imageDetails[*].{tag:imageTags[0],pushed:imagePushedAt}' \
  --output table
```

### 5. 修改 app 後重新建置

修改 `app/app.py` 任一處，然後：

```bash
# Terraform 會重新打包並上傳 source.zip（etag 改變觸發 S3 object 更新）
terraform apply

# 再次觸發建置
BUILD_ID=$(aws codebuild start-build \
  --project-name "$PROJECT" \
  --query 'build.id' --output text)
```

---

## 結束

```bash
# 先清空 ECR（有 image 的話 destroy 會失敗）
ECR_REPO=$(terraform output -raw ecr_repository_url | cut -d/ -f2)
aws ecr list-images --repository-name "$ECR_REPO" \
  --query 'imageIds[*]' --output json | \
  xargs -I{} aws ecr batch-delete-image \
  --repository-name "$ECR_REPO" --image-ids {}

terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| CodeBuild BUILD_GENERAL1_SMALL | $0.005/分鐘，一次建置約 $0.01-0.02 |
| ECR Storage | $0.10/GB/月，幾十 MB 近乎免費 |
| S3 Source Bucket | < $0.01 |
| CloudWatch Logs | < $0.01 |
| **合計（10 次建置）** | **~$0.10-0.20** |

---

## 核心概念釐清

### buildspec.yml phases 執行順序

```
install → pre_build → build → post_build
```

任何 phase 失敗 → 建置立刻中止，後續 phases 不執行。
`post_build` 即使前面失敗也會執行（用於清理）—— 這是和其他 phase 的差異。

### privileged_mode = true 是什麼？

CodeBuild 本身跑在容器裡，要在容器內再跑 `docker build` 需要特殊的 Linux 權限（`--privileged` flag）。
不設定的話：
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

### ECR IAM 權限的兩個層次

| 動作 | Resource | 原因 |
|------|----------|------|
| `ecr:GetAuthorizationToken` | `"*"` | 這個 API 回傳的 token 可以登入任何 registry，AWS 設計上不支援限縮 |
| `ecr:PutImage` 等推送動作 | 特定 repo ARN | 限定只能推到這個 repo |

### imagedefinitions.json 是什麼？

Lab 26 CodePipeline 的 ECS Deploy Action 需要這個檔案，格式：
```json
[{"name":"app","imageUri":"xxxx.dkr.ecr.us-east-1.amazonaws.com/repo:latest"}]
```
告訴 ECS 要部署哪個 container 用哪個 image。在 `buildspec.yml` 的 `post_build` 生成，
並在 `artifacts` 區塊輸出，讓 CodePipeline 傳遞給下一個 Stage。

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `Cannot connect to the Docker daemon` | `privileged_mode = true` 沒設定 |
| `Error: no basic auth credentials` | ECR 登入失敗，`ecr:GetAuthorizationToken` 權限缺少 |
| `denied: User is not authorized to perform: ecr:InitiateLayerUpload` | IAM Policy 缺少 ECR 推送權限，或 Resource ARN 寫錯 |
| `DOWNLOAD_SOURCE Failed` | S3 source location 格式錯誤（應為 `bucket-name/key`）或 IAM 缺少 `s3:GetObject` |
| Build 卡在 QUEUED | 正常，CodeBuild 需要幾秒分配建置環境 |
| ECR repository already exists | 同名 ECR repo 已存在，換個 `project` 名稱或先手動刪除 |
