# AI Agent 協作指南

本文檔為 AI 助手（如 Claude、GitHub Copilot、Cursor AI 等）提供專案背景與協作規範，幫助 AI 更好地理解專案目標並提供精準協助。

## 專案概覽

**專案名稱**: Terraform AWS Labs  
**專案目標**: 透過實作練習學習 Terraform 和 AWS，建立從基礎到進階的學習路徑  
**學習方式**: 每個練習專案獨立運作，可單獨執行和銷毀

## 目錄結構

```
terraform-aws-labs/
├── 01-ec2-web-server/     # 練習專案（按編號順序）
├── 02-xxx/                # 未來的練習專案
├── modules/               # 可重用模組
│   ├── backend/
│   ├── compute/
│   ├── database/
│   ├── iam-baseline/
│   ├── networking/
│   ├── serverless/
│   └── storage/
└── docs/
    ├── roadmap.md         # 完整學習路線圖
    └── agents.md          # 本文件
```

## 學習路線

完整路線圖請參考 [roadmap.md](file:///home/changken/terraform-aws-labs/docs/roadmap.md)，共分為 6 個階段：

1. **基礎設施**（1-2 週）: EC2, VPC, S3
2. **資料層**（3-4 週）: RDS, DynamoDB
3. **Serverless**（5-7 週）: Lambda, API Gateway
4. **容器化**（8-11 週）: ECR, App Runner, ECS Fargate
5. **Kubernetes**（12-15 週）: EKS
6. **DevOps & 監控**（16-18 週）: CloudWatch, Secrets Manager, IAM

## AI 協作規範

### 優先原則

1. **學習導向**: 這是學習專案，不是生產環境。優先考慮可讀性和教育價值，而非極致優化
2. **漸進式**: 按照路線圖順序進行，避免跨階段引入複雜概念
3. **獨立性**: 每個練習專案應該能獨立運作，避免過度耦合
4. **最佳實踐**: 遵循 Terraform 和 AWS 的最佳實踐，但要在複雜度和學習曲線間取得平衡

### 程式碼風格

#### Terraform 檔案結構

每個練習專案應包含：

```
xx-project-name/
├── terraform.tf       # Provider 和 Terraform 版本設定
├── variables.tf       # 輸入變數定義
├── locals.tf          # 區域變數（可選）
├── main.tf            # 主要資源定義
├── outputs.tf         # 輸出值
├── terraform.tfvars.example  # 範例變數檔
└── README.md          # 專案說明與使用指南
```

#### 命名規範

- **資源名稱**: 使用 `snake_case`，例如 `aws_instance.web_server`
- **變數名稱**: 使用描述性名稱，例如 `instance_type` 而非 `type`
- **標籤**: 統一使用 `Name`, `Environment`, `Project` 等標籤

#### 註解規範

- 在關鍵資源上方加入註解，說明用途和學習重點
- 對於較複雜的設定，說明為什麼這樣做
- 範例：

```hcl
# Security Group: 允許 HTTP/HTTPS 和 SSH 訪問
# 學習重點: ingress/egress 規則設定
resource "aws_security_group" "web" {
  name        = "web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id
  
  # ...
}
```

### 協助方式建議

#### 當用戶要求新增練習專案時

1. **確認階段**: 檢查是否符合當前學習階段，避免跳躍式學習
2. **參考路線圖**: 對照 `roadmap.md` 確認練習編號和內容
3. **結構完整**: 確保包含所有必要檔案（terraform.tf, variables.tf, main.tf, outputs.tf, README.md）
4. **README.md**: 必須包含以下章節
   - 專案說明
   - 學習目標
   - 架構圖（可選）
   - 使用方式
   - 清理資源的指令
   - 預估成本（重要！）

#### 當用戶要求除錯時

1. **檢查 Terraform 版本**: 確認是否符合專案需求（>= 1.2）
2. **檢查狀態檔**: 提醒用戶不要提交 `*.tfstate` 到版本控制
3. **驗證語法**: 建議執行 `terraform validate` 和 `terraform fmt`
4. **安全檢查**: 特別注意 IAM 權限、Security Group 規則等安全設定

#### 當用戶要求創建模組時

1. **評估可重用性**: 確認是否真的需要抽象成模組
2. **模組位置**: 放在 `modules/` 對應類別下
3. **模組結構**: 包含 `variables.tf`, `main.tf`, `outputs.tf`, `README.md`
4. **版本化**: 提醒未來可考慮使用 Git 標籤進行模組版本管理

### 成本意識

協助用戶時，應主動提醒可能產生的 AWS 費用：

- **免費方案**: 優先使用 AWS 免費方案資源（如 t2.micro, t3.micro）
- **費用估算**: 對於付費資源，提供大致費用估算
- **清理提醒**: 在每個練習的 README.md 中強調清理資源的重要性
- **高費用警告**: 對於 RDS, EKS, NAT Gateway 等較貴的服務，特別提醒

範例警告：

> [!WARNING]
> **成本提醒**: NAT Gateway 每小時約 $0.045，每月約 $32.4 USD。練習完畢請務必執行 `terraform destroy`。

### 安全最佳實踐

1. **不要硬編碼密鑰**: 使用 `variables.tf` 和 `.tfvars`（加入 `.gitignore`）
2. **最小權限原則**: IAM 政策應遵循最小權限原則
3. **預設拒絕**: Security Group 應採用預設拒絕，明確允許的策略
4. **敏感輸出**: 對於敏感資訊的輸出，使用 `sensitive = true`

### 文件撰寫

協助撰寫文件時，應使用：

- **繁體中文**: 主要文件使用繁體中文
- **英文註解**: 程式碼註解可使用中英文混合，但 Terraform 資源名稱使用英文
- **Markdown 格式**: 使用標準 Markdown 和 GitHub Flavored Markdown
- **程式碼區塊**: 使用正確的語法高亮（```hcl, ```bash）

## 常見任務範例

### 1. 建立新練習專案

```bash
# 用戶請求：「幫我建立 02-custom-vpc 練習專案」
# 
# AI 應該：
# 1. 確認這是階段 1 的第 2 個練習
# 2. 參考 roadmap.md 中的說明
# 3. 建立完整的檔案結構
# 4. 在 README.md 中強調學習重點
# 5. 提醒成本和清理資源
```

### 2. 創建可重用模組

```bash
# 用戶請求：「把 VPC 相關設定抽成模組」
#
# AI 應該：
# 1. 評估是否適合抽成模組
# 2. 創建 modules/networking/vpc/
# 3. 提供清晰的 variables 和 outputs
# 4. 撰寫模組使用範例
# 5. 更新原練習專案使用此模組
```

### 3. 問題診斷

```bash
# 用戶報告：「terraform apply 失敗」
#
# AI 應該：
# 1. 要求提供錯誤訊息
# 2. 檢查常見問題（權限、配額、命名衝突等）
# 3. 提供逐步除錯建議
# 4. 必要時要求查看相關檔案內容
```

## 與用戶溝通建議

### 使用場景範例

**場景 1**: 用戶想跳過某些階段

```
用戶: 「我想直接學 EKS」

建議回應: 「EKS 是階段 5 的內容，需要先理解 VPC、IAM、容器等概念。
建議先完成階段 1-4 的基礎練習，或至少確保您已經熟悉：
- VPC 網路架構設定
- IAM 角色和政策
- 容器基礎（ECR, ECS）

如果您已經有這些背景，我們可以直接開始 EKS 練習。」
```

**場景 2**: 用戶關心成本

```
用戶: 「這個練習會花多少錢？」

建議回應: 「這個練習的主要費用來源：
- EC2 t2.micro: 免費方案內（每月 750 小時）
- EBS 30GB: 免費方案內
- 其他資源: 基本免費

預估總費用: 如在免費方案內，應該是 $0。
練習完畢後請執行 `terraform destroy` 清理資源。」
```

**場景 3**: 用戶遇到權限問題

```
用戶: 「terraform apply 說我沒權限」

建議回應: 「請確認您的 IAM 使用者/角色具有以下權限：
- EC2: 完整權限或至少 ec2:RunInstances
- VPC: 完整權限或至少 ec2:CreateVpc, ec2:CreateSubnet
- IAM: 如需建立 IAM 角色

建議檢查：
1. 執行 `aws sts get-caller-identity` 確認身份
2. 檢查 IAM 政策是否包含所需權限
3. 如果是組織帳號，請確認是否有 SCP 限制」
```

## AI 自我檢查清單

在回應用戶前，確認：

- [ ] 回應是否符合當前學習階段？
- [ ] 程式碼是否遵循專案命名規範？
- [ ] 是否提醒潛在的成本問題？
- [ ] 是否強調學習重點而非只是給答案？
- [ ] 文件是否完整且易讀？
- [ ] 是否提供清理資源的指令？
- [ ] 安全設定是否遵循最佳實踐？

## 參考資源

- [Terraform AWS Provider 文件](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS 架構中心](https://aws.amazon.com/architecture/)
- [Terraform 最佳實踐](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
- [AWS 定價計算器](https://calculator.aws/)

## 更新記錄

- 2026-02-03: 初始版本建立
