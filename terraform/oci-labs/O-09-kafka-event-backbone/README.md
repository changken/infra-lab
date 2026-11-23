# O-09：Kafka 事件骨幹（Integration Event + Transactional Outbox）

> 用 OCI Streaming 的 Kafka 相容端點建置事件 topic，從本機 producer 發布 integration event，再由 consumer 建立投影。對標 AWS MSK。
> 💰 **成本等級：🟡/🔴 待查**。本 lab 不建立 VM；OCI Streaming 的實際 Always Free 額度、Singapore 可用性與超額單價須在 apply 前確認。
>
> ⏰ OCI credit **2026-11-22 到期**。若使用任何付費額度，**2026-11-21 前必須 destroy**；不要因為 Stream Pool 已建立就假設它免費。

## 學習目標

- 建立 OCI Stream Pool 與 Stream，理解 OCI Streaming 對 Kafka topic／broker 的映射
- 使用 Kafka protocol、`SASL_SSL` 與 OCI auth token 連線，不把憑證放進 Terraform state
- 用 transactional outbox 避免「資料庫寫入成功、事件發布失敗」造成的雙寫不一致
- 理解 outbox relay 是 at-least-once，並用 `event_id` 在 consumer 做冪等處理
- 實驗 Kafka key、partition、consumer group、offset 與重送的關係

## 架構

```text
本機 SQLite
  ├─ orders
  └─ outbox ── producer / relay ── SASL_SSL ──► OCI Streaming
                                                    │ integration-events
                                                    ▼
本機 SQLite ◄── idempotent consumer ◄── Kafka consumer group
  ├─ processed_events（event_id 唯一）
  └─ order_projection
```

本 lab 用 SQLite 讓 outbox 模式可以在單機演練；正式系統應讓業務資料與 outbox table 位於同一個資料庫交易中。此練習不宣稱 exactly-once：broker ACK 後、outbox 標記前若程序崩潰，事件可能重送，consumer 必須冪等。

## 檔案

| 檔案 | 說明 |
|---|---|
| `main.tf` | Stream Pool 與 Kafka 相容設定、integration event Stream |
| `variables.tf` | OCI region、compartment、partition 與 retention |
| `src/producer.py` | 訂單／outbox 原子寫入與事件 relay |
| `src/consumer.py` | 事件去重、更新 projection、提交 offset |
| `src/env.example` | 本機 Kafka 連線環境變數範例（不含真實憑證） |

## 實作內容與學習檢查

程式碼中的 TODO 已填入可執行的基礎實作。連線 OCI 與實測仍需你在自己的帳號完成。

| 項目 | 狀態 | 學習檢查 |
|---|---|---|
| Stream Pool / Stream | ✅ Terraform 已設定 1 partition、24 小時 retention，並關閉自動建立 topic | 為什麼 topic 由 Terraform 管理時要關閉自動建立？增加 partitions 有何取捨？ |
| Order + outbox | ✅ 同一個 SQLite transaction 寫入 | 若兩筆寫入分開 commit，可能出現什麼不一致？ |
| Outbox relay | ✅ 等待 Kafka ACK 後才標記 published，使用 `aggregate_id` 作 key | ACK 後、標記前 crash 為什麼仍會重送？ |
| Consumer projection | ✅ `event_id` 唯一鍵去重，並在同一交易更新 projection | 如何避免重複事件重複產生業務效果？ |
| Kafka offset | ✅ DB transaction 成功後才 commit offset | 若先 commit offset 再寫 DB，crash 時會怎樣？ |

## 前置檢查

**在建立資源前先做：**

1. 在 OCI Console 確認 `ap-singapore-1` 可建立 Kafka 相容的 Stream Pool。
2. 查 Streaming service limits／quota，確認帳號有足夠額度。
3. 用 OCI Cost Estimator 確認 Stream Pool、partition、保留時間與訊息流量的費用，確認 Always Free 額度是否適用於此帳號。
4. 若無法確認免費額度或超額單價，先不要 `terraform apply`。

## 建立 OCI 資源

```bash
cp terraform.tfvars.example terraform.tfvars  # 填 homelab compartment OCID
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

確認 plan 只會建立本 lab 的 Stream Pool 與 Stream。不要把 OCI auth token 放到 `terraform.tfvars`；token 不需要 Terraform 管理。

```bash
terraform output
```

到 OCI Console 的 Stream Pool → **Kafka Connection Settings** 取得 bootstrap server 與服務提供的 Kafka SASL username 格式。建立專用 OCI auth token 作為 SASL password；不要將 token 寫入 Git、Terraform state 或 shell history。

## 本機 producer / consumer

```bash
cd src
python -m venv .venv
source .venv/Scripts/activate  # Windows Git Bash；Linux/macOS 請改用 .venv/bin/activate
pip install -r requirements.txt
cp env.example .env
```

填好 `.env` 後，在終端機載入環境變數（以下為 Git Bash）：

```bash
set -a
source .env
set +a
```

開兩個終端機：

```bash
# 終端機 A：持續消費並更新本機 projection
python consumer.py

# 終端機 B：建立一筆 order，relay outbox event
python producer.py
```

應看到 consumer 收到 `OrderCreated`。重跑 producer 會產生新的 order；也可在程式中模擬「送出成功但尚未標記 published」後重試，確認 consumer 不會重複套用同一 `event_id`。

## 驗證與實驗紀錄

| 實驗 | 結果 |
|---|---|
| Stream Pool / Stream lifecycle state | |
| producer 發布到 consumer 的端到端延遲 | |
| 同一 `aggregate_id` 的事件順序 | |
| 不同 consumer group 是否各自收到完整事件 | |
| 重送相同 `event_id` 是否只更新一次 projection | |
| DB commit 前／後終止 consumer，重啟後的結果 | |
| 目前 partition 數與 retention 設定 | |
| 實際費用／Always Free 額度依據 | |

## 結束

```bash
# 先停止 producer / consumer
terraform destroy -auto-approve
```

在 OCI Console 確認 Stream 與 Stream Pool 都已刪除。SQLite 資料庫只存在本機 `src/`，確認不需要後再手動刪除 `src/o09-events.db`。

## 成本

| 資源 | Always Free 狀態 | 成本注意事項 |
|---|---|---|
| OCI Streaming Stream Pool / partitions / 儲存與傳輸 | **apply 前自行確認** | 額度與計價受帳號、region、partition、流量及 retention 影響；不要假設免費 |
| 本機 SQLite / Python client | 不使用 OCI 資源 | 不建 VM、VCN 或 Bastion |

⏰ PAYG credit **2026-11-22 到期**。如果查不到明確的 Always Free 適用條件及費用，視為付費服務；最晚 **2026-11-21** destroy，避免 credit 到期後扣款。

## 卡關提示

| 症狀 | 常見原因 |
|---|---|
| `terraform validate` 找不到 OCI streaming resource | 確認 provider lock/version，執行 `terraform init -upgrade` 前先檢查版本差異 |
| `LimitExceeded` 或 quota error | Stream Pool／partition 額度不足；到 OCI Limits 確認服務額度 |
| Kafka client `SASL authentication failed` | Console 的 Kafka username 格式錯、token 過期，或把登入密碼當成 auth token |
| `Topic ... does not exist` | Terraform Stream 名稱與 `KAFKA_TOPIC` 不一致，或 Stream 尚未 ACTIVE |
| TLS／連線 timeout | bootstrap server region 不符、網路代理限制，或端點抄錯 |
| consumer 重啟後看到舊事件 | `auto_offset_reset=earliest` 對尚無 offset 的 group 會從最早事件讀取；已提交 offset 的 group 行為不同 |
| projection 出現重複效果 | 去重與 projection 更新未放在同一 DB transaction，或 offset 提交順序錯誤 |
