# Docker 協作規範

`docker/README.md` 是 Compose stacks 與 Terraform tool images 的目錄索引；處理特定環境時，先讀該目錄的 README 和 Compose 設定。

## 檔案命名

- 每個 Compose stack 的預設檔名為 `compose.yaml`。
- 完整替代設定使用 `compose.<purpose>.yaml`，並在 README 記錄 `docker compose -f ...` 指令；避免使用數字序號或版本字樣等不具用途資訊的名稱。
- 範例環境檔統一使用 `.env.example`。實際 `.env` 僅供本機使用，不進版本控制；不要覆寫既有 `.env`。
- 新增或修改 image 時固定明確 tag；不要順手更新既有 image 版本。

## 資料與相容性

- Container/service name、host port、bind mount 路徑和 volume name 可能被既有資料或用戶端依賴。修改前確認影響，必要時提供遷移步驟。
- Stateful stack 使用的 volume 設定各有差異；不要假設所有 volume 都是 external，也不要未經確認就改名或刪除。
- `docker compose down` 保留資料；`docker compose down -v` 可能刪除 Compose 管理的資料 volumes。不得把刪除 volume 當成一般驗證步驟。

## 驗證與操作

- 在 stack 目錄執行 `docker compose config --quiet` 驗證設定；需要 `.env` 的 stack，先由使用者建立並填妥本機設定。
- 驗證設定不需要啟動或停止服務；除非使用者要求，不執行 `up`、`down` 或刪除 volume。
- 初始化 SQL 的掛載位置依各 stack 的 Compose 設定與 README 為準。
