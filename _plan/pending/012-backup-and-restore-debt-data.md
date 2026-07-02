# 012 - Backup And Restore Debt Data

## Goal

Extend `foodtracker` backup/restore coverage so transferred debt data is not
lost after migration.

## Previous Behavior

- `foodtracker` has `BackupService` and `BackupView`.
- Backup coverage may only include current food/fasting models.
- `ban` debt data is not part of `foodtracker` backups before migration.

## New Behavior

- Backup and restore include debt models, calorie repayment history, weekly
  balances, meal completions, and ban rules.
- Restore preserves enough history for the debt engine to recompute state.

## Invariants

- Backup format changes must be backward compatible where possible.
- Restoring a backup must not duplicate existing debt records.
- Restored ledger history must preserve timestamp ordering.

## Explicit Assumptions

- Backup support should happen after the new schema exists but before the old
  `ban` app is retired.

## Atomic Work

- Inspect `BackupService` current model coverage.
- Add serialization for the new debt models.
- Add restore logic with idempotent matching.
- Include migration/import metadata only if it helps debugging.
- Add backup fixture data for at least one debt item and one calorie repayment.

## Edge Cases

- Restoring a backup created before debt models existed.
- Restoring into a store that already has imported debt data.
- Missing optional legacy snapshot fields.
- Weekly balance restored before repayment entries.

## Done Criteria

- New debt data appears in backup output.
- Restored debt data computes the same state as before backup.
- Older backups still restore without requiring debt sections.

## Verification

- Create a backup with debt, calorie, weekly balance, meal, and ban-rule data.
- Restore into an empty in-memory or test store and compare record counts and
  computed debt state.
- Restore an older backup and confirm food/fasting data still restores.
