# Local DB Environment

This repo contains Docker Compose configs for local PostgreSQL and Oracle Database.

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose

## Quick Start

### PostgreSQL 18 (Alpine)

Uses `docker-compose.yaml`.

- Start: `docker compose up -d`
- Port: `15432` -> `5432`
- User: `postgres`
- Password: `postgres123`
- Database: `myfirstapp`
- Data: `./data`
- Init SQL: `./init/*.sql` (runs on first start)

### Oracle Database Free (Latest/26ai-free)

- Version: 26ai-free(a.k.a. latest = 23.26.0.0)

Uses `compose.oracle26.yaml`.

- Start: `docker compose -f compose.oracle26.yaml up -d`
- Port: `11521` -> `1521`
- Username: `SYS, SYSTEM and PDB_ADMIN`
- SID: `FREE`
- Service Name: `FREEPDB1`
- Password: `oracle123`
- Data: `./myoradb`

## Notes

### oracle db container image: 
https://container-registry.oracle.com/ords/ocr/ba/database/free

### oracle db container build:
https://github.com/oracle/docker-images/tree/main/OracleDatabase

- The database data directories are gitignored to avoid committing large binaries.
- Remove the data folders if you want a clean re-init.
