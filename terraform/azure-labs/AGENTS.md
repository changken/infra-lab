# Azure Labs — AI Agent 協作指南

本文檔為 AI 助手提供 Azure Labs 的背景與協作規範。
`CLAUDE.md` / `GEMINI.md` 為 symlink，指向此檔案。

## 專案概覽

**目標**：透過 Terraform + AzureRM provider 學習 Azure，以「AWS 對比」方式加速理解
**前提**：使用者已完成 `terraform/labs/` 中的 AWS labs（01-45）
**預算**：Azure Student Credit $100，目標花費 < $15（保留餘裕探索）
**語言**：文件使用繁體中文，程式碼使用英文

## 目錄結構

```
azure-labs/
├── AGENTS.md                    # AI 協作指南（本文件）
├── CLAUDE.md                    # → AGENTS.md（symlink）
├── A-01-container-apps/         # Azure Container Apps（對比 ECS Fargate）
├── A-02-acr/                    # Azure Container Registry（對比 ECR）
├── A-03-aks-cluster/            # AKS 基礎（對比 EKS lab 15-16）
├── A-04-aks-workload-identity/  # AKS Workload Identity（對比 IRSA lab 17）
├── A-05-azure-sql-serverless/   # Azure SQL Serverless（對比 RDS lab 04）
└── A-06-azure-devops-pipeline/  # Azure DevOps CI/CD（對比 CodePipeline lab 26）
```

## AWS vs Azure 對照速查

| 概念 | AWS | Azure |
|------|-----|-------|
| 帳號隔離 | AWS Account | Subscription |
| 資源容器 | —（無強制） | Resource Group（**必須**） |
| 虛擬網路 | VPC | Virtual Network (VNet) |
| 子網路 | Subnet | Subnet |
| 防火牆（VM） | Security Group | Network Security Group (NSG) |
| 容器服務（Serverless） | ECS Fargate | Container Apps |
| 容器 Registry | ECR | ACR (Azure Container Registry) |
| Kubernetes | EKS | AKS |
| 關聯式 DB | RDS | Azure SQL / Azure Database |
| 物件儲存 | S3 | Blob Storage |
| 秘密管理 | Secrets Manager | Key Vault |
| Pod 身份（K8s） | IRSA | Workload Identity |
| CI/CD | CodePipeline | Azure DevOps Pipelines |
| IaC Provider | hashicorp/aws | hashicorp/azurerm |

## Azure 關鍵概念（AWS 使用者須知）

### 1. Resource Group 是必須的
Azure 所有資源都必須屬於某個 Resource Group——不像 AWS 資源可以獨立存在。
Destroy 時 `terraform destroy` 會刪除所有資源，但 Resource Group 本身也要一起刪。

### 2. Location 命名
Azure 用 `location`（如 `japaneast`、`eastasia`）而非 AWS 的 `region`。
Student 帳號推薦用 `japaneast`（台灣最近的穩定區域）。

### 3. Provider 認證
```bash
# 推薦：Azure CLI 登入（本機開發）
az login
az account set --subscription "<subscription-id>"
```
Terraform 會自動讀取 Azure CLI 的 credential，不需要另外設定 client_id/client_secret。

### 4. 命名限制
| 資源 | 長度限制 | 特殊限制 |
|------|---------|---------|
| Resource Group | 1-90 | 英數、底線、連字號 |
| Storage Account | 3-24 | **只能小寫英數**，全域唯一 |
| ACR | 5-50 | 英數，全域唯一 |
| Container App | 2-32 | 英數、連字號 |

## Lab 骨架規範

每個 lab 目錄結構：

```
A-XX-lab-name/
├── terraform.tf           # Provider + 版本鎖定
├── variables.tf           # 輸入變數（含 location、project、environment）
├── locals.tf              # common_tags
├── main.tf                # 主要資源（含 TODO 提示）
├── outputs.tf             # 輸出值
├── terraform.tfvars.example
├── .gitignore
├── .terraform.lock.hcl    # ✅ 提交至 Git
└── README.md
```

### terraform.tf 標準格式

```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

### common_tags 標準格式

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

### TODO 格式（與 AWS labs 一致）

```hcl
#--------------------------------------------------------------
# TODO N: 資源說明（對比 AWS：aws_xxx）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/xxx
#
# 需要設定：
#   key1 = value1    # 說明
#
# ⚠️ 注意：Azure 特有的坑

resource "azurerm_xxx" "name" {
  # TODO
}
```

## 成本警示

| 等級 | 費用 | 資源範例 | 處置 |
|------|------|---------|------|
| 🟢 安全 | $0 | Container Apps（free tier）、Azure DevOps | 可保留 |
| 🟡 注意 | < $1/次 | ACR Basic、Azure SQL Serverless | 練完 destroy |
| 🔴 危險 | > $1/hr | AKS（含 node VM）、Azure Database | 一日 Sprint，當天 destroy |

**高費用資源特別提醒**：
- AKS node VM (B2s)：$0.048/hr → 超過 8 小時 destroy
- ACR Basic：$0.167/天 → 練完立刻刪
- Azure SQL：Serverless 版本閒置近乎 $0，但 General Purpose 很貴

## 安全最佳實踐

1. `subscription_id` 放 `terraform.tfvars`（已加入 `.gitignore`），不硬編碼
2. 密碼、connection string 加 `sensitive = true`
3. NSG 預設拒絕，只開必要 port
4. 不要 commit `.terraform/`、`*.tfstate`、`*.tfvars`

## 參考資源

- AzureRM Provider Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- Azure Pricing Calculator: https://azure.microsoft.com/pricing/calculator/
- Azure Student: https://azure.microsoft.com/free/students/
- Azure Regions: `az account list-locations --output table`
