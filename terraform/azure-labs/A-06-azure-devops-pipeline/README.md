# A-06：Azure DevOps Pipeline 🟢 免費

> Terraform 建立 Azure DevOps 專案與 CI/CD pipeline，對比 CodePipeline（lab 26）與 GitHub Actions OIDC（lab 27）。

**費用估算**：Azure DevOps 免費 tier（5 user、1800 pipeline min/月）完全夠用，$0。

---

## 學習目標

- 理解 Azure DevOps Project 的概念（vs AWS 帳號層級的 CodePipeline）
- 學會用 Terraform `azuredevops` provider 管理 DevOps 資源
- 實作 Service Connection（vs GitHub Actions OIDC / CodePipeline execution role）
- 填寫 `azure-pipelines.yml` 的 4 個 TODO，完成 build → push ACR → deploy ACA 流程

## AWS vs Azure 對比

| 元素 | AWS (Lab 26-27) | Azure (本 Lab) |
|------|----------------|---------------|
| 資源容器 | 帳號層級，無需專案 | Azure DevOps **Project**（必須） |
| Pipeline 定義 | `buildspec.yml` + CodePipeline JSON | `azure-pipelines.yml`（全在一個 YAML）|
| Pipeline YAML 語法 | CodeBuild：`phases.build.commands` | ADO：`stages > jobs > steps > task` |
| 觸發器 | CodePipeline source stage | `trigger.branches / paths` |
| Runner/Agent | CodeBuild container | Microsoft-hosted agent（`vmImage`）|
| Azure/AWS 授權 | IAM Role（OIDC 或 instance profile） | **Service Connection**（自動建 SP）|
| 多環境審核 | CodePipeline Approval action | ADO **Environment** + Approval gate |
| 免費額度 | CodeBuild 100min/月 | ADO 1800min/月 |

## 架構

```
Git push to main
    │ trigger
    ▼
Azure DevOps Pipeline
  Stage 1: Build
    ├─ az acr login
    └─ docker build & push → ACR (A-02)
  Stage 2: Deploy（dependsOn: Build）
    └─ az containerapp update → Container App (A-01)

Service Connection（SP）
    ├─ Contributor on RG → 允許 deploy
    └─ AcrPush on ACR   → 允許 push image
```

## 前置步驟（手動，Terraform 做不到）

```bash
# 1. 建立 Azure DevOps 帳號（免費）
#    https://dev.azure.com → 用 Microsoft/GitHub 帳號登入

# 2. 建立 Personal Access Token (PAT)
#    右上角頭像 → Personal Access Tokens → New Token
#    需要的 scope（⚠️ 注意：Project and Team 需要勾 manage，否則建立 project 會 401）：
#      - Project and Team: Read, write, & manage
#      - Build: Read & Execute
#      - Service Connections: Read, query, & manage

# 3. 記下你的 org URL：https://dev.azure.com/<your-org>
```

## 你要做的事

### Terraform（main.tf）

| TODO | 資源 | 說明 |
|------|------|------|
| TODO 1 | `azurerm_resource_group` | Azure 資源容器 |
| TODO 2 | `azuredevops_project` | DevOps 專案 |
| TODO 3 | `azuredevops_serviceendpoint_azurerm` | Service Connection（WorkloadIdentityFederation，自動建立 SP）|
| TODO 4 | `azurerm_role_assignment` | SP 取得 Contributor 權限 |
| TODO 5 | `azuredevops_build_definition` | Pipeline 定義 |

### Pipeline YAML（azure-pipelines.yml）

| TODO | 位置 | 說明 |
|------|------|------|
| TODO A | `variables` | 填入 ACR server、Container App 名稱 |
| TODO B | Stage 1 step 1 | 完成 `az acr login` 指令 |
| TODO C | Stage 1 step 2 | Docker build & push 設定 |
| TODO D | Stage 2 step | 完成 `az containerapp update` 指令 |

## 操作步驟

```bash
# 1. 填寫 terraform.tfvars
cp terraform.tfvars.example terraform.tfvars

# 填入 subscription_id
az account show --query id -o tsv

# 填入 tenant_id
az account show --query tenantId -o tsv

# 填入 azuredevops_org_url、azuredevops_pat

# 2. 部署
terraform init
terraform fmt && terraform validate
terraform apply

# 3. 取得 DevOps 連結
terraform output devops_project_url   # 在瀏覽器開啟確認專案建好
terraform output service_connection_name  # 填入 azure-pipelines.yml 的 azureSubscription

# 4. 把 azure-pipelines.yml 推到 repo 根目錄
#    （或在 Azure DevOps 的 Repos 頁面直接建立）

# 5. 觸發 pipeline
git commit -m "feat: trigger pipeline" && git push
```

## 驗證

```bash
# 在瀏覽器確認
terraform output pipeline_url   # 開啟 pipeline 頁面，看 run 是否成功

# 或用 Azure DevOps CLI
az extension add --name azure-devops
az devops configure --defaults organization=$(terraform output -raw devops_project_url | cut -d/ -f1-4)
az pipelines run --name "azure-labs-ci-cd"
```

## 清除資源

```bash
terraform destroy -auto-approve
# Azure DevOps 專案會一起刪除
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `401 Unauthorized`（建立 project） | PAT 的 **Project and Team** scope 缺少 `manage`，重建 PAT 確認勾選 **Read, write, & manage** |
| `403 Forbidden` | PAT scope 不夠，確認 Build 與 Service Connections 也有勾選正確 scope |
| `azurerm_spn_tenantid` 錯誤 | `credentials {}` / `settings {}` block 是錯誤用法，應改用頂層屬性，見 main.tf TODO 3 |
| `service_principal_id` 找不到 | `azuredevops_serviceendpoint_azurerm` apply 後需等 30 秒 SP 才同步到 Entra ID |
| Pipeline 找不到 YAML | `yml_path` 相對路徑，確認 YAML 在 repo 根目錄且命名正確 |
| Stage 2 等待 approval | ADO Environment 預設需要手動審核，到 Environments 頁面點 Approve |
| `az containerapp update` 失敗 | Service Connection 的 SP 缺少 Container App 的 Contributor 權限 |
