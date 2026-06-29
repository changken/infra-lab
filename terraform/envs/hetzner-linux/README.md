# hetzner-linux — Hetzner Cloud Linux Server

🟢 **費用等級：安全** — cx22 約 **€3.79 EUR/月**（~$4 USD，按小時計費 ~€0.006/hr）

透過 Terraform 在 Hetzner Cloud 上建立一台 Ubuntu 24.04 Server，含 SSH Key 上傳與 Firewall 設定。Hetzner 是歐洲最具 CP 值的雲端服務商之一。

## 學習目標

- 使用 Hetzner Cloud Terraform Provider（`hetznercloud/hcloud`）
- 管理 `hcloud_ssh_key`、`hcloud_firewall`、`hcloud_server`
- 了解 Hetzner Firewall 特性：只需設定 inbound rules，outbound 預設全開

## 架構

```
你的電腦 (my_ip)
     │
     │ SSH TCP:22
     ▼
┌─────────────────────────────────────────┐
│  hcloud_firewall                        │
│  inbound:  TCP 22 from my_ip only       │
│  inbound:  ICMP from anywhere           │
│  outbound: 全部放行（Hetzner 預設行為） │
└──────────────────┬──────────────────────┘
                   │
                   ▼
         ┌──────────────────┐
         │  hcloud_server   │
         │  Ubuntu 24.04    │
         │  cx22            │
         │  location: sin   │
         └──────────────────┘
```

## 前置需求

1. 取得 Hetzner Cloud API Token：
   - [https://console.hetzner.cloud](https://console.hetzner.cloud) > 選擇專案 > Security > API Tokens > **Generate API Token**（選 Read & Write）
2. 確保本機有 SSH Key（`~/.ssh/id_rsa.pub`）

## 使用步驟

```bash
# 1. 複製變數檔
cp terraform.tfvars.example terraform.tfvars

# 2. 填入實際值
#    hcloud_token   : Hetzner Cloud API Token
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
# 取得 IP
terraform output public_ip

# SSH 連線（apply 完成後約等 15-30 秒讓 Server 啟動）
ssh root@$(terraform output -raw public_ip)

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
| hcloud_server | cx22（2 vCPU / 4GB RAM / 40GB SSD） | ~€3.79/月 |
| hcloud_ssh_key | - | 免費 |
| hcloud_firewall | - | 免費 |
| **總計** | | **~€3.79/月（~$4 USD）** |

> Hetzner 的 cx22 是目前三家（Vultr/DO/Hetzner）CP 值最高的入門規格。

## 常見 Server 規格

| server_type | vCPU | RAM | 儲存 | 月費 |
|-------------|------|-----|------|------|
| `cx22` | 2 | 4 GB | 40 GB | ~€3.79 |
| `cx32` | 4 | 8 GB | 80 GB | ~€6.52 |
| `cx42` | 8 | 16 GB | 160 GB | ~€13.08 |
| `cax11` | 2 | 4 GB | 40 GB | ~€3.79（ARM） |

## 常見 Location

| location | 位置 |
|----------|------|
| `sin` | 新加坡（亞洲，距台灣最近） |
| `fsn1` | 德國 Falkenstein |
| `nbg1` | 德國 Nuremberg |
| `hel1` | 芬蘭 Helsinki |
| `ash` | 美國 Ashburn |
| `hil` | 美國 Hillsboro |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SSH 連線被拒 | `my_ip` 填錯，或 Server 還在啟動（等 30 秒再試） |
| `hcloud_token` 驗證失敗 | Token 未選 Write 權限，或 Token 已刪除 |
| `server_type` 不存在 | 指定 location 不支援此規格，`sin` 僅支援部分 type |
| `image` 找不到 | 映像名稱有誤，確認格式為 `ubuntu-24.04`（含連字號） |
| `server_name` 無效 | 名稱必須符合 RFC 1123（小寫英數 + 連字號，不可底線） |
