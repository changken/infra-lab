#!/bin/bash
set -e

# 安裝 Docker
dnf install -y docker
systemctl enable --now docker
sleep 5

# 複製 init scripts 到 host 目錄，再 mount 進 container
mkdir -p /opt/oracle-init
cat > /opt/oracle-init/01_hr_schema.sh << 'INITSCRIPT'
#!/bin/bash
set -e
TMPDIR=/tmp/sample-schemas
mkdir -p "$TMPDIR"
cd "$TMPDIR"

echo ">>> Downloading Oracle HR sample schema..."
BASE_URL="https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources"
for f in hr_create.sql hr_popul.sql hr_cre_idx.sql hr_code.sql hr_comnt.sql; do
  curl -sL "$BASE_URL/$f" -o "$f"
done

echo ">>> Installing HR schema into XEPDB1..."
sqlplus -s sys/"$ORACLE_PASSWORD"@//localhost/XEPDB1 as sysdba <<SQL
CREATE USER hr IDENTIFIED BY "$ORACLE_PASSWORD" QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW TO hr;
ALTER SESSION SET CURRENT_SCHEMA = hr;
@$TMPDIR/hr_create.sql
@$TMPDIR/hr_popul.sql
@$TMPDIR/hr_cre_idx.sql
@$TMPDIR/hr_code.sql
@$TMPDIR/hr_comnt.sql
EXIT;
SQL

echo ">>> HR schema installed."
rm -rf "$TMPDIR"
INITSCRIPT

cat > /opt/oracle-init/02_oe_schema.sh << 'INITSCRIPT'
#!/bin/bash
set -e
TMPDIR=/tmp/sample-schemas-oe
mkdir -p "$TMPDIR"
cd "$TMPDIR"

echo ">>> Downloading Oracle OE sample schema..."
BASE_URL="https://raw.githubusercontent.com/oracle/db-sample-schemas/main/order_entry"
for f in oe_create.sql oe_popul.sql oe_cre_idx.sql oe_code.sql; do
  curl -sL "$BASE_URL/$f" -o "$f" || echo "Skipping $f"
done

echo ">>> Installing OE schema into XEPDB1..."
sqlplus -s sys/"$ORACLE_PASSWORD"@//localhost/XEPDB1 as sysdba <<SQL
CREATE USER oe IDENTIFIED BY "$ORACLE_PASSWORD" QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM TO oe;
ALTER SESSION SET CURRENT_SCHEMA = oe;
@$TMPDIR/oe_create.sql
@$TMPDIR/oe_popul.sql
@$TMPDIR/oe_cre_idx.sql
@$TMPDIR/oe_code.sql
EXIT;
SQL

echo ">>> OE schema installed."
rm -rf "$TMPDIR"
INITSCRIPT

chmod +x /opt/oracle-init/01_hr_schema.sh /opt/oracle-init/02_oe_schema.sh

# 啟動 Oracle XE 21c（21-full 才有 curl，slim 沒有）
# init scripts 在第一次初始化後自動執行（只跑一次）
docker run -d \
  --name oracle-xe \
  --restart unless-stopped \
  -p 1521:1521 \
  -p 5500:5500 \
  -e ORACLE_PASSWORD="${oracle_password}" \
  -e ORACLE_DATABASE=XEPDB1 \
  -v oracle-data:/opt/oracle/oradata \
  -v /opt/oracle-init:/container-entrypoint-initdb.d \
  gvenzl/oracle-xe:21-full

echo "Oracle XE container started."
echo "DB initialization takes ~5 minutes, sample schemas install after that."
echo "Monitor: docker logs -f oracle-xe"
