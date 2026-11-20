-- 連線：psql "host=127.0.0.1 port=5432 user=dbadmin dbname=postgres sslmode=require"
-- 用途：量 failover 中斷秒數、reader 的 replication lag

-- SQL-1: 建立探測表
CREATE TABLE IF NOT EXISTS probe (
  id     bigserial PRIMARY KEY,
  ts     timestamptz NOT NULL DEFAULT now(),
  writer inet DEFAULT inet_server_addr()
);

-- SQL-2: 寫入探測列
--   在另一個終端機每 0.5 秒執行一次，失敗時印出時間，失敗區間 = failover 中斷秒數：
--     while true; do
--       psql "host=127.0.0.1 port=5432 user=dbadmin dbname=postgres sslmode=require" \
--         -c "INSERT INTO probe DEFAULT VALUES;" || date +%T
--       sleep 0.5
--     done
--   failover 後 writer 欄位（inet_server_addr()）是否改變？
INSERT INTO probe DEFAULT VALUES;

-- SQL-3: 在 reader endpoint 上量 replication lag（reader 上執行）
SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;

-- 也可比對 writer 最新一筆與 reader 最新一筆的 ts：
SELECT max(ts) AS latest_visible, now() - max(ts) AS visible_age FROM probe;

-- SQL-4: 對 reader 嘗試寫入，記錄錯誤訊息（預期：cannot execute INSERT in a read-only transaction）
INSERT INTO probe DEFAULT VALUES;
