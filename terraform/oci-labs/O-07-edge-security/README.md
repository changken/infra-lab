# O-07：LB + WAF + Network Firewall + Bastion（邊界安全）

> Internet-facing Load Balancer 掛 WAF，backend 在 private subnet，出站流量經 Network Firewall 檢查，管理用 Bastion `MANAGED_SSH`。對標 AWS 的 ALB + WAF + Network Firewall + SSM Session Manager。
>
> 💰 **成本等級：🔴 危險**（Network Firewall 按小時計費且最貴；沒有任何 Always Free 資源，除了 LB 10 Mbps 以外的部分）
>
> ⏰ **credit 2026-11-22 到期**。練完當天 `terraform destroy`，到期後仍存在會直接扣信用卡。
>
> ⚠️ Network Firewall 的單價與額度**還沒查**，開 TODO 3 前先用 Cost Estimator 與 `oci limits` 確認。

## 學習目標

- 建 Flexible Load Balancer（backend set、health check、listener），理解與 ALB Target Group 的對應
- 用 WAF 擋 SQLi／XSS 與 rate limit，並驗證前後差異
- 用 Network Firewall 對 backend 出站做目的地控制，比較它與 NSG 的能力差距
- 用 Bastion `MANAGED_SSH` 連進 private instance（與 O-01／O-04／O-05 的 port forwarding 對照）
- 理解 NSG 與 Security List 疊加、route table 如何把流量導進 firewall

## 架構

```
你的電腦（allowed_cidr）
   │ HTTP/HTTPS                          │ Bastion MANAGED_SSH（session ≤ 3 小時）
   ▼                                     ▼
┌──────────── VCN（10.34.0.0/16）────────────────────────────────────┐
│ public subnet   [LB + WAF]                                         │
│                      │ :80                                         │
│ private subnet  [backend ×N, nginx] ── 出站 ─► NAT（預設）         │
│                                          └──► Network Firewall     │
│ private subnet  [Network Firewall]            （TODO 3 改路由）    │
└────────────────────────────────────────────────────────────────────┘
```

## 你要做的事

TODO 1～5 已填完（`terraform validate` 通過，**尚未 plan／apply**）；網路層與 backend instance（nginx）原本就提供。

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | LB + backend set + backend + listener | health check；`is_private`；NSG |
| 2 | `main.tf` | WAF policy + firewall 掛到 LB | OWASP protection capability、rate limit |
| 3 | `main.tf` | Network Firewall + policy + 路由 | 出站只放行指定目的地；route table 改指 firewall |
| 4 | `main.tf` | Bastion + `MANAGED_SSH` session | 用 instance OCID，不是 IP；Bastion plugin 已啟用 |
| 5 | `outputs.tf` | LB IP、SSH 指令 | 不放私鑰 |

> `variables.tf` 的 validation 已擋住 `allowed_cidr = 0.0.0.0/0`、`backend_count` 超出 1～2。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填 compartment / tenancy OCID、你的 IP、ssh_public_key
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

建議的 apply 順序（控制費用）：

1. TODO 1（LB）→ 驗證 round-robin 與 health check
2. TODO 4（Bastion）→ SSH 進 backend
3. TODO 2（`enable_waf = true`）→ 跑 `scripts/attack_probe.sh`，前後各一次
4. TODO 3（`enable_network_firewall = true`）→ 量完立刻改回 `false` 並 apply，或直接 destroy

## 驗證方式

```bash
LB=$(terraform output -raw lb_public_ip)       # TODO 5 完成後
for i in $(seq 1 6); do curl -s http://$LB/; done   # 應看到兩台 backend 的 hostname 輪流出現

./scripts/attack_probe.sh $LB                  # WAF 前後各跑一次

# LB 後端健康
oci lb backend-health get --load-balancer-id <lb_id> --backend-set-name <set> --backend-name <ip:80>

# Network Firewall 生效（在 backend 內執行，經 Bastion SSH）
curl -sI --max-time 5 https://oracle.com | head -1      # 放行
curl -sI --max-time 5 https://example.com | head -1     # 應被擋（逾時）
```

驗證紀錄（做完請自己填）：

| 項目 | 結果 |
|------|------|
| LB round-robin 有輪流 | ✅ 連打 6 次，backend-1／backend-2 交替出現；backend set health 為 OK（2026-11-20） |
| 停一台 backend 後 LB 標 CRITICAL 的秒數 | |
| SQLi／XSS 請求在 WAF 前／後的回應碼 | 前：200／200；後：**403／403**（正常請求維持 200） |
| rate limit 觸發門檻與回應碼 | 規則 60 秒 50 次；連打 100 次 → 49 個 200、51 個 403（WAF 前為 100 個 200） |
| Network Firewall 建立時間 | 未測（額度：`premium-nfw-max-count` 2、`premium-nfp-max-count` 50，夠用） |
| 被擋的出站請求現象（逾時／reset） | |
| Network Firewall 每小時費用 | 未查（CLI 查不到單價，需用 Cost Estimator） |

補充：

- Bastion plugin 在 instance 建好後約 10 分鐘才會 `RUNNING`；太早建 `MANAGED_SSH` session 會得到 `Bastion plugin must be in the RUNNING state`，等 plugin 起來再 apply 一次即可。
- instance 重建後 session 會跟著重建，同樣要等 plugin。

## 結束

```bash
# 若做了 TODO 3：先把 route table 改回 NAT 並 apply，再 destroy，避免 backend 斷線
terraform destroy -auto-approve

oci lb load-balancer list -c <compartment_id>
oci network-firewall network-firewall-collection list-network-firewalls -c <compartment_id>
oci bastion bastion list -c <compartment_id> --bastion-lifecycle-state ACTIVE
```

## 成本

| 資源 | 是否 Always Free | 備註 |
|------|------------------|------|
| Flexible Load Balancer（10 Mbps） | ⚠️ 一個 10 Mbps LB 在 Always Free 內，帳號是否已佔用請查 | 超出按小時計費 |
| WAF | ❌ | 依 policy 與請求量計費；單價待確認 |
| Network Firewall | ❌ 💰💰 | 按小時計費，本 lab 最貴；單價待 Cost Estimator 確認 |
| backend `VM.Standard.E4.Flex` 1 OCPU / 8 GB ×2 | ❌ | A1 額度已被 `envs/oci-linux` 用滿，不可用 |
| NAT Gateway / VCN / subnet / NSG / Bastion | ✅ 免費 | |

⏰ **11/22 前必須 destroy**。

## 卡關提示

| 症狀 | 常見原因 |
|------|---------|
| `availability_domain` 錯誤 | 查 AD 要用 tenancy OCID，不是 compartment |
| `data.oci_core_images` 找不到映像 | shape 與映像不相容；確認 `backend_shape` |
| curl LB 逾時 | LB NSG 只開給 `allowed_cidr`；你的 IP 變了要更新；Security List 也要放行 |
| LB backend 一直 CRITICAL | health check 的 port／path 錯，或 backend 的 firewalld／NSG 沒放 80 |
| nginx 沒起來 | cloud-init 需要出站（NAT）裝套件；看 `/var/log/cloud-init-output.log` |
| Bastion session 建立失敗（`plugin must be in the RUNNING state`） | plugin 約需 10 分鐘才 Running，用 `oci instance-agent plugin list` 確認後再 apply；instance 需有出站到 OCI 服務 |
| 改路由後 SSH／nginx 裝套件全斷 | 出站被 Network Firewall 規則擋掉，先檢查 firewall 的 security rule |
| WAF 擋不到請求 | 規則 key／version 錯，或 WAF 尚未關聯到 LB；一個 LB 只能掛一個 WAF |
| rate limit 沒觸發 | LB 後的 client IP 判斷、規則動作與計數視窗要重新檢查 |
| destroy 卡在 subnet | Network Firewall 或 LB 尚未刪完，等它們先消失 |
