# AI Agent 協作指南 — aws-k3s 模組

本文件為 AI 助手（Claude、Gemini 等）提供此模組的背景與協作規範。
Claude Code 透過 `CLAUDE.md`（hard link）自動載入，Gemini CLI 透過 `GEMINI.md`（hard link）自動載入。

## 模組概覽

**模組名稱**: aws-k3s (Multi-Cloud K3s Lab)
**用途**: 個人學習與實驗用的多雲 K3s 開發環境
**特性**: 同時在 **Azure VM** 與 **AWS EC2** 部署 K3s，透過 **Tailscale VPN** 做安全遠端管理
**注意**: 這不是填空式 Lab，而是可長期使用的個人參考模組

## 目錄結構

```
aws-k3s/
├── agents.md                    # AI 協作指南（CLAUDE.md / GEMINI.md 為 hard link）
├── CLAUDE.md                    # → agents.md（Claude Code 自動載入）
├── GEMINI.md                    # → agents.md（Gemini CLI 自動載入）
├── main.tf                      # Terraform Cloud + Azure 全部資源
├── aws.tf                       # AWS VPC / EC2 / SG 等資源
├── variables.tf                 # 共用與雲端專屬變數
├── outputs.tf                   # 輸出值（含 next_steps 操作指引）
├── user-data-cp.sh              # Control plane cloud-init（Tailscale + K3s server + SSM write）
├── user-data-worker.sh          # Worker node cloud-init（Tailscale + SSM poll + k3s agent）
├── user-data-azure.sh           # Azure cloud-init（Tailscale + K3s）
├── terraform.tfvars.example     # 變數範例（可公開）
├── .terraform.lock.hcl          # Provider 版本鎖定（已提交）
└── docs/
    └── SETUP_GUIDE.md           # 詳細建置記錄
```

## 架構

```
Internet
  │
  ├─ Azure japaneast ─────────────────────┐
  │    Standard_B2s (2vCPU/4GB)           │
  │    Ubuntu 24.04 LTS                   │
  │    VNet: 10.0.0.0/16                  │
  │    [無公開 SSH port]                   │
  │                                       │
  └─ AWS us-east-1 ───────────────────────┤
       t3.medium (2vCPU/4GB)             │
       Ubuntu 24.04 LTS                  │
       VPC: 10.1.0.0/16                  │
       [無公開 SSH port]                  │
                                         │
         ← Tailscale Mesh VPN ──────────►│
         (兩個獨立 K3s 叢集互連)
```

## 核心設計原則

| 原則 | 說明 |
|------|------|
| **Tailscale First** | 無公開 SSH；所有存取均透過 Tailscale VPN |
| **IMDSv2 強制** | `http_tokens = "required"`，防止 SSRF 攻擊 |
| **加密 Volume** | AWS root volume 強制加密 |
| **Secure Boot** | Azure VM 啟用 Trusted Launch（`secure_boot_enabled = true`） |
| **Terraform Cloud** | State 存於 Terraform Cloud，Local execution mode |

## 費用概估

| 資源 | 費用 |
|------|------|
| Azure Standard_B2s | ~$0.042/hr (~$30/月) |
| AWS CP (t3.medium) | ~$0.0416/hr |
| AWS Worker × 2 (t3.small) | ~$0.0416/hr（合計） |
| AWS EIP（開機中） | 免費 |
| **AWS 合計（開機中）** | **~$0.083/hr** |
| **全部合計（開機中）** | **~$0.125/hr (~$90/月)** ⚠️ |

> **注意**：3 節點 AWS 叢集（$0.083/hr）加上 Azure（$0.042/hr）總計約 **$90/月**，遠超 $48/月 預算上限。
> 不使用時務必透過 `az vm deallocate` / `aws ec2 stop-instances` 停止全部 VM 節省費用。

## 關機/開機（節省費用）

```bash
# Azure
az vm deallocate --resource-group my-k3s-lab-rg --name my-k3s-vm
az vm start --resource-group my-k3s-lab-rg --name my-k3s-vm

# AWS（停止全部 3 台）
aws ec2 stop-instances --instance-ids \
  $(terraform output -raw aws_instance_id) \
  $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ')
aws ec2 start-instances --instance-ids \
  $(terraform output -raw aws_instance_id) \
  $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ')
```

## 關鍵變數

| 變數 | 必填 | 說明 |
|------|------|------|
| `tailscale_auth_key` | ✅ | Tailscale 自動入網金鑰（sensitive） |
| `emergency_ssh_public_key_path` | ✅ | Azure 緊急 SSH 公鑰路徑 |
| `aws_ssh_public_key_path` | ✅ | AWS 緊急 SSH 公鑰路徑（預設 `./.ssh/aws_emergency_ed25519.pub`） |
| `aws_region` | ❌ | 預設 `us-east-1` |
| `cp_instance_type` | ❌ | CP instance type，預設 `t3.medium` |
| `worker_instance_type` | ❌ | Worker instance type，預設 `t3.small` |
| `worker_count` | ❌ | Worker 數量，預設 `2` |
| `aws_availability_zone` | ❌ | 預設空（AWS 自動選）|

## AI 協作規範

### 修改此模組時的注意事項

1. **安全不降級**：不要移除 IMDSv2、volume 加密、Secure Boot 等安全設定
2. **Tailscale 優先**：不要預設開放 SSH ingress，緊急存取用 AWS Systems Manager 或 EC2 Instance Connect
3. **Provider 版本**：修改前確認 `.terraform.lock.hcl`，維持 Provider 版本一致性
4. **敏感變數**：`tailscale_auth_key` 必須保持 `sensitive = true`，不得出現在 output 裡
5. **費用提醒**：任何新增資源都應評估費用並更新本文件的費用概估

### 常見操作流程

```bash
# 初次設定
cp terraform.tfvars.example terraform.tfvars
# 填入 tailscale_auth_key 和 SSH key 路徑

# 部署
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply

# 查看後續步驟
terraform output next_steps

# 完全銷毀
terraform destroy
```

### 疑難排解

| 症狀 | 原因與解法 |
|------|-----------|
| Tailscale 連不上 | `tailscale status` 確認 VPN；檢查 AWS SG outbound 規則 |
| K3s 未自動安裝 | 查 cloud-init 日誌：`aws ec2 get-console-output --instance-id <id>` |
| kubeconfig 連不上 | 確認 `sed` 已將 `127.0.0.1` 替換為 Tailscale IP |
| `terraform plan` 顯示差異 | 檢查 AMI ID 是否有更新版本、OS Disk 名稱是否符合 |
| AWS EC2 apply 卡住 | 正常，EC2 啟動約 1-2 分鐘 |

---

*最後更新: 2026-05-31*
