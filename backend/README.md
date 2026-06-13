# CalorieLens API

Laravel 12 backend — **accounts + offline-first sync** (v1). SQLite now,
Postgres-ready (change `DB_CONNECTION` only). No Redis required: cache, queue,
and session all use the database/sync drivers.

> The fuller production design (Postgres + pgvector, Redis queues, Octane,
> RS256 JWT with rotating refresh, the AI/nutrition domain layer, scans/coach/
> planner endpoints) is preserved under [`reference/`](reference/) as the
> build-out target. This app is the runnable foundation.

## Run

```bash
composer install
php artisan migrate          # creates tables in database/database.sqlite
php artisan serve --port=8791
```

## Endpoints (`/api/v1`)

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `auth/register` | — | `{name,email,password}` → `{token,user}` |
| POST | `auth/login` | — | `{email,password}` → `{token,user}` |
| POST | `auth/logout` | Bearer | revoke current token |
| GET  | `me` | Bearer | `{user, profile}` |
| PUT  | `profile` | Bearer | upsert the profile (calorie-target inputs) |
| GET  | `sync?since=ISO` | Bearer | pull changes (diary, water, weights, profile) |
| POST | `sync` | Bearer | push local changes (idempotent, tombstone deletes) |

Auth is Sanctum personal access tokens — send `Authorization: Bearer <token>`.

## Sync model

The phone is the editor. Diary entries use the **client UUID as primary key**,
so re-pushing upserts (never duplicates) and deletes ride along as soft-delete
tombstones the client pulls and removes. Last-write-wins; volumes are tiny
(one person's diary), so no operational transforms.

## Test

```bash
php artisan test --filter=SyncFlowTest
```
