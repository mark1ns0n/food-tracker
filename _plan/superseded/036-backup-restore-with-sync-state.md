# 036 - Backup Restore With Sync State

## Goal

Make local backup/restore compatible with sync metadata, outbox, cursors, and
device identity.

## Previous Behavior

- Backup/restore handles local app models.
- Import currently deletes and restores local data for covered models.
- There is no sync state to preserve or reset.

## New Behavior

- Backups include sync metadata needed to preserve stable entity IDs.
- Backups do not leak auth tokens.
- Restore has an explicit policy for outbox, cursor, and device identity.

## Invariants

- Restore must not silently create remote duplicates.
- Restore must not resurrect server-deleted records without an explicit local
  operation.
- Auth tokens must stay out of backup files.
- Additive-first restore behavior must preserve old backup compatibility.

## Explicit Assumptions

- Restoring user data and restoring device identity are separate decisions.
- Backup restore after sync may require a reconciliation step before pushing.

## Atomic Work

- Extend backup format with sync IDs and metadata.
- Decide whether pending outbox entries are included, skipped, or reset on
  backup.
- Add restore reconciliation state.
- Ensure imported records without sync IDs get backfilled safely.
- Add backup compatibility tests for pre-sync backups.
- Add UI warning when restoring into a synced device.

## Edge Cases

- Restore old backup on a device already synced to backend.
- Restore synced backup on a new phone without token.
- Restore backup with pending unsynced outbox.
- Restore backup containing deleted/tombstoned records.
- Restore backup created before debt migration.

## Done Criteria

- Backup/restore and sync metadata do not fight each other.
- Token handling is safe.
- Restore behavior is documented and tested.

## Verification

- Restore pre-sync backup.
- Restore sync-enabled backup without token.
- Restore with tombstone metadata and confirm deleted records do not reappear
  incorrectly.
