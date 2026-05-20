# Local Oracle XE Database Environment

Docker Compose config for local Oracle Database Express Edition (gvenzl/oracle-xe).

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose

## Quick Start

- Image: `gvenzl/oracle-xe:21.3.0-slim`
- Start: `docker compose up -d`
- Stop: `docker compose down`

## Connection Info

| Item         | Value              |
|--------------|--------------------|
| Port         | `15212` → `1521`   |
| Username     | `SYS`, `SYSTEM`, `PDBADMIN` |
| Password     | `oracle123` (or `ORACLE_PASSWORD` env var) |
| SID          | `XE`               |
| Service Name | `XEPDB1`           |
| Volume       | `oraclexedb_oracle-xe-data` (named volume, external) |

- Init SQL: `./oracle-init/*` (runs only on first database initialization)

## Connect Strings

### SQL Developer / DBeaver

- Host: `localhost`
- Port: `15212`
- Service name: `XEPDB1`
- Username: `system` (or `sys as sysdba`)
- Password: `oracle123`

### JDBC

```
jdbc:oracle:thin:@localhost:15212/XEPDB1
```

### .NET (ODP.NET / Oracle.ManagedDataAccess)

```
User Id=system;Password=oracle123;Data Source=localhost:15212/XEPDB1;
User Id=sys;Password=oracle123;DBA Privilege=SYSDBA;Data Source=localhost:15212/XEPDB1;
```

### sqlplus

```bash
sqlplus system/oracle123@//localhost:15212/XEPDB1
sqlplus sys/oracle123@//localhost:15212/XEPDB1 as sysdba
```

## Volume Setup

Create the named volume before first start:

```bash
docker volume create oraclexedb_oracle-xe-data
```

## References

- Docker Hub (gvenzl/oracle-xe): https://hub.docker.com/r/gvenzl/oracle-xe
- Oracle Docker Images: https://github.com/oracle/docker-images/tree/main/OracleDatabase

## oracle-free vs oracle-xe

| | oracle-free (23c) | oracle-xe (21c) |
|---|---|---|
| Folder | `oracle-db/` | `oracle-xe/` |
| Image | `gvenzl/oracle-free` | `gvenzl/oracle-xe` |
| SID | `FREE` | `XE` |
| Service Name | `FREEPDB1` | `XEPDB1` |
| Port (host) | `15211` | `15212` |

## Notes

- Database data is stored in a Docker named volume.
- To re-init from scratch, remove the volume (this deletes all DB data):

```bash
docker compose down
docker volume rm oraclexedb_oracle-xe-data
```
