# Azure Virtual Desktop (AVD) 環境

> **費用等級**: 🟡 注意 (~$0.10 ~ $0.15/hr，依 VM 規格計算)  
> **作業系統**: Windows 11 Enterprise multi-session + Microsoft 365 Apps  
> **連線機制**: AVD Gateway 反向代理（零信任，無 Public IP，不需對外開放 RDP 3389 Port）

---

## 架構說明

```
你的電腦 / 瀏覽器
     │
     ▼  HTTPS (443) via AVD Gateway（Microsoft 管理）
┌─────────────────────────────────────────────────────────────┐
│  Azure Resource Group (az-avd-rg)                           │
│                                                             │
│  AVD Host Pool (az-avd-hostpool, Pooled)                    │
│    ├── AVD Workspace (az-avd-workspace)                    │
│    └── AVD App Group (az-avd-appgroup, Desktop)             │
│                                                             │
│  VNet: 10.60.0.0/16                                         │
│    └── Subnet: 10.60.1.0/24 (NSG 阻擋所有非必要 Inbound)      │
│          └── Session Host VM (Windows 11 multi-session)     │
│                - Entra ID (Azure AD) Join                   │
│                - Trusted Launch (vTPM + Secure Boot)        │
└─────────────────────────────────────────────────────────────┘
```

---

## 常用操作

### 1. 準備設定檔
```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars 填入 subscription_id 與 admin_password
```

### 2. 初始化與套用
```bash
terraform init
terraform plan
terraform apply
```

### 3. 連線桌面
- **網頁版**: 前往 [AVD Web Client](https://client.wvd.microsoft.com/arm/webclient) 並使用 Azure 帳號登入。
- **桌面版**: 開啟 Windows 內建「遠端桌面」或「Windows App」，點擊「訂閱」並登入。

### 4. 清理環境
```bash
terraform destroy
```
