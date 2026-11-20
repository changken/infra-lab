# O-05：OCI Database with PostgreSQL

> 託管 PostgreSQL DB system（可選 HA + reader endpoint），private subnet + Bastion。對標 AWS 的 RDS PostgreSQL（Multi-AZ）／Aurora PostgreSQL（reader endpoint）。
>
> 💰 **成本等級：🔴 危險**（HA 會讓 instance 費用變 3 倍；沒有任何 Always Free 資源）
>
> ⏰ **credit 2026-11-22 到期**。練完當天 `terraform destroy`，到期後仍存在會直接扣信用卡。
>
> ⚠️ 單價還沒驗證，開 lab 前先用 Cost Estimator 確認。Singapore 的 PostgreSQL 只提供 E5／E6／Standard3 shape（**沒有 E4**）；`dbsystem-count` 額度為 0，用 E5 shape 走的是 `dbsystem-e5-count`（額度 20），已 apply 驗證不會被擋。

## 學習目標

- 會建 OCI PostgreSQL DB system（private subnet + NSG），理解它與 RDS 的差異：儲存是共用分散式儲存，與 instance 分開
- 理解 HA（多 instance + 跨 AD/FD 儲存）與 RDS Multi-AZ／Aurora 的差異，並實測 failover 中斷時間
- 用 reader endpoint 做讀寫分離，量 replication lag
- 用 Bastion 連進 private subnet 的資料庫（與 O-01／O-04 相同）
- 效能線：記錄 p95 延遲與 failover 中斷時間（見驗證紀錄）

## 架構

```
你的電腦（allowed_cidr）
   │ SSH tunnel（Bastion，session 最長 3 小時）
   ▼
┌─────────────── VCN（10.33.0.0/16）─ private subnet ───────────────┐
│  Writer endpoint ──► primary instance                             │
│  Reader endpoint ──► replica ×N（instance_count > 1）  NSG: 5432  │
│                  └── 共用分散式儲存（可跨 AD/FD）                  │
└───────────────────────────────────────────────────────────────────┘
```

## 你要做的事

網路層（VCN / subnet / NSG）已提供。

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | `oci_psql_db_system` | `network_details`、`storage_details`、`credentials`；`shape` 名稱為 `PostgreSQL.VM.Standard.E5.Flex`（不含 `.2.32GB`），OCPU／GB 另用 `instance_ocpu_count`／`instance_memory_size_in_gbs` 指定 |
| 2 | `main.tf` | HA | `instance_count`、`is_regionally_durable`；先看 plan 是 in-place 還是 replace |
| 3 | `main.tf` | Reader endpoint | 讀寫分離；`instance_count = 1` 時行為？ |
| 4 | `main.tf` | Bastion + session | port forwarding；tunnel 指向 writer 或 reader |
| 5 | `outputs.tf` | 連線資訊 | 不要把密碼放進 output |
| SQL-1～4 | `sql/01_failover_probe.sql` | 探測表、failover 中斷、replication lag | 記錄時間戳 |

> `variables.tf` 的 validation 已擋住 `allowed_cidr = 0.0.0.0/0`、OCPU 超出 2～4、instance 超出 1～3。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填 compartment / tenancy OCID、你的 IP、密碼
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

建議的 apply 順序（控制費用）：

1. 只做 TODO 1（`instance_count = 1`）→ 連線驗證、跑負載測試記 p95
2. 做 TODO 2，`instance_count = 3` 量 failover → 記錄後改回 `1`
3. 做 TODO 3，開 reader endpoint 量 replication lag → 做完 destroy

## 連線

```bash
terraform output bastion_tunnel_command   # 把 <privateKey> 換成私鑰路徑，貼上執行（會佔住終端機）
psql "host=127.0.0.1 port=5432 user=dbadmin dbname=postgres sslmode=require"   # 另開終端機
```

## 驗證方式

```bash
# DB system 狀態
oci psql db-system get --db-system-id <db_system_id> \
  --query 'data.{state:"lifecycle-state",count:"instance-count",version:"db-version"}'

# 觸發 failover（HA 才有意義；--db-instance-id 可指定要切到哪個 instance，未指定由服務決定）
oci psql db-system failover --db-system-id <db_system_id> --wait-for-state SUCCEEDED

# 額度
oci limits resource-availability get --service-name postgresql \
  --limit-name dbsystem-e5-count -c <tenancy_ocid>

# 殘留檢查（destroy 後應為空）
oci psql db-system-collection list-db-systems -c <compartment_id>
oci bastion bastion list -c <compartment_id> --bastion-lifecycle-state ACTIVE
```

驗證紀錄（2026-11-20 apply 後，因 credit 11/22 到期已 `terraform destroy`，未量測的項目留空）：

| 項目 | 結果 |
|------|------|
| 單節點連線 | ✅ Bastion tunnel + DataGrip（`sslmode=require`）連線成功 |
| 單節點 pgbench p95 延遲 | 未量測 |
| HA（`instance_count = 3`）建立 | ✅ 3 個 instance 皆 ACTIVE；`is_regionally_durable = true` 被拒（Singapore 只有 1 個 AD），改 `false` + 指定 AD |
| 單節點改 HA | ⚠️ 是 replace，舊 DB 與資料會消失 |
| HA failover 中斷秒數 | 未量測 |
| reader replication lag | 未量測 |
| 對 reader 寫入的錯誤訊息 | 未量測 |
| HA 費用 ÷ 單節點費用 | 未量測（預期約 3 倍） |

## 結束

```bash
terraform destroy -auto-approve
oci psql db-system-collection list-db-systems -c <compartment_id>   # 確認沒有殘留
```

## 成本

| 資源 | 是否 Always Free | 備註 |
|------|------------------|------|
| PostgreSQL DB system instance | ❌ | 按 OCPU／GB 計費，HA ×3；單價待 Cost Estimator 確認 |
| 儲存 | ❌ | 共用儲存按容量計費 |
| VCN / subnet / NSG / Bastion | ✅ 免費 | |

⏰ **11/22 前必須 destroy**。

## 卡關提示

| 症狀 | 常見原因 |
|------|---------|
| `availability_domain` 錯誤 | 查 AD 要用 tenancy OCID，不是 compartment |
| `plan` 想 in-place 改 shape（`...E5.Flex` -> `...E5.Flex.2.32GB`） | `psql_shape` 不要帶 `.2.32GB`，規格由 `instance_ocpu_count`／`instance_memory_gbs` 指定 |
| `LimitExceeded: dbsystem-count` | 用了 Singapore 沒有的 shape（如 E4），落到額度為 0 的通用額度；改用 `oci psql shape-summary list-shapes --all` 列出的 E5 |
| 連不上 tunnel | `<privateKey>` 要換成 `ssh_public_key` 對應的私鑰，不是預設的 `~/.ssh/id_rsa` |
| 建立被拒（額度） | `dbsystem-e5-count` 或 `dbsystem-count` 為 0／不足，先用 `oci limits` 查 |
| 連不上 5432 | Bastion session 過期；NSG 只開給 VCN 內部 |
| 單節點改 HA 出現 replace | 先看 plan，不要直接 apply |
| reader 連得到但資料落後 | replication lag；用 `pg_last_xact_replay_timestamp()` 量 |
