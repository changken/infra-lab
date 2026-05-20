# Local PostgreSQL Environment

Docker Compose config for local PostgreSQL Database.

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose

## Quick Start

- Start: `docker compose up -d`
- Stop: `docker compose down`

## Connection Info

| Item     | Value          |
|----------|----------------|
| Port     | `15432` → `5432` |
| User     | `postgres`     |
| Password | `postgres123`  |
| Database | `myfirstapp`   |
| Volume   | `postgresdb_postgres-data` (named volume, external) |

- Init SQL: `./init/*.sql` (runs on first start only)

## Volume Setup

Create the named volume before first start:

```bash
docker volume create postgresdb_postgres-data
```

## Notes

- Database data is stored in a Docker named volume.
- To re-init from scratch, remove the volume (this deletes all DB data):

```bash
docker compose down
docker volume rm postgresdb_postgres-data
```
