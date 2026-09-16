#!/bin/sh
set -eu

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
SERVER="db"

if "$SQLCMD" -S "$SERVER" -U sa -P "$MSSQL_SA_PASSWORD" -C -b -d master \
  -Q "IF DB_ID(N'QL_KhachSan') IS NULL THROW 50000, 'QL_KhachSan does not exist', 1" >/dev/null 2>&1; then
  echo "QL_KhachSan already exists; skipping base database creation."
else
  echo "Creating QL_KhachSan database and base tables..."
  "$SQLCMD" -S "$SERVER" -U sa -P "$MSSQL_SA_PASSWORD" -C -b -d master \
    -i /init/sql/00_create_new_database.sql
fi

echo "Installing product views, procedures, and demo schema..."
sed 's#\$(SqlRoot)#/init/sql#g' /init/sql/01_install_views_and_procedures.sql > /tmp/01_install_views_and_procedures.sql
"$SQLCMD" -S "$SERVER" -U sa -P "$MSSQL_SA_PASSWORD" -C -b \
  -d QL_KhachSan -i /tmp/01_install_views_and_procedures.sql

echo "Database initialization completed."
