# linode-linux — Linode (Akamai Cloud) Linux Instance

🟢 **費用等級：安全** — g6-nanode-1 約 **$5 USD/月**（按小時計費，~$0.0075/hr）

透過 Terraform 在 Linode（Akamai Cloud）上建立一台 Ubuntu 24.04 Instance，含 Firewall 設定。

## 學習目標

- 使用 Linode Terraform Provider（`linode/linode`）
- 了解 `linode_firewall` 的白名單機制：`inbound_policy = "DROP"` + 明確 ACCEPT 規則
- 理解 Linode 特有設計：SSH Key 直接傳入 `authorized_keys`，無需獨立 SSH Key resource

## 架構

```
你的電腦 (my_ip)
     │
     │ SSH TCP:22
     ▼
┌──────────────────────────────────────────────────┐
│  linode_firewall                                 │
│  inbound_policy  = DROP  (預設拒絕所有入站)       │
│  outbound_policy = ACCEPT (預設放行所有出站)       │
│                                                  │
│  ACCEPT rule: TCP 22 from my_ip                 │
│  ACCEPT rule: ICMP from anywhere                │
└──────────────────────┬───────────────────────────┘
                       │ linodes = [instance.id]
                       ▼
            ┌────────────────────┐
            │  linode_instance   │
            │  Ubuntu 24.04      │
            │  g6-nanode-1       │
            │  region: ap-       │
            │  southeast         │
            └────────────────────┘
```

## Linode 防火牆特色

Linode 的 `linode_firewall` 採「預設政策 + 例外規則」設計，比其他雲端更直觀：

| 設定 | 說明 |
|------|------|
| `inbound_policy = "DROP"` | 預設拒絕所有入站（白名單模式） |
| `outbound_policy = "ACCEPT"` | 預設放行所有出站 |
| `inbound { action = "ACCEPT" }` | 明確允許指定流量 |

## 前置需求

1. 取得 Linode Personal Access Token：
   - [https://cloud.linode.com/profile/tokens](https://cloud.linode.com/profile/tokens) > **Create A Personal Access Token**
   - 勾選權限：**Linodes（Read/Write）**、**Firewalls（Read/Write）**
2. 確保本機有 SSH Key（`~/.ssh/id_rsa.pub`）

## 使用步驟

```bash
# 1. 複製變數檔
cp terraform.tfvars.example terraform.tfvars

# 2. 填入實際值
#    linode_token   : Linode Personal Access Token
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

# 確認規格（vCPU / RAM / 磁碟 / 流量）
terraform output specs

# SSH 連線（apply 完成後約等 30-60 秒讓 Instance 啟動）
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
| linode_instance | g6-nanode-1（1 vCPU / 1GB RAM / 25GB SSD） | ~$5/月 |
| linode_firewall | - | 免費 |
| **總計** | | **~$5/月** |

## 常見 Instance 規格

| type | vCPU | RAM | 儲存 | 月費 |
|------|------|-----|------|------|
| `g6-nanode-1` | 1 | 1 GB | 25 GB | ~$5 |
| `g6-standard-1` | 1 | 2 GB | 50 GB | ~$10 |
| `g6-standard-2` | 2 | 4 GB | 80 GB | ~$20 |

## 常見 Region

| region | 位置 |
|--------|------|
| `ap-southeast` | 新加坡（亞洲，距台灣最近） |
| `ap-south` | 孟買（印度） |
| `us-east` | 紐約 / Newark |
| `us-west` | 加州 Fremont |
| `eu-central` | 法蘭克福 |
| `eu-west` | 倫敦 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SSH 連線被拒 | `my_ip` 填錯，Firewall 未生效，或 Instance 還在啟動（等 60 秒）|
| `linode_token` 驗證失敗 | Token 未勾選 Linodes/Firewalls Read/Write 權限 |
| `type` 不支援 | 指定 region 不提供此規格，換 region 或更換 type |
| `image` 錯誤 | 格式必須是 `linode/ubuntu24.04`（含 `linode/` 前綴） |
| Firewall 套用延遲 | `linodes` 欄位關聯後，規則約需 10-30 秒生效 |
