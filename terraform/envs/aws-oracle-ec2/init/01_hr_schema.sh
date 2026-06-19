#!/bin/bash
# 安裝 Oracle HR (Human Resources) sample schema
# 執行身份：container 內，Oracle 初始化完成後自動執行
#
# oracle-samples/db-sample-schemas 新版只有 3 個核心 SQL：
#   hr_create.sql   — 建表 + index（已合併）
#   hr_populate.sql — 資料填入（舊名 hr_popul.sql）
#   hr_code.sql     — PL/SQL procedures

SQL_DIR=/opt/oracle-sql/hr

echo ">>> [HR] Waiting for XEPDB1 to be ready..."
for i in $(seq 1 20); do
  result=$(sqlplus -s / as sysdba <<'CHECK' 2>/dev/null
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT open_mode FROM v$pdbs WHERE name='XEPDB1';
EXIT;
CHECK
)
  echo "$result" | grep -q "READ WRITE" && break
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
@$SQL_DIR/hr_populate.sql
@$SQL_DIR/hr_code.sql
EXIT;
SQL

echo ">>> [HR] Done. Verifying tables..."
sqlplus -s hr/"$ORACLE_PASSWORD"@//localhost/XEPDB1 <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT table_name FROM user_tables ORDER BY table_name;
EXIT;
SQL
