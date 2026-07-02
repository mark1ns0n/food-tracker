# 025 - Backend Postgres Schema And Migrations

## Goal

Add durable PostgreSQL storage for devices, sync operations, entity state, and
pull cursors.

## Previous Behavior

- There is no backend persistence.
- The local `superapp` reference keeps envelopes only in memory.

## New Behavior

- Backend data survives service restart and pod reschedule.
- Sync operations are stored append-only.
- Current entity state and tombstones can be derived or queried without scanning
  the whole log every time.

## Invariants

- Migrations are additive-first and idempotent.
- Duplicate operation IDs must not create duplicate log entries.
- Tombstones are preserved.
- No migration should silently drop user data.

## Explicit Assumptions

- PostgreSQL runs in K3s with a PVC on `mPi5` local-path storage for phase one.
- Backups for the server database are planned separately before relying on it as
  the only durable copy.

## Atomic Work

- Add migration tooling.
- Create tables:
  - `devices`
  - `sync_operations`
  - `entity_states`
  - `sync_acks`
  - `schema_migrations`
- Add unique indexes on operation ID and entity identity.
- Add server sequence generation.
- Add tombstone fields.
- Add migration tests or deterministic local migration check.

## Edge Cases

- Migration rerun after partial failure.
- Duplicate operation pushed twice.
- Operation references unknown device.
- Entity deleted then updated by stale client.
- Database restart while a push batch is being written.

## Done Criteria

- Database migrations apply cleanly from empty state.
- Reapplying migrations is safe.
- Persistent tables support idempotent push and cursor-based pull.

## Verification

- Run migrations against a local PostgreSQL instance.
- Run backend persistence tests.
- Restart local database/service and confirm stored operations remain available.
