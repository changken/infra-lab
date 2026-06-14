#!/bin/bash
# 從 oracle/db-sample-schemas GitHub 下載並安裝 HR schema
# 執行身份：container 內，Oracle 初始化完成後自動執行

set -e

TMPDIR=/tmp/sample-schemas
mkdir -p "$TMPDIR"
cd "$TMPDIR"

echo ">>> Downloading Oracle HR sample schema..."
curl -sL "https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources/hr_install.sql" -o hr_install.sql
curl -sL "https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources/hr_create.sql" -o hr_create.sql
curl -sL "https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources/hr_popul.sql"  -o hr_popul.sql
curl -sL "https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources/hr_cre_idx.sql" -o hr_cre_idx.sql
curl -sL "https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources/hr_code.sql"   -o hr_code.sql
curl -sL "https://raw.githubusercontent.com/oracle/db-sample-schemas/main/human_resources/hr_comnt.sql"  -o hr_comnt.sql

echo ">>> Installing HR schema into XEPDB1..."
sqlplus -s sys/"$ORACLE_PASSWORD"@//localhost/XEPDB1 as sysdba <<EOF
-- 建立 HR user
CREATE USER hr IDENTIFIED BY "$ORACLE_PASSWORD" QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE TO hr;
GRANT CREATE VIEW TO hr;

-- 切換到 HR schema 執行建表/資料
ALTER SESSION SET CURRENT_SCHEMA = hr;
@$TMPDIR/hr_create.sql
@$TMPDIR/hr_popul.sql
@$TMPDIR/hr_cre_idx.sql
@$TMPDIR/hr_code.sql
@$TMPDIR/hr_comnt.sql

EXIT;
EOF

echo ">>> HR schema installed. Tables: employees, departments, jobs, locations, countries, regions, job_history"
rm -rf "$TMPDIR"
