# A-01：Azure Container Apps 🟢 免費

> 用 Terraform 部署第一個 Azure Container App，對比你已熟悉的 ECS Fargate。

**費用估算**：$0（min_replicas = 0，無流量時縮到零）

---

## 學習目標

- 理解 Azure Resource Group 的必要性（vs AWS 無強制容器概念）
- 學會 `azurerm_container_app_environment` vs ECS Cluster 的差異
- 實作 Container App 的 ingress 設定，取得公開 HTTPS URL
- 體會 ACA 比 ECS Fargate 更少的樣板設定

## AWS vs Azure 對比

| 元素 | AWS (Lab 11) | Azure (本 Lab) |
|------|-------------|---------------|
| 執行環境 | ECS Cluster | Container App Environment |
| 服務定義 | Task Definition + Service | Container App（合一） |
| Log | CloudWatch Log Group | Log Analytics Workspace |
| 對外 URL | ALB DNS | 內建 FQDN（不需要 ALB） |
| 縮到零 | 不支援（Fargate 最少 1 task） | 支援（min_replicas = 0） |

## 架構

```
Internet
    │ HTTPS
    ▼
┌─────────────────────────────────┐
│  Container App Environment      │
│  ┌───────────────────────────┐  │
│  │   Container App (nginx)   │  │
│  │   0-1 replicas            │  │
│  └───────────────────────────┘  │
│  Log Analytics Workspace        │
└─────────────────────────────────┘
        Resource Group
```

## 你要做的事

| TODO | 資源 | 說明 |
|------|------|------|
| TODO 1 | `azurerm_resource_group` | Azure 資源容器（必須） |
| TODO 2 | `azurerm_log_analytics_workspace` | 收 container log |
| TODO 3 | `azurerm_container_app_environment` | Container 執行環境 |
| TODO 4 | `azurerm_container_app` | 實際跑的 container |
| outputs | `app_url` | 填入正確的 FQDN attribute |

## 操作步驟

```bash
# 0. 確認 Azure CLI 已登入
az login
az account show --query id -o tsv   # 取得 subscription_id

# 1. 複製並填寫變數
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入 subscription_id

# 2. 初始化
terraform init

# 3. 格式化與驗證
terraform fmt
terraform validate

# 4. 預覽
terraform plan

# 5. 部署
terraform apply
```

## 驗證

```bash
# 取得 URL
terraform output app_url

# 測試（應該看到 nginx 歡迎頁）
curl https://$(terraform output -raw app_url)

# 或直接在瀏覽器開啟 output 的 URL
```

## 清除資源

```bash
terraform destroy -auto-approve
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `subscription_id` 錯誤 | 執行 `az account show --query id -o tsv` 取得正確值 |
| `cpu` / `memory` 不合法 | 只有固定組合：0.25/0.5Gi、0.5/1Gi、1.0/2Gi |
| ingress 沒有 `latest_revision` | `traffic_weight` block 裡要加 `latest_revision = true` |
| apply 後 URL 是 null | outputs.tf 的 FQDN attribute 填錯，查文件確認 |
| Container App 一直 Provisioning | 第一次建 Environment 需要 3-5 分鐘，正常現象 |
