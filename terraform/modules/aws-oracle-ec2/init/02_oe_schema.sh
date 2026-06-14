#!/bin/bash
# 安裝 Oracle OE (Order Entry) sample schema
# 包含：customers, orders, order_items, product_information, inventories, warehouses

set -e

TMPDIR=/tmp/sample-schemas-oe
mkdir -p "$TMPDIR"
cd "$TMPDIR"

FILES=(
  "oe_install.sql"
  "oe_create.sql"
  "oe_popul.sql"
  "oe_p_lob.sql"
  "oe_cre_idx.sql"
  "oe_code.sql"
  "oe_comnt.sql"
)

BASE_URL="https://raw.githubusercontent.com/oracle/db-sample-schemas/main/order_entry"

echo ">>> Downloading Oracle OE sample schema..."
for f in "${FILES[@]}"; do
  curl -sL "$BASE_URL/$f" -o "$f" || echo "Warning: $f not found, skipping"
done

echo ">>> Installing OE schema into XEPDB1..."
sqlplus -s sys/"$ORACLE_PASSWORD"@//localhost/XEPDB1 as sysdba <<EOF
CREATE USER oe IDENTIFIED BY "$ORACLE_PASSWORD" QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE TO oe;
GRANT CREATE VIEW, CREATE SEQUENCE, CREATE SYNONYM TO oe;

ALTER SESSION SET CURRENT_SCHEMA = oe;
@$TMPDIR/oe_create.sql
@$TMPDIR/oe_popul.sql
@$TMPDIR/oe_cre_idx.sql
@$TMPDIR/oe_code.sql

EXIT;
EOF

echo ">>> OE schema installed. Tables: customers, orders, order_items, product_information, inventories, warehouses"
rm -rf "$TMPDIR"
