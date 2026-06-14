#!/bin/bash
# =============================================================
# Oracle XE EC2 User Data Script
#
# 修復說明：
# 1. SQL 檔案在 EC2 Host 層就先下載完成，不再依賴 Container 內
#    的網路連線（避免 curl 失敗 + set -e 造成腳本中斷）
# 2. init 腳本不再有 set -e，改用明確錯誤處理
# 3. 帳號建立後，改以 hr/oe 身份執行 DDL，確保資料表
#    建在正確的 Schema 下（而非 SYS 底下）
# =============================================================
set -euxo pipefail

# ── 安裝基本工具 ──────────────────────────────────────────────
dnf install -y docker
systemctl enable --now docker
sleep 5

# ── 在 Host 端預先下載 Oracle sample schema SQL 檔 ───────────
# 這樣 Container 的 init script 就不需要對外 curl
HR_DIR=/opt/oracle-sql/hr
OE_DIR=/opt/oracle-sql/oe
mkdir -p "$HR_DIR" "$OE_DIR"

HR_BASE="https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources"
for f in hr_create.sql hr_popul.sql hr_cre_idx.sql hr_code.sql hr_comnt.sql; do
  curl -fsSL "$HR_BASE/$f" -o "$HR_DIR/$f"
done

OE_BASE="https://raw.githubusercontent.com/oracle/db-sample-schemas/main/order_entry"
for f in oe_create.sql oe_popul.sql oe_cre_idx.sql oe_code.sql oe_comnt.sql; do
  curl -fsSL "$OE_BASE/$f" -o "$OE_DIR/$f" || echo "Warning: $f not found, skipping"
done

# ── 建立 init 腳本目錄 ───────────────────────────────────────
mkdir -p /opt/oracle-init

# ── 01_hr_schema.sh ──────────────────────────────────────────
# SQL 檔已掛載於 /opt/oracle-sql/hr（Host 端預先下載）
cat > /opt/oracle-init/01_hr_schema.sh << 'INITSCRIPT'
#!/bin/bash
# 注意：不使用 set -e，避免任一步驟失敗時中斷後續所有步驟
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

echo ">>> [HR] Step 1: Creating hr user (as sysdba via local IPC)..."
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
INITSCRIPT

# ── 02_oe_schema.sh ──────────────────────────────────────────
cat > /opt/oracle-init/02_oe_schema.sh << 'INITSCRIPT'
#!/bin/bash
SQL_DIR=/opt/oracle-sql/oe

echo ">>> [OE] Step 1: Creating oe user (as sysdba via local IPC)..."
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
GRANT SELECT ON hr.countries TO oe;
GRANT SELECT ON hr.customers TO oe WITH GRANT OPTION;
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
INITSCRIPT

chmod +x /opt/oracle-init/01_hr_schema.sh /opt/oracle-init/02_oe_schema.sh

# ── 啟動 Oracle XE Container ─────────────────────────────────
# 將 SQL 檔目錄一同 mount 進 container，供 init 腳本使用
docker run -d \
  --name oracle-xe \
  --restart unless-stopped \
  -p 1521:1521 \
  -p 5500:5500 \
  -e ORACLE_PASSWORD="${oracle_password}" \
  -e ORACLE_DATABASE=XEPDB1 \
  -v oracle-data:/opt/oracle/oradata \
  -v /opt/oracle-init:/container-entrypoint-initdb.d \
  -v /opt/oracle-sql:/opt/oracle-sql:ro \
  gvenzl/oracle-xe:21-full

echo "========================================================"
echo " Oracle XE container started."
echo " DB init takes ~5 min, sample schemas install after."
echo " Monitor: docker logs -f oracle-xe"
echo "========================================================"
