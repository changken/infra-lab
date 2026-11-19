--==============================================================
-- SQL 1: 從 Object Storage 載入範例資料
--==============================================================
-- 以 ADMIN 連線後執行。把 <PAR_BASE_URL> 換成：
--   terraform output -raw par_base_url
-- ⚠️ PAR 網址等同密碼。填好的版本請另存成 01_load_data.local.sql（已 gitignore），
--    不要改在這個檔案上再 commit。
--
-- 文件（搜尋 DBMS_CLOUD.COPY_DATA）:
--   https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/

--------------------------------------------------------------
-- (a) 建表（已提供）
--------------------------------------------------------------
CREATE TABLE docs (
  id      NUMBER PRIMARY KEY,
  title   VARCHAR2(200),
  content VARCHAR2(4000)
);

CREATE TABLE orders (
  order_id      NUMBER PRIMARY KEY,
  customer_name VARCHAR2(100),
  product       VARCHAR2(100),
  category      VARCHAR2(50),
  quantity      NUMBER,
  unit_price    NUMBER(10, 2),
  status        VARCHAR2(20),
  order_date    DATE
);

--------------------------------------------------------------
-- TODO SQL-1: 用 DBMS_CLOUD.COPY_DATA 載入兩個 CSV
--------------------------------------------------------------
-- 需要的參數：
--   table_name    => ???
--   file_uri_list => ???    -- <PAR_BASE_URL>（結尾已有 /）後面直接接物件名稱（data/docs.csv）
--   format        => ???    -- JSON：CSV 格式、跳過標題列；orders 還要指定日期格式
--
-- 想一想：
--   - 為什麼這裡不需要 credential_name？（對比用 API key 讀 private bucket）
--   - content 欄位內有逗號，CSV 是怎麼處理的？
--
-- 對比 AWS：aws_s3.table_import_from_s3（RDS／Aurora PostgreSQL）。

BEGIN
  -- TODO SQL-1: docs
  DBMS_CLOUD.COPY_DATA(
    table_name    => 'docs',
    file_uri_list => '<PAR_BASE_URL>data/docs.csv',
    format        => json_object('type' value 'CSV', 'skipheaders' value 1)
  );
END;
/

BEGIN
  -- TODO SQL-1: orders
  DBMS_CLOUD.COPY_DATA(
    table_name    => 'orders',
    file_uri_list => '<PAR_BASE_URL>data/orders.csv',
    format        => json_object('type' value 'CSV', 'skipheaders' value 1, 'dateformat' value 'YYYY-MM-DD')
  );
END;
/

--------------------------------------------------------------
-- 驗證
--------------------------------------------------------------
SELECT COUNT(*) AS docs_rows FROM docs;      -- 應為 12
SELECT COUNT(*) AS orders_rows FROM orders;  -- 應為 20

-- 載入失敗時，COPY_DATA 會留下 log／bad file 表，名稱可從這裡查：
SELECT table_name, status, logfile_table, badfile_table
FROM   user_load_operations
ORDER  BY id DESC;
