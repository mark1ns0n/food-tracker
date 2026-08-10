# 041 - Backend Database Backup And Restore

## Goal

Add operational backup and restore for the backend PostgreSQL database.

## Previous Behavior

- Local app backup exists.
- Backend database does not exist and therefore has no backup process.

## New Behavior

- Backend sync data has a tested backup/restore procedure.
- A Pi disk, pod, or migration failure does not make the backend unrecoverable.

## Invariants

- Backup jobs must not expose secrets in logs.
- Restore must be tested before backend sync is treated as reliable.
- App local data still remains a fallback, but backend should not rely on that
  as its only recovery path.

## Explicit Assumptions

- Phase one may use scheduled `pg_dump` to a PVC or manually copied file.
- Off-Pi backup destination is a later decision unless selected in this step.

## Atomic Work

- Add backup job or documented manual `pg_dump`.
- Add restore runbook.
- Add retention policy.
- Add backup health check.
- Test restore into a temporary database.
- Document how backup interacts with Argo/K8s manifests.

## Edge Cases

- Database pod unavailable during backup.
- Backup file corrupted.
- Restore into newer schema.
- Restore old database while clients have newer local outbox entries.
- Pi storage fills up.

## Done Criteria

- Database backup and restore procedure exists.
- Restore has been exercised at least once in a safe target.
- Risks and retention are documented.

## Verification

- Run backup command/job.
- Restore into temporary database.
- Run backend health and simple pull against restored data.
