# Local Oracle Database Environment

Docker Compose config for local Oracle Database Free (gvenzl/oracle-free).

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose

## Quick Start

- Image: `gvenzl/oracle-free:23.26.1-slim`
- Start: `docker compose up -d`
- Stop: `docker compose down`

## Connection Info

| Item         | Value              |
|--------------|--------------------|
| Port         | `15211` → `1521`   |
| Username     | `SYS`, `SYSTEM`, `PDB_ADMIN` |
| Password     | `oracle123` (or `ORACLE_PASSWORD` env var) |
| SID          | `FREE`             |
| Service Name | `FREEPDB1`         |
| Volume       | `oracledb_oracle-data` (named volume, external) |

- Init SQL: `./oracle-init/*` (runs only on first database initialization)

## Connect Strings

### SQL Developer / DBeaver

- Host: `localhost`
- Port: `15211`
- Service name: `FREEPDB1`
- Username: `system` (or `sys as sysdba`)
- Password: `oracle123`

### JDBC

```
jdbc:oracle:thin:@localhost:15211/FREEPDB1
```

### .NET (ODP.NET / Oracle.ManagedDataAccess)

```
User Id=system;Password=oracle123;Data Source=localhost:15211/FREEPDB1;
User Id=sys;Password=oracle123;DBA Privilege=SYSDBA;Data Source=localhost:15211/FREEPDB1;
```

### sqlplus

```bash
sqlplus system/oracle123@//localhost:15211/FREEPDB1
sqlplus sys/oracle123@//localhost:15211/FREEPDB1 as sysdba
```

## Volume Setup

Create the named volume before first start:

```bash
docker volume create oracledb_oracle-data
```

## References

- Docker Hub (gvenzl/oracle-free): https://hub.docker.com/r/gvenzl/oracle-free
- Oracle Docker Images: https://github.com/oracle/docker-images/tree/main/OracleDatabase

## Notes

- Database data is stored in a Docker named volume.
- To re-init from scratch, remove the volume (this deletes all DB data):

```bash
docker compose down
docker volume rm oracledb_oracle-data
```
