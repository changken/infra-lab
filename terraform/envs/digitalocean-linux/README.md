# digitalocean-linux — DigitalOcean Droplet Linux VM

🟡 **費用等級：注意** — s-1vcpu-1gb 約 **$6 USD/月**（按小時計費，~$0.009/hr）

透過 Terraform 在 DigitalOcean 上建立一台 Ubuntu 22.04 Droplet，含 SSH Key 上傳與 Cloud Firewall 設定。

## 學習目標

- 使用 DigitalOcean Terraform Provider（`digitalocean/digitalocean`）
- 管理 `digitalocean_ssh_key`、`digitalocean_firewall`、`digitalocean_droplet`
- 透過 Cloud Firewall inbound/outbound rule 限制 SSH 來源

## 架構

```
你的電腦 (my_ip)
     │
     │ SSH TCP:22
     ▼
┌──────────────────────────────────────────┐
│  digitalocean_firewall                   │
│  inbound:  TCP 22 from my_ip only        │
│  inbound:  ICMP from anywhere            │
│  outbound: TCP/UDP/ICMP to anywhere      │
└──────────────────┬───────────────────────┘
                   │
                   ▼
         ┌──────────────────┐
         │ digitalocean_    │
         │ droplet          │
         │ Ubuntu 22.04     │
         │ s-1vcpu-1gb      │
         │ region: sgp1     │
         └──────────────────┘
```

## 前置需求

1. 取得 DigitalOcean API Token：[https://cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens)
2. 確保本機有 SSH Key（`~/.ssh/id_rsa.pub`）
3. （選用）安裝 `doctl` CLI 方便查詢 region/size/image

## 使用步驟

```bash
# 1. 複製變數檔
cp terraform.tfvars.example terraform.tfvars

# 2. 填入實際值
#    do_token       : DigitalOcean API Token
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

# 確認月費（由 DO API 即時回傳）
terraform output price_monthly

# SSH 連線（apply 完成後約等 30-60 秒讓 Droplet 啟動）
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
| digitalocean_droplet | s-1vcpu-1gb（1 vCPU / 1GB RAM / 25GB SSD） | ~$6/月 |
| digitalocean_ssh_key | - | 免費 |
| digitalocean_firewall | - | 免費 |
| **總計** | | **~$6/月** |

> 使用完立即 `terraform destroy` 節省費用。

## 常見 Droplet 規格

| Size Slug | vCPU | RAM | 儲存 | 月費 |
|-----------|------|-----|------|------|
| `s-1vcpu-1gb` | 1 | 1 GB | 25 GB | ~$6 |
| `s-1vcpu-2gb` | 1 | 2 GB | 50 GB | ~$12 |
| `s-2vcpu-2gb` | 2 | 2 GB | 60 GB | ~$18 |
| `s-2vcpu-4gb` | 2 | 4 GB | 80 GB | ~$24 |

## 常見 Region

| Region | 位置 |
|--------|------|
| `sgp1` | 新加坡（距台灣最近） |
| `nrt1` | 東京 |
| `nyc3` | 紐約 |
| `sfo3` | 舊金山 |
| `blr1` | 班加羅爾（印度） |

## 常見 Image Slug

| Slug | 說明 |
|------|------|
| `ubuntu-22-04-x64` | Ubuntu 22.04 LTS（推薦） |
| `ubuntu-24-04-x64` | Ubuntu 24.04 LTS |
| `debian-12-x64` | Debian 12 |
| `fedora-40-x64` | Fedora 40 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SSH 連線被拒 | `my_ip` 填錯，或 Droplet 還在啟動（等 60 秒再試） |
| `do_token` 驗證失敗 | Token 未勾選 Write 權限，或 Token 已過期 |
| `size` 不存在 | 指定 region 不支援此 size，用 `doctl compute size list` 確認 |
| `image` 找不到 | Slug 錯誤，用 `doctl compute image list --public` 確認 |
| firewall 不生效 | Cloud Firewall 套用到 Droplet 需要約 10-30 秒 |
