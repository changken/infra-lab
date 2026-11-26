# Docker 實驗環境

`docker/` 收錄 infra-lab 使用的本機 Compose stacks 與 Docker 建置環境。
每個 Compose stack 都可獨立操作，預設設定檔名稱為 `compose.yaml`。

## Compose 環境

| 目錄 | 內容 | 提供 `.env.example` |
|---|---|---:|
| [`doltgresql/`](doltgresql/) | Doltgres（相容 PostgreSQL 的資料庫） | 是 |
| [`forgejo/`](forgejo/) | Forgejo 與 PostgreSQL | 是 |
| [`minio/`](minio/) | MinIO（相容 S3 的物件儲存） | 是 |
| [`oracle-db/`](oracle-db/) | Oracle Database Free | 是 |
| [`oracle-xe/`](oracle-xe/) | Oracle Database Express Edition | 是 |
| [`portainer-root/`](portainer-root/) | Portainer CE | 否 |
| [`postgresql-db/`](postgresql-db/) | PostgreSQL 18 | 是 |
| [`postgresql-db-19/`](postgresql-db-19/) | PostgreSQL 19 RC、Adminer 與 pgAdmin | 否 |
| [`rabbitmq-valkey-garage/`](rabbitmq-valkey-garage/) | RabbitMQ、Valkey 與 Garage | 是 |
| [`redis/`](redis/) | Redis | 是 |
| [`supabase/`](supabase/) | 自架 Supabase | 是 |

部分環境有自己的 README，記載連線資訊與初始化方式。連接用戶端或修改持久化資料前，請先閱讀該環境文件。

## 啟動環境

請在對應的環境目錄執行指令：

```bash
cd docker/postgresql-db
if [ ! -e .env ]; then cp .env.example .env; fi
# 啟動前先編輯 .env，填入本機設定。
docker compose config --quiet
docker compose up -d
```

只有在環境提供 `.env.example` 且 `.env` 尚不存在時才複製範例檔；本機 `.env` 不應加入版本控制。

`docker compose down` 會停止並移除容器，但不會移除資料 volumes。`docker compose down -v` 會移除 Compose 管理的 volumes，可能造成資料遺失；清理前請先確認該環境的 volume 設定。

## 替代 Compose 設定

以下是完整的替代設定，不會自動作為 override 載入。它們可能與預設設定共用 host port、container name 或 volume；切換前請先檢查設定，並停止另一個環境。請在對應目錄明確指定檔案：

```bash
cd docker/postgresql-db
docker compose -f compose.postgres16-pgadmin.yaml up -d

cd ../portainer-root
docker compose -f compose.legacy-http.yaml up -d
```

這兩個目錄仍以 `compose.yaml` 作為預設設定。

## Terraform 工具映像

以下目錄是 Docker build context，不是 Compose stacks：

| 目錄 | 包含工具 | 從 repository root 建置 |
|---|---|---|
| [`aws-terraform/`](aws-terraform/) | Terraform、AWS CLI 與 AWS SAM build image | `docker build -t aws-tf ./docker/aws-terraform` |
| [`azure-terraform/`](azure-terraform/) | Terraform 與 Azure CLI | `docker build -t az-tf ./docker/azure-terraform` |

各目錄的 `command.sh` 提供對應的執行 alias。
