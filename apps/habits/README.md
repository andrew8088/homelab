# habits

Metabase + Postgres for habit tracking.

- **Metabase** at `https://habits.<tailnet>.ts.net` (Tailscale Ingress).
- **Postgres** reachable on the tailnet at `habits-db.<tailnet>.ts.net:5432` for direct writes from your laptop.

## Databases and roles

One Postgres instance, two databases:

- `habits` — your data. Owned by `habits_owner`.
  - `habits_rw` — read/write, used from your laptop.
  - `habits_ro` — read-only, used by Metabase to query your data.
- `mbapp` — Metabase's internal store (dashboards, users). Owned by `mbapp_user`.

Roles, databases, and grants are reconciled idempotently by the `postgres-bootstrap` Job on every deploy.

## Secrets (1Password vault `homelab`, tag `habits`)

Item `habits-secrets` with fields:

- `POSTGRES_PASSWORD` — superuser
- `HABITS_OWNER_PASSWORD`
- `HABITS_RW_PASSWORD`
- `HABITS_RO_PASSWORD`
- `MBAPP_PASSWORD`
- `MB_ENCRYPTION_SECRET_KEY` — 32+ random chars; encrypts stored DB connection passwords inside Metabase

## Deploy

The bootstrap `Job` cannot be re-applied without first being deleted, so run:

```bash
kubectl -n habits delete job postgres-bootstrap --ignore-not-found
./scripts/deploy.sh habits
kubectl -n habits logs job/postgres-bootstrap -f
```

## First-time Metabase setup

1. Open `https://habits.<tailnet>.ts.net`, create the admin user.
2. Add a database connection:
   - Type: PostgreSQL
   - Host: `postgres`
   - Port: `5432`
   - Database: `habits`
   - User: `habits_ro`
   - Password: from 1Password

## Connecting from your laptop

```bash
psql "postgresql://habits_rw@habits-db.<tailnet>.ts.net:5432/habits"
```

You'll need a tailnet ACL grant from your device to `habits-db:5432`.

## Backups

The `habits-backup` CronJob runs `pg_dumpall` daily at 03:00 America/Los_Angeles, gzips the dump, and writes it to `/mnt/primary/k3s-storage/files/backups/habits-postgres/` — visible inside copyparty under `backups/habits-postgres/`. Files older than 14 days are pruned.

Trigger a manual backup:

```bash
kubectl -n habits create job --from=cronjob/habits-backup habits-backup-manual
```

## Lira sync

The `lira-sync` CronJob runs nightly at 04:00 America/Los_Angeles. It snapshots the lira sqlite file (using sqlite's online-backup API, safe against concurrent writers) and uses [pgloader](https://pgloader.io/) to mirror every table into the `lira` schema of the `habits` database. Each run drops and recreates tables, so postgres is always a fresh copy of sqlite.

`habits_ro` automatically gets `SELECT` on the new tables via default privileges set in the bootstrap Job, so Metabase can query them — re-sync the database schema in Metabase admin after the first run to pick up `lira.*` tables.

Trigger a manual sync:

```bash
kubectl -n habits create job --from=cronjob/lira-sync lira-sync-manual
kubectl -n habits logs job/lira-sync-manual -f
```
