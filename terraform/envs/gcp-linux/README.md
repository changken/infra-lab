# gcp-linux — GCP Compute Engine Linux VM

🟢 **費用等級：安全** — e2-micro 每帳號每月 **1 台免費**（Free Tier），超出約 **$6 USD/月**

透過 Terraform 在 GCP 台灣（`asia-east1`）建立一台 Ubuntu 24.04 VM，含 VPC Firewall Rule 設定。

## 學習目標

- 使用 GCP Terraform Provider（`hashicorp/google`）
- 理解 GCP Firewall 架構：rule 掛在 VPC 層，透過 **network tag** 套用到 VM
- 了解 GCP SSH Key 注入方式：透過 `metadata["ssh-keys"]`，格式 `<user>:<pubkey>`
- 認識 GCP Free Tier：`e2-micro`、`30GB` 磁碟、台灣 region 以外不在免費範圍

## 架構

```
你的電腦 (my_ip)
     │
     │ SSH TCP:22
     ▼
┌──────────────────────────────────────────────────────┐
│  google_compute_firewall (VPC 層)                    │
│  allow TCP:22 from my_ip                             │
│  target_tags = ["allow-ssh-from-my-ip"]              │
└───────────────────────┬──────────────────────────────┘
                        │ 僅套用到有 tag 的 VM
                        ▼
           ┌────────────────────────┐
           │  google_compute_       │
           │  instance              │
           │  Ubuntu 24.04          │
           │  e2-micro              │
           │  zone: asia-east1-b   │
           │  tag: allow-ssh-...   │
           └────────────────────────┘
```

## GCP 認證設定（擇一）

### 方式 1：gcloud CLI（推薦本機開發）
```bash
gcloud auth application-default login
```

### 方式 2：Service Account Key（CI/CD 推薦）
```bash
# 1. 在 GCP Console 建立 Service Account，賦予 Compute Admin 角色
# 2. 下載 JSON key
# 3. 設定環境變數
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
```

## 前置需求

1. 建立 GCP 專案並啟用 Compute Engine API：
   ```bash
   gcloud services enable compute.googleapis.com
   ```
2. 取得專案 ID：
   ```bash
   gcloud config get-value project
   ```
3. 確保本機有 SSH Key（`~/.ssh/id_rsa.pub`）

## 使用步驟

```bash
# 1. 複製變數檔
cp terraform.tfvars.example terraform.tfvars

# 2. 填入實際值
#    project_id     : GCP 專案 ID
#    my_ip          : curl ifconfig.me（後面加 /32）
#    ssh_public_key : cat ~/.ssh/id_rsa.pub

# 3. 格式化與初始化
terraform fmt
terraform init

# 4. 驗證與預覽
terraform validate
terraform plan

# 5. 部署
terraform apply
```

## 驗證

```bash
# 取得公網 IP
terraform output public_ip

# SSH 連線（apply 後約 20-30 秒啟動）
ssh devuser@$(terraform output -raw public_ip)

# 或使用 gcloud 指令（不需管理 SSH Key）
terraform output gcloud_ssh_command

# 確認系統資訊
uname -a
lsb_release -a
```

## 結束（避免持續計費）

```bash
terraform destroy
```

## 費用估算

| 資源 | 規格 | 費用 |
|------|------|------|
| google_compute_instance | e2-micro（0.25 vCPU / 1GB） | **Free Tier（每月 1 台）** |
| 開機磁碟 | 20GB Standard | **Free Tier（每月 30GB 以內）** |
| 公網 IP | Ephemeral | **免費**（靜態 IP 才收費） |
| google_compute_firewall | - | 免費 |
| **總計（Free Tier 內）** | | **$0 USD/月** |

> ⚠️ e2-micro Free Tier 限制：每月 1 台、僅限 `us-*` 及 `asia-east1`（台灣）、`europe-west1`。

## 常見機器類型

| machine_type | vCPU | RAM | 月費 |
|-------------|------|-----|------|
| `e2-micro` | 0.25 shared | 1 GB | Free Tier / ~$6 |
| `e2-small` | 0.5 shared | 2 GB | ~$12 |
| `e2-medium` | 1 shared | 4 GB | ~$25 |
| `n1-standard-1` | 1 | 3.75 GB | ~$25 |

## 常見 Region / Zone

| region | zone | 位置 |
|--------|------|------|
| `asia-east1` | `asia-east1-b` | 台灣彰化（Free Tier 可用）|
| `asia-northeast1` | `asia-northeast1-a` | 東京 |
| `asia-southeast1` | `asia-southeast1-b` | 新加坡 |
| `us-central1` | `us-central1-a` | 美國愛荷華（Free Tier 可用）|

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `Error: Compute Engine API not enabled` | 執行 `gcloud services enable compute.googleapis.com` |
| SSH 連線被拒 | `my_ip` 填錯、Firewall tag 未套用、或 VM 還在啟動 |
| `Error: project_id is required` | `terraform.tfvars` 未填 `project_id` |
| `Error: Permission denied` | Service Account 缺少 `roles/compute.admin` 或 `roles/compute.instanceAdmin.v1` |
| 公網 IP 為空 | `access_config {}` 區塊缺少，或 `network_interface` 設定錯誤 |
| root 登入失敗 | GCP 預設禁止 root SSH，需用 `ssh_user`（非 root）登入 |
