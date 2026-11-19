# O-03：ADB AI Vector Search + Generative AI

> 用 Autonomous Database 當 AI agent 的資料層：資料庫內產生 embedding、做向量搜尋，再接 OCI Generative AI 做 NL2SQL 與 RAG。對標 AWS 的 Aurora PostgreSQL + pgvector + Bedrock。
>
> 💰 **成本等級：🟡 注意**（付費 ADB 2 ECPU + GenAI 按用量；沒有任何 Always Free 資源）
>
> ⏰ **credit 2026-11-22 到期**。練完當天 `terraform destroy`，到期後仍存在會直接扣信用卡。

## 學習目標

- 理解 ADB 的 **public endpoint + ACL + TLS**（不帶 wallet），並和 [O-02](../O-02-autonomous-database/) 的 private endpoint + Bastion 比較
- 會寫 Object Storage 的 bucket、object、**pre-authenticated request（PAR）**，理解 PAR 的資安風險
- 把 ONNX embedding 模型載入資料庫，用 `VECTOR_EMBEDDING` 在 SQL 內產生向量
- 會用 `VECTOR` 型別、`VECTOR_DISTANCE`、向量索引（HNSW／IVF），看懂 exact 與 approximate search 的差別
- 用 Select AI（`DBMS_CLOUD_AI`）接 OCI Generative AI，做 NL2SQL 與手刻 RAG
- 從 NFR 角度評估：憑證放哪、模型看得到什麼、prompt injection、延遲、邏輯該放 DB 還是後端

## 架構

```
你的電腦（allowed_cidr）
   │ TLS 1521，不帶 wallet（ACL 只放你的 IP）
   ▼
┌──────────── Autonomous Database（ATP, 23ai/26ai, 2 ECPU）────────────┐
│  DOCS（content + embedding VECTOR）   ORDERS（NL2SQL 用）              │
│  DOC_MODEL（資料庫內的 ONNX embedding 模型）                           │
│  AI profile GENAI ─────────────────────────────┐                      │
└───────┬────────────────────────────────────────┼──────────────────────┘
        │ HTTPS（PAR，免憑證）                    │ HTTPS（你的 API key）
        ▼                                        ▼
  Object Storage bucket                 OCI Generative AI（Singapore）
   data/docs.csv、data/orders.csv         google.gemini-2.5-flash 等 chat 模型
   models/*.onnx
```

> Singapore 的 Generative AI 只有 chat 模型、沒有 embedding 模型（2026-11-16 以 CLI 查得），所以 embedding 在資料庫內用 ONNX 模型產生，不呼叫外部服務。

## 你要做的事

範例資料（`data/`）、建表 SQL、`locals.tf` 的上傳清單**已提供**。

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | `oci_database_autonomous_database` | `db_version`、`whitelisted_ips`、`is_mtls_connection_required`；不設 `subnet_id` |
| 2 | `main.tf` | namespace + bucket | namespace 是 tenancy 層級；bucket 不公開 |
| 3 | `main.tf` | 上傳物件 | `for_each` + `local.upload_files`；`bucket` 填名稱不是 OCID |
| 4 | `main.tf` | PAR | 唯讀、有到期日；URL 等同密碼 |
| 5 | `outputs.tf` | 連線字串、PAR 網址 | 從 `profiles` 篩出 TLS 那一筆；PAR 要 `sensitive` |
| SQL-1 | `sql/01_load_data.sql` | `DBMS_CLOUD.COPY_DATA` | 用 PAR 不需要 credential |
| SQL-2、3 | `sql/02_onnx_model.sql` | 下載並載入 ONNX 模型 | 目錄物件、`DBMS_VECTOR.LOAD_ONNX_MODEL` |
| SQL-4～6 | `sql/03_vector_search.sql` | embedding、搜尋、向量索引 | 維度要和模型一致；索引與查詢的距離函式要一致 |
| SQL-7～9 | `sql/04_genai.sql` | 憑證、AI profile、NL2SQL、RAG | 私鑰不落地；`object_list` 限制模型可見範圍 |

> `variables.tf` 的 validation 已擋住 `allowed_cidr = 0.0.0.0/0`、`db_version` 為 19c、`compute_count` 超出 2～4。

## 準備 ONNX 模型

Oracle 提供已包好 tokenizer 的 `all-MiniLM-L12-v2`（384 維，約 117 MB，以英文為主）：

1. 到 Oracle 的說明文章取得下載連結：<https://blogs.oracle.com/machinelearning+selectai/use-our-prebuilt-onnx-model-now-available-for-embedding-generation-in-oracle-database-23ai>
2. 下載 `all_MiniLM_L12_v2_augmented.zip` 並解壓。
3. 把 `all_MiniLM_L12_v2.onnx` 放進本 lab 的 `models/`（已 gitignore）。

> 這個模型對中文效果有限，所以範例文件用英文。想測中文，要另外用 OML4Py 把多語模型轉成 ONNX，不在本 lab 範圍。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填 compartment OCID、你的 IP、ADMIN 密碼
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply      # ⏳ ADB 約 5–15 分鐘；模型上傳另需數分鐘
```

> `.terraform.lock.hcl` 請一併 commit。
> 可以先不放模型就 apply（只會上傳 CSV），之後放好模型再 apply 一次補上傳。

## 驗證方式

```bash
# 1. ADB 為 AVAILABLE、版本是 23ai 以上、不要求 mTLS
oci db autonomous-database get --autonomous-database-id "$(terraform output -raw adb_id)" \
  --query 'data.{s:"lifecycle-state",ver:"db-version",mtls:"is-mtls-connection-required",acl:"whitelisted-ips"}'

# 2. bucket 內有 2 個 CSV 與 1 個模型
oci os object list --bucket-name o03-vec-bucket --query 'data[].{n:name,size:size}' --output table

# 3. PAR 讀得到（應印出 CSV 標題列）；換一個不存在的物件名稱應回 404
curl -s "$(terraform output -raw par_base_url)data/docs.csv" | head -1

# 4. 不帶 wallet 連線（SQLcl；也可用 SQL Developer 或 python-oracledb thin mode）
sql admin@"$(terraform output -raw tls_connect_string)"
```

連上後依序執行 `sql/01` → `04`（先把佔位字串換掉，另存成 `*.local.sql`）。每支腳本結尾都有驗證查詢，預期結果：

| 腳本 | 預期 |
|---|---|
| `01_load_data` | `docs` 12 筆、`orders` 20 筆 |
| `02_onnx_model` | `user_mining_models` 有 `DOC_MODEL`；維度 384 |
| `03_vector_search` | 問「How long do I have to return a product?」第一名是 `Refund policy` |
| `04_genai` | `showsql` 產出的 SQL 結果和你手寫的一致；RAG 對文件外的問題回答不知道 |

### 建議練習

- 從你自己的後端連進來：用 `tls_connect_string` 當 DSN，把 retrieval 寫成 repository、generation 寫成 application service，比較「邏輯放 DB」與「邏輯放後端」的可測試性
- 向量搜尋加一般 `WHERE` 條件，觀察執行計畫
- 換 `gemini-2.5-flash-lite` 與 `gemini-2.5-pro`，比較同一題的延遲與答案品質
- 在 `docs` 插入一筆含「忽略以上指示」的內容，觀察 RAG 的回答是否被帶走

## 結束

```bash
terraform destroy -auto-approve        # ⏳ 通常數分鐘

# 確認沒有殘留
oci db autonomous-database list -c <compartment_id> --lifecycle-state AVAILABLE
oci os bucket list -c <compartment_id> --query 'data[].name'
```

> - 載入 ADB 的模型、憑證、資料都會隨 ADB 一起刪除。
> - bucket 內若有 Terraform 以外的方式放進去的物件，destroy 會失敗，先手動刪掉。
> - 填過 PAR 網址或私鑰的 `sql/*.local.sql` 用完請刪除。

## 成本

> ⚠️ **單價尚未驗證**。開工前請到 OCI Cost Estimator 以 Singapore 試算，並把結果補到下表。
> 📌 <https://www.oracle.com/cloud/costestimator.html>

| 項目 | 規格 | 單價 | 備註 |
|------|------|------|------|
| ADB compute | 2 ECPU | 待確認 | 按 ECPU／小時；本 lab 不開 auto scaling、Data Guard |
| ADB storage | 20 GB | 待確認 | |
| Generative AI | Gemini chat，on-demand | 待確認 | 按用量；本 lab 只有幾十次呼叫 |
| Object Storage | 約 120 MB | 待確認 | 是否落在 Always Free 額度內未查 |
| 資料庫內 embedding | ONNX 模型 | 不另計費 | 吃的是 ADB 的 ECPU |

- 本 lab **不使用 Always Free**（`is_free_tier = false`），全部消耗 credit。
- ⏰ 到期日 **2026-11-22**。

## 卡關提示

| 症狀 | 常見原因 | 解決方式 |
|------|---------|---------|
| apply 報 mTLS／ACL 相關錯誤 | 關閉 mTLS 卻沒有設 ACL | `whitelisted_ips` 與 `is_mtls_connection_required = false` 要一起設 |
| `whitelisted_ips` 與 `subnet_id` 衝突 | 同時設了 public ACL 與 private endpoint | 本 lab 不設 `subnet_id`／`nsg_ids` |
| 連線逾時 | 你的對外 IP 變了，不在 ACL 內 | 更新 `allowed_cidr` 後 apply（並依 AGENTS.md 同步其他位置） |
| 連線被斷（`ORA-17800` 之類） | 用到要求 mTLS 的連線字串，或 mTLS 沒關 | 用 `tls_authentication` 為 server 端驗證的那一筆 profile |
| `Invalid index`（output 的 `[0]`） | `profiles` 篩選條件配不到任何元素 | 用 `terraform console` 看實際的 `tls_authentication`、`consumer_group` 值 |
| `ORA-00902`／`VECTOR` 不認得 | ADB 是 19c | `db_version` 要 23ai 以上 |
| 物件上傳後內容沒更新 | Terraform 不知道本機檔案變了 | 看文件的 `content_md5` |
| `COPY_DATA` 失敗 | PAR 網址貼錯、少了物件名稱，或 PAR 已過期 | 先用 `curl` 測網址；查 `user_load_operations` 指到的 log 表 |
| `COPY_DATA` 日期錯誤 | `orders.order_date` 沒指定格式 | `format` 內加日期格式 |
| `LOAD_ONNX_MODEL` 失敗 | 模型不是 augmented 版本，或檔名／目錄填錯 | 用 Oracle 提供的預建模型；`DBMS_CLOUD.LIST_FILES` 確認檔案在 |
| `ORA-51803` 之類的維度錯誤 | `VECTOR` 欄位維度和模型輸出不一致 | 以 `02_onnx_model.sql` 查到的維度為準 |
| 近似搜尋沒走向量索引 | 資料太少，或索引與查詢的距離函式不一致 | 12 筆時走全表掃描是正常的；確認兩邊距離函式相同 |
| GenAI 回 401／404（NotAuthorizedOrNotFound） | 憑證的 OCID／fingerprint 錯，或 compartment、region、model 名稱錯 | 用 `oci generative-ai model-collection list-models -c <compartment_id>` 確認模型名稱 |
| Select AI 不接受 Gemini 模型 | profile 屬性不對，或該組合在此區不支援（本 lab 未實測） | 對照 Select AI 範例頁；仍不通就把 generation 改到後端用 OCI SDK 呼叫，retrieval 仍留在 SQL |
| `showsql` 產出的 SQL 用錯表 | `object_list` 沒設，模型看到太多表 | profile 的 `object_list` 只列 `ORDERS` |

## 與 AWS 的對照

| | Aurora PostgreSQL + pgvector + Bedrock | OCI ADB + Generative AI |
|---|---|---|
| 向量型別 | `vector(n)`（extension） | `VECTOR(n, format)`（內建） |
| 距離 | `<=>`、`<->`、`<#>` 運算子 | `VECTOR_DISTANCE(..., COSINE)` |
| 索引 | HNSW、IVFFlat | HNSW（in-memory graph）、IVF（neighbor partitions） |
| 產生 embedding | 呼叫 Bedrock（`aws_bedrock.invoke_model_get_embeddings`）或在應用層 | 資料庫內 ONNX 模型（`VECTOR_EMBEDDING`），或呼叫外部服務 |
| NL2SQL | 自己接 Bedrock | Select AI（`DBMS_CLOUD_AI`） |
| 託管 RAG | Bedrock Knowledge Bases | Select AI with RAG |
| DB 呼叫模型的身分 | IAM role 掛在 cluster | API key 憑證（本 lab）或 resource principal |
| 從物件儲存載入 | `aws_s3.table_import_from_s3` | `DBMS_CLOUD.COPY_DATA` |
| 免憑證分享物件 | S3 presigned URL（單一物件） | PAR（可到 bucket 層級） |
| 對外連線控管 | VPC + SG | ACL（本 lab）或 private endpoint + NSG（O-02） |
