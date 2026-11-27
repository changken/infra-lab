# Vultr Tailscale Exit Node

使用 OpenTofu 在 Vultr 建立 Ubuntu VM，透過 cloud-init 安裝並設定 Tailscale exit node。Cloud-init 是從 repo 的 `scripts/cloud-init-config.yml` 改成可由 OpenTofu 插入 hostname 與 auth key 的範本；原始 YAML 保持不變。

## 會建立的資源

- 一台 Vultr Cloud Compute instance
- 一個 Vultr Firewall Group
- 可選的 UDP/41641 IPv4/IPv6 防火牆規則

預設不開放公網 SSH/22。Tailscale SSH 只供 tailnet 內使用。預設不開放 UDP/41641；Tailscale 仍可使用 DERP 中繼連線，若要嘗試直接連線，可在確認網路需求後啟用該規則。

## 預設值

| 設定 | 預設值 |
|---|---|
| Region | `nrt`（東京） |
| Plan | `vc2-1c-1gb`（1 vCPU、1 GB RAM） |
| OS | `1743`（Ubuntu 22.04 LTS x64） |
| IPv6 | 啟用 |
| UDP/41641 | 關閉 |
| Backups | 關閉 |

`region`、`plan`、`os_id` 和 `hostname` 都可以在 `terraform.tfvars` 調整。更改 Vultr hostname 會重建 instance。

## 憑證

Vultr provider 直接呼叫 Vultr API，不需要 Vultr CLI。請在目前的 PowerShell 工作階段設定 Vultr API key 與 Tailscale auth key：

```powershell
$env:VULTR_API_KEY = "<Vultr API key>"
$env:TF_VAR_tailscale_auth_key = "<Tailscale auth key>"
```

兩個 key 是不同憑證。Tailscale key 請使用一次性、**非 ephemeral** 的 auth key；exit node 是長時間運作的 server，ephemeral node 在離線後會自動從 tailnet 移除。若使用 tag，請先確認 tailnet policy 已允許該 tag。此範本不會修改 tailnet policy，也不會自動核准 exit node。

`sensitive = true` 只會遮蔽一般 CLI 輸出。Tailscale key 被渲染進 Vultr `user_data`，因此仍可能出現在 OpenTofu state、saved plan 和 Vultr 端的 user-data 記錄中。請使用一次性 key，保護 state/plan，並勿提交憑證或真實的 `terraform.tfvars`。

## 使用步驟

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，設定本次要用的 region、plan、OS 與 hostname

tofu init
tofu fmt
tofu validate
```

建立 plan 前，先到 [Vultr 官方定價頁](https://www.vultr.com/pricing/)確認所選 region/plan 的費率。Provider 在 plan/apply 時可能呼叫 Vultr API；apply 會建立持續計費的 VM。檢查費用與 plan 內容後，再自行執行：

```powershell
tofu plan -out=tfplan
tofu apply tfplan
```

不要把 `tfplan` 或 OpenTofu state 提交到 Git。實例建立後，在 Tailscale Admin Console 手動核准這台裝置為 exit node，並確認 tailnet 的 access policy 允許預期的使用者使用它。

## 驗證與清理

```powershell
tofu output public_ipv4
tofu output instance_status
```

使用完畢後，檢查 destroy plan 並刪除資源，避免 VM 繼續計費：

```powershell
tofu plan -destroy
tofu destroy
```

## 費用估算

預設 `vc2-1c-1gb` 的估算約 **US$5–6/月**（約 **US$0.007–0.009/小時**，24 小時約 **US$0.17–0.22**），依 Vultr region 而異。此估算不含超額流量或日後啟用的備份等付費項目。Vultr 說明不同資料中心的價格可能不同，建立前請以官方定價頁面及所選 region 的實際方案價格為準。

## 參考

- [Vultr Terraform provider](https://registry.terraform.io/providers/vultr/vultr/latest/docs)
- [vultr_instance resource](https://registry.terraform.io/providers/vultr/vultr/latest/docs/resources/instance)
- [Vultr Firewall Rule resource](https://registry.terraform.io/providers/vultr/vultr/latest/docs/resources/firewall_rule)
- [Tailscale auth keys](https://tailscale.com/docs/features/access-control/auth-keys)
- [Tailscale exit nodes](https://tailscale.com/docs/features/exit-nodes/configure)
