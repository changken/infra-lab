# O-01：Base Database（Oracle DB System）

> 在 OCI 建立原生 Oracle Database VM（Base Database Service），對標 AWS 的 [`envs/aws-oracle-rds`](../../envs/aws-oracle-rds/)。
> 搭配前公司 11g → 19c 升版背景，熟悉 Oracle 在「自家雲」的託管型態。
>
> 💰 **成本等級：🔴 危險**（沒有 Always Free，按 ECPU + 儲存 + 授權計費）
>
> ⏰ **credit 2026-11-22 到期**。同一天 apply + destroy，不要過夜；到期後仍存在會直接扣信用卡。

## 學習目標

- 理解 Base Database 架構：DB System = 一台 VM + Grid Infrastructure/ASM 儲存 + Oracle Home + CDB/PDB
- 會寫 `oci_database_db_system`，理解 `db_home` → `database` 巢狀結構
- 理解 **ECPU 計價**、`LICENSE_INCLUDED` vs `BRING_YOUR_OWN_LICENSE`、Standard vs Enterprise Edition
- 用 data source 查 AD；理解 Singapore 只有 1 個 AD（Data Guard 只能同 AD）
- 對比 RDS Oracle：能 SSH 進 DB host（opc → oracle/grid），RDS 不行
- 實際操作 `sqlplus`、`dbcli`／`dbaascli`，並比較 CDB／PDB 與 19c／21c／23ai 差異

## 架構

```
   你的電腦（allowed_cidr）
     │ SSH tunnel：localhost:2222 → :22、localhost:1521 → :1521
     ▼
 OCI Bastion service（免費；allow list = 你的 IP）
     │ port-forwarding session ×2
     ▼
┌──────────────── VCN 10.30.0.0/16 ─────────────────────┐
│  db subnet 10.30.10.0/24（private，無公網 IP）         │
│  ┌──────────────────────────────────────────────┐     │
│  │ DB System（VM.BaseDB.x86, 4 ECPU）            │     │
│  │  ├─ CDB: ORCL                                │     │
│  │  │    └─ PDB: PDB1  ← 應用連這裡             │     │
│  │  └─ LVM / 256 GB data storage                │     │
│  └──────────────────────────────────────────────┘     │
│   Security List：不對外開 port，僅 VCN 內全通          │
└───────────────────────┬───────────────────────────────┘
              Service Gateway（免費，僅連 Oracle 服務）
```

> 沒有 Internet Gateway、沒有 NAT Gateway；唯一入口是 Bastion。

## 你要做的事

網路層（VCN / Service Gateway / Private Route Table / Security List / Private Subnet）**已提供**：

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | 查 Availability Domain | 用 **tenancy** OCID，不是 compartment |
| 2 | `main.tf` | `oci_database_db_system` | shape、ECPU、license_model、`db_home.database` 巢狀區塊 |
| 3 | `outputs.tf` | DB node private IP 與 PDB service name | private IP 與 service name 要自己找來源 |
| 4 | `main.tf` | Bastion + 兩個 port-forwarding session（22、1521） | `allowed_cidr` 放你的 IP；name 只能英數；不用 MANAGED_SSH |
| 5 | `outputs.tf` | Bastion tunnel 指令 | 從 session 的 `ssh_metadata` 取指令，替換佔位字串 |

## 此帳號的實際限制（2026-11-09 以 `oci` CLI 查得）

| 項目 | 值 |
|------|-----|
| 可用 shape | **`VM.BaseDB.x86`**（ECPU 制），最小 **4 ECPU** |
| Service limit `vm-basedb-x86-ecpu-count` | **8** |
| Service limit `vm-block-storage-gb` | 1050 GB |
| 可選版本 | 19c（19.0.0.0 ~ 19.33）、21c、23ai（23.26.x）、26ai（26.0.0.0.0）|

`variables.tf` 的 validation 已擋住 `compute_count` 超出 4～8，以及 `allowed_cidr = 0.0.0.0/0`。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填 OCID、你的 IP、SSH 公鑰、DB 密碼
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply      # ⏳ 約 30–60 分鐘
```

> `.terraform.lock.hcl` 請一併 commit。

## 驗證方式

```bash
# 1. 狀態應為 AVAILABLE
oci db system list -c <compartment_id> --query 'data[].{n:"display-name",s:"lifecycle-state"}'

# 2. 開 tunnel（各開一個終端機，會一直佔著；SSH 2222、SQL*Net 1521）
terraform output -raw ssh_tunnel_command
terraform output -raw sql_tunnel_command

# 3. 另開終端機，SSH 進 DB host（使用者 opc）
ssh -i <private_key> -p 2222 opc@localhost

# 在 host 上切 oracle 看 listener 與 DB
sudo su - oracle
lsnrctl status
sqlplus / as sysdba <<'SQL'
select name, open_mode, cdb from v$database;
show pdbs
select banner_full from v$version;
SQL

# 4. 從你的電腦連 PDB（走 tunnel）
sqlplus system/<密碼>@//localhost:1521/<pdb_service_name>
```

> Bastion session 有存活時間（`session_ttl_in_seconds`），到期 tunnel 會斷，需重建 session（`terraform apply -replace=...`）。

### 建議練習（時間有限，挑著做）

- `alter session set container = PDB1;` 建 user、tablespace，載入 HR 範例 schema
- `dbaascli database getDetails`／`dbcli list-databases`：體驗 OCI 的 DB 管理 CLI
- 手動 `dbaascli` 做備份、PDB clone；比較與 RDS 的 snapshot
- 在 11g 與 19c 差異上做功課：non-CDB → CDB/PDB、`SEC_CASE_SENSITIVE_LOGON`、密碼大小寫

## 結束

```bash
terraform destroy -auto-approve        # ⏳ 約 10–20 分鐘

# 確認沒有殘留
oci db system list -c <compartment_id> --lifecycle-state AVAILABLE
oci network vcn list -c <compartment_id> --query 'data[].{n:"display-name"}'
```

> 若 `db_backup_config.auto_backup_enabled = true`，備份會留在 Object Storage 並持續計費，destroy 後請檢查並刪除。

## 成本

| 項目 | 規格 | 費用 |
|------|------|------|
| Compute infrastructure（B112724） | 4 ECPU | US$0.0251 /ECPU/hr → **≈ US$0.10/hr** |
| 授權：Enterprise **High Performance**（B112727） | 4 ECPU，License Included | US$0.2218 /ECPU/hr → **≈ US$0.89/hr** |
| Database storage（B111584） | 試算以 **717 GB** 計（見下方說明） | US$0.12 /GB/月 → **≈ US$86/月** |
| 自動備份 | 預設關閉 | 開啟會多一筆 Object Storage |
| Bastion service | session 數量有上限，無用量計費 | 免費 |
| VCN / Service Gateway / Security List | — | 免費 |

### 實際試算：Enterprise High Performance、4 ECPU、跑 11 天（264 小時）

| 項目 | 金額 |
|------|------|
| Storage（717 GB × $0.12，試算以整月計） | $86.04 |
| Compute（4 × 264 × $0.0251） | $26.51 |
| EE High Performance 授權（4 × 264 × $0.2218） | $234.22 |
| **試算合計** | **US$346.77** |

### Edition 比較（4 ECPU、11 天 / 264 小時、storage 717 GB 以整月計）

| Edition | 授權單價 /ECPU/hr | 授權 11 天 | 合計（含 compute $26.51、storage $86.04） | 每天運轉（不含 storage） |
|---------|------------------|-----------|------------------------------------------|------------------------|
| **Standard**（B112725） | $0.0538 | $56.81 | **US$169.36** | ≈ US$7.6 |
| **Enterprise**（B112726） | $0.1075 | $113.52 | **US$226.07** | ≈ US$12.7 |
| **Enterprise High Performance**（B112727） | $0.2218 | $234.22 | **US$346.77** | ≈ US$23.7 |

> Enterprise 的授權費約為 High Performance 的一半（$0.1075 vs $0.2218）。Enterprise 已含 Data Guard 等基本 EE 功能；Partitioning、Tuning Pack 這類選項才需要 High Performance。

- High Performance 運轉成本約 **US$0.99/hr ≈ US$23.7/天**，其中授權費佔約 90%。
- Storage 試算是整月價；實際若按小時比例計，11 天約 US$31，總額約 US$290（待實際帳單確認）。
- 你選 256 GB data，但試算是 717 GB，推測是含 recovery／系統儲存的總配置量，請在 Console 建立畫面確認實際配置。

> ⚠️ 本 lab **沒有任何 Always Free 資源**，全部消耗 credit。**授權 Edition 是最大成本因子**；Standard Edition 授權費遠低於 Enterprise High Performance，若只想練 SQL／DBA 基本功，用 `STANDARD_EDITION`（預設值）即可。
> ⚠️ 若跑到 11/22，EE-HP 會吃掉幾乎整個 credit（400 SGD），且其他 lab（如 OKE）也會用到。建議只開 1～2 天。
> 📌 單價取自 2026-11-11 的 OCI Cost Estimator 試算，定價可能變動，apply 前請再確認：<https://www.oracle.com/cloud/costestimator.html>
> ⏰ 到期日 **2026-11-22**。

## 卡關提示

| 症狀 | 常見原因 | 解決方式 |
|------|---------|---------|
| `LimitExceeded` | ECPU 超過 8，或 `vm-block-storage-gb` | 先 `oci limits resource-availability get --service-name database --limit-name vm-basedb-x86-ecpu-count ...` 確認額度 |
| `Out of host capacity` | Singapore 只有 1 個 AD，當前可用實體機不足 | 稍後重試，或調降至最小 4 ECPU |
| `shape` 不支援 | 此帳號只有 `VM.BaseDB.x86` | 舊的 `VM.Standard2.*`／`E4.Flex` 在 DB 服務已不開放 |
| `400-CannotParseRequest`（密碼問題） | 密碼不符 Oracle 嚴格複雜度規則，長度超出 30 字元或字元非法 | 長度必須為 **9–30 字元**；必須同時包含大小寫字母、數字；特殊字元**僅允許 `_`、`-`、`#` 且至少 2 個**（不可用 `@`、`$` 等）；不可含 `sys`、`system`、`oracle`。 |
| `400-CannotParseRequest`（缺少 compute_model） | 設定了 `compute_count` 但未宣告 `compute_model` | 官方規定使用 `compute_count` 時必須同時指定 `compute_model = "ECPU"`。 |
| `400-InvalidParameter`（LVM 儲存方案） | `VM.BaseDB.x86` 未指定儲存管理方式（預設 ASM 遭拒） | 加上 `db_system_options { storage_management = "LVM" }`，此 Shape 僅支援 LVM。 |
| `hostname` 錯誤 | 主機名稱長度 > 12 字元 | ≤ 12 字元，限小寫英數，不可連字號開頭（例如直接用 `var.name_prefix`，避免 `${var.name_prefix}-db` 破表）。 |
| `Reference to undeclared resource` / 查無公網 IP | DB System 資源本身只提供 `private_ip` | 需先用 `data "oci_database_db_nodes"` 查節點，再用 `data "oci_core_vnic"` 查出 `public_ip_address`。 |
| tunnel 連不上／逾時 | 你的 IP 變了，Bastion allow list 沒更新 | 確認對外 IP，更新 `allowed_cidr`（依 AGENTS.md 同步其他位置）後 apply |
| tunnel 連上又斷 | Bastion session 到期 | 重建 session；必要時調 `session_ttl_in_seconds`（不可超過 bastion 的 `max_session_ttl_in_seconds`） |
| `Bastion name` 報錯 | 名稱含連字號等不允許字元 | `name` 只用英數（`replace(var.name_prefix, "-", "")`） |
| SSH tunnel 通但 sqlplus 連不上 | service name 錯，或 1521 的 session 沒開 | 確認為 `<pdb>.<db_domain>`（`oci_database_db_system.this.domain`），且 sql tunnel 正在跑 |
| 想從外網直接連 DB | DB 在 private subnet，沒有公網 IP | 走 Bastion tunnel，不要為了方便改回 public subnet |
| `apply` 後 `plan` 一直有差異 | `admin_password`／`db_home` 巢狀欄位 provider 不回傳 | 使用 `lifecycle { ignore_changes = [db_home[0].database[0].admin_password] }`。 |
| `destroy` 卡在刪 subnet／VCN | DB System 尚在 TERMINATING | OCI 需等待 DB System 完全終止釋放 VNIC，稍候重跑即可。 |
| 想開 Data Guard | 需 Enterprise Edition 且 Singapore 單 AD（同 AD 備援） | 不在本 lab 範圍。 |

## 與 AWS RDS Oracle 的對照

| | RDS Oracle SE2 | OCI Base Database |
|---|---|---|
| 存取 OS | ❌ 不能 SSH | ✅ SSH 進 host（opc → oracle/grid）|
| 計價 | instance 小時 + 授權（含於價內）| ECPU 小時 + 授權 + 儲存 |
| CDB/PDB | 單一 DB（可用 Multitenant 選項）| 預設 CDB + PDB |
| 備份 | 自動 snapshot | 可選自動備份到 Object Storage／手動 RMAN |
| 版本管理 | RDS patch／minor version | `dbaascli` patch、Release Update |
| 高可用 | Multi-AZ | Data Guard／RAC（Enterprise）|
