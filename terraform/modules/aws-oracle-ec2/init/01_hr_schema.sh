#!/bin/bash
# 安裝 Oracle HR (Human Resources) sample schema
# 執行身份：container 內，Oracle 初始化完成後自動執行
#
# 修復：
#   - 移除 set -e，避免任一步驟失敗中斷所有後續動作
#   - SQL 檔由 Host 端預下載並掛載至 /opt/oracle-sql/hr
#   - Step 1: sysdba via local IPC 建立帳號（不走 TCP，不受 Listener 影響）
#   - Step 2: 改以 hr 身份執行 DDL，資料表才會建在 hr Schema 下

SQL_DIR=/opt/oracle-sql/hr

echo ">>> [HR] Waiting for XEPDB1 to be ready..."
for i in $(seq 1 20); do
  sqlplus -s / as sysdba <<'CHECK' 2>/dev/null | grep -q "OPEN" && break
  SET HEADING OFF FEEDBACK OFF PAGESIZE 0
  SELECT open_mode FROM v\$pdbs WHERE name='XEPDB1';
  EXIT;
CHECK
  echo "    attempt $i: XEPDB1 not ready yet, waiting 15s..."
  sleep 15
done

echo ">>> [HR] Step 1: Creating hr user (sysdba / local IPC)..."
sqlplus -s / as sysdba <<SQL
ALTER SESSION SET CONTAINER = XEPDB1;
BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
CREATE USER hr IDENTIFIED BY "$ORACLE_PASSWORD" QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW TO hr;
ALTER USER hr DEFAULT TABLESPACE USERS;
EXIT;
SQL

echo ">>> [HR] Step 2: Creating schema objects as hr user..."
sqlplus -s hr/"$ORACLE_PASSWORD"@//localhost/XEPDB1 <<SQL
WHENEVER SQLERROR CONTINUE
@$SQL_DIR/hr_create.sql
@$SQL_DIR/hr_popul.sql
@$SQL_DIR/hr_cre_idx.sql
@$SQL_DIR/hr_code.sql
@$SQL_DIR/hr_comnt.sql
EXIT;
SQL

echo ">>> [HR] Done. Verifying tables..."
sqlplus -s hr/"$ORACLE_PASSWORD"@//localhost/XEPDB1 <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT table_name FROM user_tables ORDER BY table_name;
EXIT;
SQL
