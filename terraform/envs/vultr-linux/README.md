# vultr-linux — Vultr Cloud Compute Linux VM

🟡 **費用等級：注意** — vc2-1c-1gb 約 **$6 USD/月**（按小時計費，~$0.009/hr）

透過 Terraform 在 Vultr 上開一台 Ubuntu 22.04 Cloud Compute VM，含 SSH Key 與防火牆設定。

## 學習目標

- 使用 Vultr Terraform Provider（`vultr/vultr`）
- 管理 SSH Key、Firewall Group 與 Firewall Rule
- 建立 Cloud Compute 實例並限制 SSH 存取來源

## 架構

```
你的電腦 (my_ip)
     │
     │ SSH TCP:22
     ▼
┌─────────────────────────────────┐
│  Vultr Firewall Group           │
│  Rule: TCP 22 from my_ip only  │
└────────────────┬────────────────┘
                 │
                 ▼
        ┌─────────────────┐
        │  vultr_instance │
        │  Ubuntu 22.04   │
        │  vc2-1c-1gb     │
        │  region: nrt    │
        └─────────────────┘
```

## 前置需求

1. 取得 Vultr API Key：[https://my.vultr.com/settings/#settingsapi](https://my.vultr.com/settings/#settingsapi)
2. 確保本機有 SSH Key（`~/.ssh/id_rsa.pub`）

## 使用步驟

```bash
# 1. 複製變數檔
cp terraform.tfvars.example terraform.tfvars

# 2. 填入實際值（API Key、my_ip、ssh_public_key）
#    my_ip: curl ifconfig.me
#    ssh_public_key: cat ~/.ssh/id_rsa.pub

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

# SSH 連線（apply 完成後約等 60 秒讓 VM 啟動）
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
| vultr_instance | vc2-1c-1gb（1 vCPU / 1GB RAM / 25GB SSD） | ~$6/月 |
| vultr_ssh_key | - | 免費 |
| vultr_firewall_group | - | 免費 |
| **總計** | | **~$6/月** |

> 使用完立即 `terraform destroy` 節省費用。

## 常見規格對照

| Plan | vCPU | RAM | 儲存 | 月費 |
|------|------|-----|------|------|
| `vc2-1c-1gb` | 1 | 1 GB | 25 GB | ~$6 |
| `vc2-1c-2gb` | 1 | 2 GB | 55 GB | ~$12 |
| `vc2-2c-4gb` | 2 | 4 GB | 80 GB | ~$24 |

## 常見 OS ID

| OS | ID |
|----|----|
| Ubuntu 22.04 LTS x64 | 1743 |
| Ubuntu 20.04 LTS x64 | 387 |
| Debian 12 x64 | 2136 |
| CentOS 7 x64 | 167 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SSH 連線被拒 | Firewall Rule 的 `my_ip` 填錯，或 VM 還在啟動中（等 60 秒） |
| `api_key` 驗證失敗 | API Key 未在 Vultr 控制台啟用，或 Key 填錯 |
| `plan` 不存在 | 該 region 不支援此 plan，換 region 或換 plan |
| hostname 更新後 force-replace | Vultr 設計：hostname 改變會觸發重建，請謹慎修改 |
