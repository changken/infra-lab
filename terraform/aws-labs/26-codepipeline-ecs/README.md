# Lab 26: CodePipeline（Source → Build → ECS Deploy）

> 把 Lab 25 的 CodeBuild 整合進 CodePipeline，實現「改程式碼 → 自動建置 → 自動部署到 ECS」的完整 CI/CD 流程。

**費用等級**：🟡 注意（~$0.20，CodePipeline $1/月/pipeline，做完當天 destroy）

---

## 學習目標

- 理解 CodePipeline 的三個概念：Pipeline、Stage、Action
- 掌握 Artifacts 在 Stage 間的流動（`output_artifacts` → `input_artifacts`）
- 理解 `imagedefinitions.json` 如何連接 Build Stage 和 ECS Deploy Stage
- 設計 CodePipeline IAM Policy（特別是 `iam:PassRole` 的必要性）
- 理解 ECS Service 的 `lifecycle { ignore_changes = [task_definition] }` 為何必要

---

## 架構

```
terraform apply → 上傳 source.zip → S3 Source Bucket
                                          │
                                   (版本變更偵測)
                                          │
                              ┌───────────▼───────────┐
                              │   CodePipeline        │
                              │                       │
                              │  Stage 1: Source      │
                              │  S3 → source_output   │
                              │          │            │
                              │  Stage 2: Build       │
                              │  CodeBuild            │
                              │  source_output →      │
                              │  build_output         │
                              │  (含 imagedefinitions) │
                              │          │            │
                              │  Stage 3: Deploy      │
                              │  ECS Rolling Update   │
                              │  build_output → ECS   │
                              └───────────────────────┘
                                          │
                                          ▼
                                    ECS Fargate
                                    (更新 image)
```

### artifacts 流動圖

```
source.zip (S3)
    │
    ▼ [Source Stage]
source_output (zip，包含 app/ 所有檔案)
    │
    ▼ [Build Stage: CodeBuild]
    ├── docker build + push → ECR
    └── 生成 imagedefinitions.json
build_output (zip，只含 imagedefinitions.json)
    │
    ▼ [Deploy Stage: ECS]
讀取 imagedefinitions.json
更新 ECS Service Task Definition
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_ecr_repository.app` | 和 Lab 25 相同 |
| 2 | SG + Cluster + Task Definition + Service | container name = "app"；`ignore_changes = [task_definition]` |
| 3 | CodeBuild IAM + Project | `type = "CODEPIPELINE"`（和 Lab 25 不同）；Artifact Bucket 需要讀寫 |
| 4 | CodePipeline IAM + Policy | 5 個權限區塊，`iam:PassRole` 最容易忘 |
| 5 | `aws_codepipeline.main` | 3 個 Stage，理解 input/output artifacts 的名稱對應 |

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

`apply` 完成後，CodePipeline 會自動因為偵測到 S3 source 變更而觸發第一次執行。

---

## 驗證

### 1. 觀察 Pipeline 執行

```bash
PIPELINE=$(terraform output -raw pipeline_name)

# 查看最新執行狀態
aws codepipeline list-pipeline-executions \
  --pipeline-name "$PIPELINE" \
  --max-results 1 \
  --query 'pipelineExecutionSummaries[0].{status:status,started:startTime}'
```

或直接到 AWS Console → CodePipeline，視覺化觀察三個 Stage 的進度。

### 2. 查看 Build log

```bash
aws logs tail "/aws/codebuild/$PIPELINE" --follow
```

### 3. 確認 ECS Service 已部署新 image

```bash
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)

# 查看 Service 目前運行的 task definition
aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].{taskDef:taskDefinition,running:runningCount,desired:desiredCount}'
```

### 4. 確認 ECR image 存在

```bash
ECR_REPO=$(terraform output -raw ecr_repository_url | cut -d/ -f2)

aws ecr describe-images \
  --repository-name "$ECR_REPO" \
  --query 'imageDetails[*].{tag:imageTags[0],pushed:imagePushedAt}' \
  --output table
```

### 5. 觸發第二次 Pipeline（模擬程式碼更新）

修改 `app/app.py`（例如改 version 字串），然後：

```bash
terraform apply   # 重新打包並上傳 source.zip，觸發 Pipeline
```

等 Pipeline 跑完後，ECS Service 會自動部署新版 image。

---

## 結束

```bash
# 先清空 ECR（有 image 時 destroy 會失敗）
ECR_REPO=$(terraform output -raw ecr_repository_url | cut -d/ -f2)
IMAGE_IDS=$(aws ecr list-images --repository-name "$ECR_REPO" \
  --query 'imageIds' --output json)
if [ "$IMAGE_IDS" != "[]" ]; then
  aws ecr batch-delete-image \
    --repository-name "$ECR_REPO" \
    --image-ids "$IMAGE_IDS"
fi

terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| CodePipeline | $1.00/月（超過 1 條 pipeline）|
| CodeBuild BUILD_GENERAL1_SMALL | ~$0.01-0.02/次建置 |
| ECS Fargate 1 task (256 CPU / 512 MB) | ~$0.01/hr |
| ECR Storage | < $0.01 |
| S3 兩個 bucket | < $0.01 |
| **1 天合計** | **~$0.15-0.25** |

---

## 核心概念釐清

### Source Bucket vs Artifact Bucket

| | Source Bucket | Artifact Bucket |
|--|---|---|
| 用途 | 存放你的程式碼，觸發 Pipeline | CodePipeline 內部傳遞 Stage 產出 |
| 誰寫入 | 你（terraform apply）| CodePipeline 自動管理 |
| 需要 versioning | 是（PollForSourceChanges 需要）| 否（Pipeline 管理） |

### imagedefinitions.json 是連接 Build → ECS 的橋樑

```json
[{"name": "app", "imageUri": "xxxx.dkr.ecr.us-east-1.amazonaws.com/repo:abc12345"}]
```

- `name`：**必須完全符合** ECS Task Definition 的 container name
- `imageUri`：新版本的 image（帶 commit hash tag，不用 latest）

ECS Deploy Action 讀到這個檔案後，會自動 register 一個新的 Task Definition revision（image 換成新的），然後更新 Service 使用這個新版本。

### 為什麼 ECS Service 需要 `ignore_changes = [task_definition]`？

CodePipeline 每次部署都會 register 一個新的 Task Definition revision，ECS Service 的 `task_definition` 會變成新的 revision。
下次你 `terraform apply` 時，Terraform 看到 state 裡的 task_definition 和實際不同，會嘗試改回去，和 Pipeline 打架。
`ignore_changes` 告訴 Terraform：這個欄位讓 CodePipeline 管，Terraform 不要動它。

### iam:PassRole 是什麼？

CodePipeline 在 Deploy Stage 呼叫 ECS 時，需要「把 ECS Task Execution Role 傳給 ECS」。
這個動作叫 PassRole，需要明確授權：
```
Action: iam:PassRole
Resource: <ECS Task Execution Role ARN>
```
沒有這個 → Deploy Stage 報 `not authorized to perform: iam:PassRole on resource`.

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| Pipeline Source Stage 失敗 | S3 Bucket versioning 沒有啟用，或 CodePipeline 沒有 s3:GetBucketVersioning 權限 |
| Pipeline Build Stage 失敗 | CodeBuild IAM 缺少 Artifact Bucket 的 `s3:PutObject`，或 `privileged_mode` 沒設 |
| Pipeline Deploy Stage 失敗（PassRole 錯誤）| CodePipeline IAM 缺少 `iam:PassRole` |
| Pipeline Deploy Stage 失敗（image name 錯誤）| `imagedefinitions.json` 的 container name 和 Task Definition 不一致 |
| ECS Service 一直 rolling（停不下來）| Task 無法啟動，看 ECS Service Events 和 CloudWatch Logs |
| `terraform apply` 後 Pipeline 沒觸發 | S3 etag 沒變（程式碼沒改），或 `PollForSourceChanges = false` |
