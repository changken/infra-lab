# Infra Lab - AI Agent Master Guidance

歡迎來到 **Infra Lab**。本文件為 AI 助手（Claude, Gemini 等）提供專案全局背景與導航指引。

## 專案概覽
本專案是一個綜合性的基礎設施實驗室，包含：
1.  **Docker 實驗室**: 各種本地資料庫環境（Oracle, PostgreSQL, Portainer）。
2.  **Terraform AWS 實驗室**: 從基礎 VPC/EC2 到進階 EKS/Serverless 的 AWS 學習路徑。

## 目錄與特化規範
本專案採「分權管理」，請根據你目前所在的目錄讀取更詳細的規範：

-   **`/docker/`**: 包含本地資料庫環境。請參閱 [docker/AGENTS.md](./docker/AGENTS.md)。
-   **`/terraform/`**: 包含 AWS 基礎設施代碼。請參閱 [terraform/agents.md](./terraform/agents.md)。

## 全域協作規範

### 1. 語言與溝通
-   **主要語言**: 文件、README 與溝通請使用 **繁體中文 (Traditional Chinese)**。
-   **技術術語**: 資源名稱、程式碼、技術術語維持英文。

### 2. 工程標準
-   **Git 提交**: 遵循 **Conventional Commits** (例如 `feat:`, `fix:`, `refactor:`, `docs:`)。
-   **安全第一**: 嚴格禁止 commit 任何 `.env`、`*.tfvars` 或包含密鑰、憑證的檔案。
-   **填空式教學**: 在協助用戶新增練習 (Labs) 時，優先採用 TODO 填空式結構，引導用戶思考與查詢文件，而非直接給出最終答案。

### 3. 自動載入 (Symlinks)
為了確保 AI 助手啟動時能自動讀取規範：
-   `CLAUDE.md` 與 `GEMINI.md` 透過硬連結 (Hard Link) 指向此檔案。
-   子目錄中亦有對應的連結檔案。

---
*最後更新: 2026-05-21*
