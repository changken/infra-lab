#!/bin/bash
# 安裝 Oracle OE (Order Entry) sample schema
# 執行身份：container 內，Oracle 初始化完成後自動執行
#
# 修復：
#   - 移除 set -e，避免任一步驟失敗中斷所有後續動作
#   - SQL 檔由 Host 端預下載並掛載至 /opt/oracle-sql/oe
#   - Step 1: sysdba via local IPC 建立帳號（不走 TCP，不受 Listener 影響）
#   - Step 2: 改以 oe 身份執行 DDL，資料表才會建在 oe Schema 下
#   - OE 依賴 HR.countries，所以授予必要的 GRANT

SQL_DIR=/opt/oracle-sql/oe

echo ">>> [OE] Step 1: Creating oe user (sysdba / local IPC)..."
sqlplus -s / as sysdba <<SQL
ALTER SESSION SET CONTAINER = XEPDB1;
BEGIN
  EXECUTE IMMEDIATE 'DROP USER oe CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
CREATE USER oe IDENTIFIED BY "$ORACLE_PASSWORD" QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM TO oe;
ALTER USER oe DEFAULT TABLESPACE USERS;
-- OE schema 的 COUNTRIES 表資料來自 HR，需要讀取 HR.COUNTRIES
GRANT SELECT ON hr.countries TO oe;
EXIT;
SQL

echo ">>> [OE] Step 2: Creating schema objects as oe user..."
sqlplus -s oe/"$ORACLE_PASSWORD"@//localhost/XEPDB1 <<SQL
WHENEVER SQLERROR CONTINUE
@$SQL_DIR/oe_create.sql
@$SQL_DIR/oe_popul.sql
@$SQL_DIR/oe_cre_idx.sql
@$SQL_DIR/oe_code.sql
EXIT;
SQL

echo ">>> [OE] Done. Verifying tables..."
sqlplus -s oe/"$ORACLE_PASSWORD"@//localhost/XEPDB1 <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT table_name FROM user_tables ORDER BY table_name;
EXIT;
SQL
