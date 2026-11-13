# O-02：Autonomous Database（付費 ECPU）

> 在 OCI 建立全託管的 Autonomous Database（ATP），對標 AWS Aurora；與 [O-01 Base Database](../O-01-base-database/) 對照「自己管 DB」與「全託管 DB」的差異。
>
> 💰 **成本等級：🟡 注意**（本 lab 用付費 ECPU，不用 Always Free，才玩得到 auto scaling、Data Guard 等功能）
>
> ⏰ **credit 2026-11-22 到期**。練完當天 `terraform destroy`，到期後仍存在會直接扣信用卡。

## 學習目標

- 理解 ADB 與 Base Database 的差異：沒有 OS 存取、自動 patch／備份／調校
- 會寫 `oci_database_autonomous_database`，理解 ECPU 計價與 `is_free_tier = false`
- 理解 **private endpoint（VCN + NSG）**：ADB 沒有公網 IP，連線一律走 Bastion tunnel
- 理解 **mTLS（wallet）vs TLS** 連線，以及 `high／medium／low／tp／tpurgent` consumer group
- 體驗 auto scaling（compute／storage）與 local Data Guard
- 對比 AWS Aurora：Serverless v2 ACU、Multi-AZ、replica

## 架構

```
你的電腦（allowed_cidr）
   │  1522（mTLS，需 wallet）／1521（TLS）
   ▼
┌────────── Autonomous Database（ATP, 2 ECPU）──────────┐
│  db_name: O02ADB    consumer groups: high/medium/low/tp │
│  Private endpoint（無公網 IP，NSG 只開 VCN 內）          │
└─────────────────────────────────────────────────────────┘

（TODO 4 進階：改成 private endpoint）
VCN 10.31.0.0/16 ── subnet 10.31.10.0/24（無公網 IP）── NSG（1521／1522 只開 VCN 內）
```

## 你要做的事

網路層（VCN／subnet／NSG／NSG rule）**已提供**，只有 TODO 4 才會用到：

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | `oci_database_autonomous_database` | `compute_model`、`is_free_tier`、`license_model` |
| 2 | `main.tf` | Auto scaling | compute 與 storage 是兩個獨立開關 |
| 3 | `main.tf` | Local Data Guard | 會多一份 standby 計費；Singapore 單 AD |
| 4 | `main.tf` | Private endpoint | `subnet_id`、`nsg_ids`；不要設 `whitelisted_ips`；你的電腦連不進去，要有跳板 |
| 5 | `main.tf` | 下載 Wallet | `generate_type`、wallet 含憑證不可 commit |
| 6 | `outputs.tf` | 連線字串 | 從 `connection_strings` 找 profile；想想 mTLS 與 TLS 的 port |
| 7 | `main.tf` | Bastion + port-forwarding session | 連進 private endpoint 的跳板；Bastion 本身免費 |
| 8 | `outputs.tf` | Bastion tunnel 指令 | 從 session 的 `ssh_metadata` 找現成指令 |

> `variables.tf` 的 validation 已擋住 `allowed_cidr = 0.0.0.0/0`，以及 `compute_count` 超出 2～8。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填 compartment OCID、你的 IP、兩組密碼
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply      # ⏳ 約 5–15 分鐘
```

> `.terraform.lock.hcl` 請一併 commit。

## 驗證方式

```bash
# 1. 狀態應為 AVAILABLE
oci db autonomous-database list -c <compartment_id> \
  --query 'data[].{n:"display-name",s:"lifecycle-state",ecpu:"compute-count"}'

# 2. 確認不是 Always Free
oci db autonomous-database get --autonomous-database-id <adb_ocid> \
  --query 'data."is-free-tier"'

# 3. 用 wallet 連線（解壓 wallet zip 後）
export TNS_ADMIN=<wallet 目錄>
sqlplus admin/<密碼>@o02adb_high <<'SQL'
select sys_context('USERENV','SERVICE_NAME') from dual;
select banner_full from v$version;
SQL

# 4. 觀察 auto scaling／Data Guard（開啟後）
oci db autonomous-database get --autonomous-database-id <adb_ocid> \
  --query 'data.{scale:"is-auto-scaling-enabled",dg:"is-local-data-guard-enabled"}'
```

## 連線到 private endpoint

ADB 沒有公網 IP，需透過 Bastion（TODO 7）開 tunnel：

```
你的電腦 127.0.0.1:1522 ──SSH tunnel──> Bastion ──> ADB private IP:1522
```

### 步驟 1：開 tunnel

```bash
# 取得 tunnel 指令（TODO 8），把 <privateKey> 換成你的私鑰，放著不要關
terraform output -raw bastion_tunnel_command
```

### 步驟 2：讓主機名稱與憑證吻合（hosts 對應）

ADB 的 TLS 憑證只簽給 `*.adb.<region>.oraclecloud.com` 這類名稱，直接連 `localhost` 會被 JDBC driver 擋下（`ORA-17965`）。做法是把 ADB 的真實 FQDN 指到本機：

```bash
# 查 FQDN（格式類似 <label>.adb.ap-singapore-1.oraclecloud.com，以實際輸出為準）
terraform console   # 輸入 oci_database_autonomous_database.this.private_endpoint
```

用**系統管理員權限**編輯 hosts（Windows：`C:\Windows\System32\drivers\etc\hosts`），加一行：

```
127.0.0.1  <上面查到的 FQDN>
```

> - 萬用字元憑證只匹配一層，FQDN 前面只能有一個標籤；不符時看錯誤訊息列出的 SAN。
> - **練完請刪掉這行**，否則平常連到同名主機會被導到 localhost。
> - 想快速繞過可在連線描述的 `description` 內加 `(security=(ssl_server_dn_match=no))`，但等於不驗證對方身分，只適合本機練習。

### 步驟 3：選擇 mTLS 或 TLS

ADB 預設 `is_mtls_connection_required = true`：1522 只接受帶客戶端憑證（wallet）的連線，沒帶會在握手時被斷線（`ORA-17800`）。

| 方式 | 做法 | 備註 |
|---|---|---|
| **TLS（GUI 建議）** | ADB 設 `is_mtls_connection_required = false`，連線描述用 `tls_authentication` 為 `SERVER` 的那一筆，host 填步驟 2 的 FQDN、port 1522 | 不需要 wallet；`profiles` 的實際欄位值請以 `terraform console` 輸出為準 |
| **mTLS（wallet）** | 下載 wallet（TODO 5）解壓，編輯 `tnsnames.ora` 把 host 改成步驟 2 的 FQDN，設 `TNS_ADMIN` | GUI 的 JDBC driver 是否能直接讀 `cwallet.sso` 視版本而定，可能需要額外 jar |

> `high`／`medium`／`low` 只是 `tnsnames.ora` 的 alias，**不能直接當 service name 填進 GUI**；GUI 要填完整的 service name 或整段連線描述。

```bash
# mTLS + sqlplus 範例
export TNS_ADMIN=<wallet 目錄>
sqlplus admin@o02adb_high
```

### 常見錯誤對照

| 錯誤 | 原因 | 解法 |
|---|---|---|
| `ORA-17800`（Got minus one from a read call） | ADB 要求 mTLS，連線沒帶 wallet，被直接斷線；tunnel 本身是通的 | 改 TLS（`is_mtls_connection_required = false`），或帶 wallet |
| `ORA-17965`（主機名稱與憑證 CN／SAN 不符） | 連的是 `localhost`，憑證不是簽給它 | 做步驟 2 的 hosts 對應 |
| tunnel 連上又斷 | Bastion session 到期（上限 3 小時），或 allow list 沒含你的 IP | 重建 session（見下方），確認 `allowed_cidr` |

> - Bastion 的 `client_cidr_block_allow_list` 要放你的對外 IP；IP 變了要同步更新。
> - 不要為了連線去改 `envs/oci-vcn`／`envs/oci-linux`（它們在不同 VCN）。

### Bastion session 到期後重建

Session 存活時間為 `session_ttl_in_seconds`（本 lab 設 10800 秒＝3 小時）。bastion 的 `max_session_ttl_in_seconds` 是上限，3 小時是我記得的最大值，**未查證**，超過時 apply 會被 API 拒絕。session 無法延長，到期只能重建，**不需要動 ADB**：

```bash
terraform apply -replace=oci_bastion_session.this
terraform output -raw bastion_tunnel_command   # session OCID 變了，要拿新的 tunnel 指令並重開舊終端
```

hosts 對應與 GUI 設定不用改（FQDN 與 port 都沒變）。

### 建議練習

- 用不同 consumer group（`high` vs `low`）跑同一支查詢，觀察併行度差異
- 在 Console 做一次 clone，對比 RDS／Aurora 的 snapshot restore
- 開啟 Data Guard 後做一次 switchover，量測中斷時間
- 之後 O-03 會直接疊在這個 ADB 上做 AI Vector Search，**可以先不 destroy**（但仍要在 11/22 前處理）

## 結束

```bash
terraform destroy -auto-approve        # ⏳ 通常數分鐘

# 確認沒有殘留
oci db autonomous-database list -c <compartment_id> --lifecycle-state AVAILABLE
oci bastion bastion list -c <compartment_id>
oci network vcn list -c <compartment_id> --query 'data[].{n:"display-name"}'
```

> ADB「停止」只停 compute，**儲存仍計費**，lab 結束請直接 destroy。若開了 Data Guard，standby 也會一併刪除。

### destroy 卡在 NSG：`412-PreconditionFailed ... still has vnics attached`

```
NetworkSecurityGroup ... cannot be deleted since it still has vnics attached to it
```

- **原因**：ADB 的 private endpoint 在 subnet 裡佔用 VNIC 並掛在 NSG 上。ADB（尤其含 Data Guard standby）刪除後，API 回報「已刪除」比 VNIC 實際釋放早一點，Terraform 緊接著刪 NSG 就撞上時間差。**不是模板的 bug**，不需要改程式。
- **處理**：等 2～3 分鐘，確認 ADB 是 `TERMINATED` 後**直接重跑** `terraform destroy`，剩下的 NSG 與 VCN 就會被刪掉。
  ```bash
  terraform state list      # 此時通常只剩 NSG、VCN
  terraform destroy -auto-approve
  ```
- 若重跑仍失敗，查是否還有 VNIC 掛在該 NSG：`oci network nsg vnics list --nsg-id <nsg_ocid>`（空輸出代表已清空，但也可能是查詢失敗，請搭配 Console 確認）。

## 成本

> ⚠️ **單價尚未驗證**。請開工前到 OCI Cost Estimator 以 Singapore、ATP、ECPU、License Included 試算，並把結果補到下表。
> 📌 <https://www.oracle.com/cloud/costestimator.html>

| 項目 | 規格 | 單價 | 備註 |
|------|------|------|------|
| ADB compute | 2 ECPU（預設） | 待確認 | 按 ECPU／小時 |
| ADB storage | 預設 20 GB | 待確認 | 實際最小值以 Console 為準 |
| Auto scaling | 開啟時最多 3 倍 ECPU | 待確認 | 只在實際擴展時多計費 |
| Local Data Guard | standby | 待確認 | 約等於再加一份 compute／storage |
| VCN／subnet／NSG | — | 免費 | |

- 本 lab **不使用 Always Free**（`is_free_tier = false`），全部消耗 credit。
- ADB 建立快（約 5–15 分鐘），適合當天 apply + destroy。
- ⏰ 到期日 **2026-11-22**。

## 卡關提示

| 症狀 | 常見原因 | 解決方式 |
|------|---------|---------|
| `LimitExceeded` | ECPU 或 ADB 數量超過 service limit | 用 `oci limits resource-availability get --service-name database ...` 確認 |
| `400-InvalidParameter`（密碼） | `admin_password` 不符規則 | 12–30 字元，需含大寫、小寫、數字，不可含雙引號與 `admin` |
| `whitelisted_ips` 與 `subnet_id` 衝突 | ACL 是 public endpoint 的做法，與 private endpoint 互斥 | 本 lab 不設 `whitelisted_ips` |
| tunnel 連不上／逾時 | 你的 IP 變了，Bastion allow list 沒更新 | 確認對外 IP 並更新 `allowed_cidr`（同時依 AGENTS.md 同步其他位置），重建 session |
| private endpoint 下本機連不上 | ADB 沒有公網 IP | 走 TODO 7 的 Bastion tunnel，連 `localhost:1522` |
| Bastion tunnel 連上又斷 | session 到期，或 `client_cidr_block_allow_list` 沒包含你的 IP | 重建 session，確認 IP |
| `Bastion name` 報錯 | 名稱含連字號等不允許字元 | Bastion `name` 只用英數 |
| `ORA-28759`／wallet 錯誤 | `TNS_ADMIN` 未指向 wallet 目錄 | 解壓 wallet zip，檢查 `sqlnet.ora` 的 `WALLET_LOCATION` |
| `compute_count`／`data_storage_size` 欄位報錯 | 欄位名稱用錯（`in_tbs` vs `in_gb`） | 對照文件，ECPU 制用 `data_storage_size_in_gb` |
| apply 後 `plan` 一直有差異 | `admin_password` 等欄位 provider 不回傳 | `lifecycle { ignore_changes = [admin_password] }` |
| `destroy` 卡住（NSG `still has vnics attached`） | ADB 正在 TERMINATING，或 private endpoint 的 VNIC 尚未釋放 | 等 2～3 分鐘再重跑，詳見「結束」章節 |

## 與 AWS Aurora 的對照

| | Aurora PostgreSQL（Serverless v2） | OCI Autonomous Database |
|---|---|---|
| 存取 OS | ❌ | ❌（與 O-01 Base DB 不同） |
| 計價 | ACU／小時 + 儲存 + I/O | ECPU／小時 + 儲存 |
| 自動擴展 | min／max ACU | auto scaling 最多 3 倍 ECPU |
| 備援 | Multi-AZ／replica | local Data Guard（Singapore 單 AD） |
| 連線安全 | TLS／IAM auth | mTLS（wallet） |
| 網路 | VPC + SG | private endpoint + NSG（本 lab 不用 public endpoint） |
