# 043 - Sync Observability And Runbook

## Goal

Add enough observability and operational notes to debug sync on `mPi5`.

## Previous Behavior

- Local app issues are debugged manually.
- `mPi5` has no Prometheus/Loki stack installed.
- Backend sync service does not exist.

## New Behavior

- Backend logs contain safe sync diagnostics.
- App exposes enough sync status for manual troubleshooting.
- Runbook explains common commands for GitHub, K3s, Argo CD, database, and app
  sync state.

## Invariants

- Logs must not contain auth tokens or private payload details beyond safe
  identifiers/counts.
- Observability must work with current `mPi5` add-ons and not assume
  Prometheus/Loki.
- Runbook commands must avoid destructive operations unless clearly labeled.

## Explicit Assumptions

- Phase-one observability is kubectl logs, health endpoints, structured log
  fields, and app status UI.
- Full monitoring stack is optional later work.

## Atomic Work

- Add structured backend logs for push, pull, auth failure, migration, and DB
  errors.
- Add safe app sync status details:
  - pending outbox count
  - last successful push/pull
  - last error
  - current cursor
- Add health/readiness endpoint behavior.
- Add runbook commands:
  - GitHub workflow status
  - Argo app status
  - pod logs
  - database backup
  - backend health
- Add troubleshooting cases.

## Edge Cases

- Backend accepts pushes but pull returns empty.
- One phone stuck with pending outbox.
- Auth revoked.
- Database migration failed.
- Argo deployed old image tag.

## Done Criteria

- Sync failures can be diagnosed without reading source code first.
- Runbook is accurate for `mPi5`.
- Logs are useful and safe.

## Verification

- Run through runbook against local service or `mPi5`.
- Trigger one controlled auth failure and one controlled sync failure and
  confirm diagnostics are visible.
