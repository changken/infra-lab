# O-04：MySQL HeatWave

> MySQL DB system（可選 HA）+ HeatWave cluster（分析加速 + in-database 向量／LLM）。對標 AWS 的 RDS MySQL（HA 對應 Multi-AZ）。
>
> 💰 **成本等級：🔴 危險**（HeatWave 節點按小時計費，HA 會讓 DB system 費用變多倍；沒有任何 Always Free 資源）
>
> ⏰ **credit 2026-11-22 到期**。練完當天 `terraform destroy`，到期後仍存在會直接扣信用卡。
>
> ⚠️ 單價、HeatWave 可掛的 shape、Singapore 是否支援 HeatWave GenAI **都還沒驗證**，開 lab 前先用 Cost Estimator 與 Console 確認。

## 學習目標

- 會建 MySQL DB system（private subnet + NSG），理解 OCI 的 MySQL 儲存與 compute 分開計費
- 理解 HA（Group Replication、跨 fault domain）與 AWS RDS Multi-AZ 的差異，並實測 failover 中斷時間
- 理解 HeatWave 的運作方式：同一個 endpoint，由 optimizer 決定查詢走 InnoDB 或 HeatWave 節點（`SECONDARY_ENGINE`／`SECONDARY_LOAD`）
- 用 `VECTOR` 型別與 HeatWave GenAI 做 embedding、向量搜尋與手刻 RAG，和 [O-03](../O-03-adb-vector-genai/) 比較
- 用 Bastion 連進 private subnet 的資料庫（與 O-02 相同的做法）

## 架構

```
你的電腦（allowed_cidr）
   │ SSH tunnel（Bastion，session 最長 3 小時）
   ▼
┌─────────────── VCN（10.32.0.0/16）─ private subnet ───────────────┐
│  MySQL DB system（單節點，或 HA 多 instance）  ◄── NSG: 3306/33060 │
│       │ 同一個 endpoint，optimizer 自動分流                       │
│       ▼                                                           │
│  HeatWave cluster（1～2 節點，可單獨開關）                         │
└───────────────────────────────────────────────────────────────────┘
```

## 你要做的事

網路層（VCN / subnet / NSG）已提供。

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | `oci_mysql_mysql_db_system` | AD 用 tenancy 查；`shape_name`、備份與 `deletion_policy` |
| 2 | `main.tf` | HA | `is_highly_available`；先看 plan 是 in-place 還是 replace |
| 3 | `main.tf` | HeatWave cluster | 💰 最貴；用 `enable_heatwave` 能單獨開關 |
| 4 | `main.tf` | Bastion + session | port forwarding；tunnel 指向哪個 endpoint |
| 5 | `outputs.tf` | 連線資訊 | 不要把密碼放進 output |
| SQL-1～4 | `sql/01_vector_search.sql` | VECTOR 欄位、embedding、搜尋 | 維度要和模型一致 |
| SQL-5～7 | `sql/02_heatwave_load.sql` | `SECONDARY_LOAD`、offload 比較 | 記錄有／無 HeatWave 的耗時 |
| SQL-8～9 | `sql/03_genai.sql` | `ML_GENERATE` 手刻 RAG | 先確認 Singapore 是否支援 |

> `variables.tf` 的 validation 已擋住 `allowed_cidr = 0.0.0.0/0`、儲存超出 50～200 GB、HeatWave 節點超出 1～2。

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

1. 只做 TODO 1（單節點，`enable_ha = false`、`enable_heatwave = false`）→ 連線驗證
2. 做 TODO 2，開 HA 量 failover → 記錄後改回 `false`
3. 做 TODO 3，開 HeatWave 做 `sql/02`、`sql/03` → **做完立刻 `enable_heatwave = false` 再 apply**

## 連線

```bash
terraform output bastion_tunnel_command   # 把 <privateKey> 換成私鑰路徑，貼上執行（會佔住終端機）
mysql -h 127.0.0.1 -P 3306 -u dbadmin -p  # 另開一個終端機
```

## 驗證方式

```bash
# DB system 狀態
oci mysql db-system get --db-system-id <db_system_id> \
  --query 'data.{state:"lifecycle-state",ha:"is-highly-available",hw:"is-heat-wave-cluster-attached"}'

# 殘留檢查（destroy 後應為空）
oci mysql db-system list -c <compartment_id> --lifecycle-state ACTIVE
oci bastion bastion list -c <compartment_id> --bastion-lifecycle-state ACTIVE
```

驗證紀錄（做完請自己填）：

| 項目 | 結果 |
|------|------|
| 單節點連線 | ✅ 經 Bastion tunnel 連線成功 |
| HA failover 中斷秒數 | |
| 聚合查詢：InnoDB 耗時 | |
| 聚合查詢：HeatWave 耗時／倍數 | 耗時未記錄；EXPLAIN 確認 `Table scan on orders in secondary engine RAPID`（已 offload）。單筆主鍵查詢走 InnoDB，不 offload |
| HeatWave GenAI 在 Singapore 可用？ | ✅ `ML_EMBED_ROW`（`multilingual-e5-small`，VECTOR(384)）與 `ML_GENERATE` 皆可執行；RAG 回答有根據文件。傳入 `model_id = mistral-7b-instruct-v1`，回應的授權聲明卻是 Llama 3.2（原因未確認） |

## 結束

```bash
terraform destroy -auto-approve
oci mysql db-system list -c <compartment_id>   # 確認沒有殘留
```

## 成本

| 資源 | 是否 Always Free | 備註 |
|------|------------------|------|
| MySQL DB system | ❌（`MySQL.Free` 不在本 lab 範圍） | 單價待 Cost Estimator 確認 |
| HA | ❌ | 費用約為單節點的多倍 |
| HeatWave 節點 | ❌ | 按小時計費，本 lab 最貴 |
| 儲存 | ❌ | 50 GB 起 |
| VCN / subnet / NSG / Bastion | ✅ 免費 | |

⏰ **11/22 前必須 destroy**。

## 卡關提示

| 症狀 | 常見原因 |
|------|---------|
| DB system 約 3 分鐘後 `FAILED`，`AuthorizationFailed`（`oci mysql work-request-error list` 才看得到） | DB system 掛了 `nsg_ids`（2026-11-20 實測：拿掉後約 9 分鐘 `ACTIVE`）。改用 subnet 的 security list 放行 3306／33060；NSG 在此 lab 只建不掛 |
| Bastion tunnel 通了但連不到 3306 | subnet 預設 security list 沒開 3306；需自訂 `oci_core_security_list`（來源 VCN CIDR）並掛到 subnet |
| `terraform apply` 被中斷後 DB system 沒進 state | 用 `oci mysql db-system delete` 手動刪，再 `terraform destroy`；殘留 lock 檔要確認沒有 terraform 行程後再刪 |
| `availability_domain` 錯誤 | 查 AD 要用 tenancy OCID，不是 compartment |
| HeatWave 建立被拒（`shapeName ... cannot be used`） | `heatwave_shape` 要用 Singapore 實測可用的值：`HeatWave.32GB`、`HeatWave.512GB`、`HeatWave.Free`（`HeatWave.256GB` 會被拒） |
| 查詢沒走 HeatWave | 表還沒 `SECONDARY_LOAD`，或查詢型態不會被 offload |
| 連不上 3306 | Bastion session 過期；NSG 只開給 VCN 內部 |
| 單節點改 HA 出現 replace | 先看 plan，不要直接 apply |
| `ML_EMBED_ROW` 不存在 | 沒有 HeatWave cluster，或該 region 不支援 HeatWave GenAI |
