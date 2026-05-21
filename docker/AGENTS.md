# AI Agent 協作指南 (Docker 篇)

本文檔為 AI 助手提供 `docker/` 目錄下的環境背景與協作規範，確保本地開發資料庫環境的一致性與安全性。

## 目錄結構

```
docker/
├── oracle-db/           # Oracle Database Free (23c)
├── oracle-xe/           # Oracle Database Express Edition (21c)
├── postgresql-db/       # PostgreSQL 18
└── portainer-root/      # Portainer 管理介面
```

## AI 協作規範

### 1. 環境一致性
- **Image 版本**: 必須固定 Image 版本（如 `postgres:18-alpine`），避免使用 `latest`。
- **連接埠管理**: 確保不同資料庫間的 Host Port 不衝突。
    - Oracle Free: `15211`
    - Oracle XE: `15212`
    - PostgreSQL: `15432`
- **Volume 命名**: 統一使用 `external: true` 的具名 Volume，避免容器刪除時遺失資料。

### 2. 安全規範
- **密鑰處理**: 絕對不要將 `.env` 檔案提交至版本控制。
- **範例檔案**: 修改配置時，同步更新 `.env.example`。
- **密碼強度**: 協助用戶產生範例密碼時，應具備基本強度。

### 3. 操作指令建議
- **啟動**: 優先推薦使用 `docker compose up -d`。
- **清理**: 提醒用戶 `docker compose down` 僅停止容器，若要刪除資料需手動刪除 Volume。
- **初始化**: 指導用戶將 SQL 腳本放置於各資料庫對應的 `init` 目錄中。

## 常見任務

### 新增資料庫環境
1. 參考現有的 `postgresql-db` 結構。
2. 建立 `compose.yaml`, `README.md`, `.env.example`。
3. 確保 `README.md` 包含完整的連接字串範例。

### 疑難排解
- 檢查 `docker logs <container_name>`。
- 確認 Volume 是否已事先建立：`docker volume create <volume_name>`。
- 檢查 Host Port 是否被占用。
