# A-02：Azure Container Registry (ACR) 🟡 < $1

> 建立私有 Container Registry，build 並推送自己的 image，為 A-03 AKS 做準備。

**費用估算**：Basic tier $0.167/天 → 練完立刻 destroy

---

## 學習目標

- 理解 ACR vs ECR 的架構差異（一個 ACR 多個 repo vs ECR 每個 repo 獨立）
- 實作 `docker build` → `docker push` 到私有 registry 的完整流程
- 學習 Azure RBAC AcrPull role（對比 ECR resource policy）
- 體驗 `az acr build` 雲端 build（不需要本地 Docker daemon）

## AWS vs Azure 對比

| 元素 | AWS (Lab 10) | Azure (本 Lab) |
|------|-------------|---------------|
| Registry 單位 | 每個 repo 獨立 | 一個 ACR 下多個 repo |
| 登入方式 | `aws ecr get-login-password` | `az acr login` 或 admin 帳密 |
| 授權 | ECR Resource Policy + IAM | RBAC AcrPull Role Assignment |
| 雲端 build | 無（需本地 Docker） | `az acr build`（不需本地 daemon） |
| 命名限制 | 帳號內唯一 | **全域唯一**，只能英數 |

## 架構

```
本機 / Cloud Shell
    │ docker build / az acr build
    ▼
┌─────────────────────────────────┐
│  Azure Container Registry       │
│  acrdevacr.azurecr.io           │
│  ├── hello-azure:v1             │
│  └── （未來 A-03 AKS 使用）     │
└─────────────────────────────────┘
        Resource Group
```

## 你要做的事

| TODO | 資源 | 說明 |
|------|------|------|
| TODO 1 | `azurerm_resource_group` | 資源容器 |
| TODO 2 | `azurerm_container_registry` | ACR 主體 |
| outputs | `acr_name`、`login_server`、`docker_login_cmd` | 填入正確 attribute |

TODO 3（Role Assignment）是選填，先跳過也能跑。

## 操作步驟

```bash
# 1. 複製並填寫變數
cp terraform.tfvars.example terraform.tfvars

# 2. 部署 ACR
terraform init
terraform fmt && terraform validate
terraform apply

# 3. 登入 ACR（方法 A：az cli）
az acr login --name $(terraform output -raw acr_name)

# 3. 登入 ACR（方法 B：docker login 用 admin 帳密）
terraform output -raw docker_login_cmd
# 把輸出的指令複製下來跑

# 4. Build 並推送 image（需要先在此目錄建立 Dockerfile）
docker build -t $(terraform output -raw acr_login_server)/hello-azure:v1 .
docker push $(terraform output -raw acr_login_server)/hello-azure:v1

# 或用 az acr build（不需本地 Docker）
az acr build --registry $(terraform output -raw acr_name) --image hello-azure:v1 .
```

## 驗證

```bash
# 列出 ACR 中的 image
az acr repository list --name $(terraform output -raw acr_name) --output table

# 查看 tag
az acr repository show-tags \
  --name $(terraform output -raw acr_name) \
  --repository hello-azure \
  --output table
```

## 清除資源

```bash
terraform destroy -auto-approve
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| ACR 名稱衝突 | 全域唯一，`local.acr_name` 已去掉連字號，但可能被別人用了 — 在 project 名加個數字 |
| `docker push` 403 | 需先 `az acr login` 或用 admin 帳密登入 |
| `az acr build` 找不到 Dockerfile | 確認當前目錄有 `Dockerfile` |
| outputs 都是 null | outputs.tf 的 attribute 還是 TODO，記得填 |
