# OCI Labs - AI 協作規範

OCI 學習 labs，對標 AWS（`../labs/`）與 Azure（`../azure-labs/`）。
共通規範請見上層 [`../agents.md`](../agents.md)；本文件只記錄 **OCI 專屬** 的差異與護欄。

## 帳號背景

- **方案**：Pay As You Go（PAYG），**不是**純 Free Tier
- **Credit**：400 SGD，**2026-11-22 到期**；到期後超出 Always Free 的資源直接扣信用卡
- **Home region**：`ap-singapore-1`（只有 **1 個 AD**）
- **認證**：`~/.oci/config` 的 `[DEFAULT]`（API key），Provider 不寫入任何金鑰

## 目錄

```
oci-labs/
├── AGENTS.md
├── O-01-base-database/   # Base Database（對比 RDS Oracle）
├── O-02-autonomous-database/ # Autonomous Database（對比 Aurora）
└── O-06-oke-cluster/     # OKE（對比 EKS）
```

## 學習路線（2026-11-12 規劃，優先消耗 credit）

| 編號 | Lab | 對標 AWS | 預計 | 狀態 |
|---|---|---|---|---|
| O-01 | Base Database | RDS Oracle | — | ✅ 已建 |
| O-02 | Autonomous Database（付費 ECPU、Data Guard、private endpoint） | Aurora | 11/12–13 | 🚧 骨架已建（TODO 待填） |
| O-03 | ADB + AI Vector Search（疊在 O-02 上） | Aurora + pgvector | 11/13–14 | 規劃 |
| O-04 | MySQL HeatWave（HA + HeatWave cluster） | RDS MySQL | 11/14–15 | 規劃 |
| O-05 | GoldenGate + Base DB | DMS | 11/15–16 | 規劃 |
| O-06 | OKE | EKS | — | ✅ 已建 |
| O-07 | LB + WAF + Bastion | ALB + WAF + SSM | 11/16–17 | 規劃 |
| O-08 | GPU 實例（短時間） | EC2 GPU | 11/17–18 | 規劃 |
| O-09 | Exadata Exascale | — | 11/18–21 | 待確認 Singapore 可用與最低配置 |

- 11/21 全部 `terraform destroy`，再用 `oci` CLI 檢查殘留資源（cluster / LB / DB system）。
- Exadata 傳統 Dedicated Infrastructure（Quarter Rack 約 SGD 20–40/hr）**不玩**，只玩 Exascale（按 ECPU 計費）。
- 單價與 Singapore 供應需開 lab 前用 Cost Estimator 確認。

長駐、已存在的資源在 `../envs/oci-*`（governance / vcn / linux），**lab 不要修改它們**。

## 護欄（務必遵守）

1. **絕不 destroy／replace `envs/oci-linux` 的 A1 實例**。Singapore 的 A1 常缺貨，刪了可能開不回來。
2. **A1 Always Free 額度是全帳號共用**：總額 4 OCPU / 24 GB，`oci-linux` 已用 2 OCPU / 12 GB（2026-11 擴大過）。
   所有 lab 的 A1 合計最多 **2 OCPU / 12 GB**；開 A1 資源前先用 `oci limits resource-availability get` 確認實際用量；Block volume 合計 200 GB（已用 47 GB）。
   帳號的 Service Limit 顯示 249 OCPU 可用 → **沒有硬性上限，超過就計費**。新增 A1 資源必須加 variable validation。
3. **付費資源註明到期日**：README 的成本章節要標示是否在 Always Free 內，以及「11/22 前必須 destroy」。
4. **K8s 建立的資源 Terraform 管不到**：`Service type=LoadBalancer` 會建 OCI LB。README 的「結束」章節必須先寫 `kubectl delete svc`，再 `terraform destroy`。
5. **IAM／Budget 屬 tenancy 層級**，由 `../envs/oci-governance` 管理；lab 內不要建 policy／group。
6. **對外 IP 變動**要同步更新：`envs/oci-vcn` 的 `ssh_allowed_cidr`、`envs/oci-governance` 的 `home_ip_cidr`，以及各 lab 的 `allowed_cidr`。

## OCI 慣例

- **每個資源都要 `compartment_id`**，lab 一律放 `homelab`（取自 `envs/oci-governance` output）。
- Tags 用 `freeform_tags = local.common_tags`（`Project / Environment / ManagedBy / Lab`）。OCI 會自動加 `Oracle-Tags.*` defined tags，import 的資源需 `ignore_changes = [defined_tags]`。
- 查 Availability Domain 用 **tenancy** OCID，不是 compartment。
- Security List 與 NSG 規則是**疊加**的，兩邊都要限制才有效。
- Identity Domains 的 group 用 `oci_identity_domains_group`，不是 `oci_identity_group`。
- `terraform.tfvars`、`*.tfstate`、`kubeconfig` 不進 Git。

## 驗證用 CLI

```bash
oci iam region list                                     # 認證是否正常
oci limits resource-availability get --service-name compute \
  --limit-name standard-a1-core-count -c <tenancy> \
  --availability-domain <AD>                            # A1 額度
oci ce cluster list -c <compartment> --lifecycle-state ACTIVE   # 是否有殘留叢集
oci lb load-balancer list -c <compartment>              # 是否有殘留 LB
```

> Windows Git Bash 下 OCI CLI 會印出 `Get-Acl` 錯誤，是檢查設定檔權限失敗，**不影響結果**，可忽略。

## 更新記錄

- 2026-11-12: O-01 改為 private subnet + OCI Bastion（新增 TODO 4/5，移除 IGW / 公網 IP）
- 2026-11-12: 重新編號（O-02→O-01、O-04→O-06）並加入學習路線 O-02~O-09
- 2026-11-12: 新增 O-02-autonomous-database 骨架（TODO 填空式，單價待 Cost Estimator 確認）
- 2026-11-09: 新增 O-01-base-database（原 O-02）（無 Always Free，全部耗 credit，11/22 前 destroy）
- 2026-11-06: 建立 oci-labs 與 O-06-oke-cluster（原 O-04）
