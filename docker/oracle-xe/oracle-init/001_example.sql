-- Example init script for gvenzl/oracle-xe
-- Runs only on first database initialization.

ALTER SESSION SET CONTAINER=XEPDB1;

-- Put your schema init here (users/tables/grants/etc.).
-- If you use APP_USER, you can connect as that user inside a script when needed.
