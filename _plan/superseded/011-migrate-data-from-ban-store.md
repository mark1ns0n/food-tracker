# 011 - Migrate Data From Ban Store

## Goal

Import existing persisted `ban` food/debt data into `foodtracker` without
destroying either app's data.

## Previous Behavior

- `ban` stores data under bundle id `com.mark1ns0n.ban`.
- `foodtracker` stores data under bundle id `com.mark1ns0n.foodtracker`.
- `foodtracker` cannot currently read `ban` SwiftData records.

## New Behavior

- `foodtracker` can perform a one-time, rerunnable import of compatible records
  from the old `ban` store.
- Imported data appears in `foodtracker` debt views.
- Re-running migration does not duplicate imported rows.

## Invariants

- The migration is additive-first and non-destructive.
- The old `ban` store is never modified by the migration.
- Imported records preserve timestamps, names, deltas, snapshots, coefficients,
  and calorie/meal fields.
- Migration can be safely retried after app restart.

## Explicit Assumptions

- The migration source is the local app container for bundle id
  `com.mark1ns0n.ban`.
- If direct app-container access is blocked, the fallback is an explicit export
  from `ban` followed by import into `foodtracker`.
- Idempotency should be based on stable natural keys, not on new SwiftData
  object identities.

## Atomic Work

- Locate the actual `ban` SwiftData store path on the device/simulator.
- Define natural-key matching for each imported model:
  - ban rules: name + createdAt
  - daily limits: name + date
  - history entries: name + createdAt + delta + kind
  - calorie repayments: targetName + createdAt + caloriesSpent + unitsRepaid
  - weekly balances: weekStart
  - meals: mealID + createdAt
- Build a read-only source container or export reader.
- Insert only missing records into the `foodtracker` container.
- Record migration completion and imported counts.
- Add a manual migration trigger until automatic migration is proven safe.

## Edge Cases

- Source store does not exist.
- Source schema version has legacy fields only.
- Partial migration completed before crash.
- Duplicate records already exist in `foodtracker`.
- Store read fails due permissions or path mismatch.
- Timezone-sensitive legacy `DailyLimit.date` rows.

## Done Criteria

- Import can run twice with identical final counts.
- Imported history computes the same debt state as source `ban`.
- Source `ban` data remains untouched.

## Verification

- Run migration on a copied fixture store.
- Run migration twice and compare counts after each run.
- Compare computed state for each configured debt item before and after import.
- Verify old foodtracker tabs still show their pre-migration data.
