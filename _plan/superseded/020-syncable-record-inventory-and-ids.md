# 020 - Syncable Record Inventory And IDs

## Goal

Inventory every `foodtracker` record that may sync and assign stable portable
identifiers before adding remote sync.

## Previous Behavior

- SwiftData object identity is local to one store.
- Some records are identified by user-visible names and timestamps.
- Backup/restore serializes records but does not define cross-device identity.

## New Behavior

- Every syncable model has a stable `syncID` or equivalent portable identifier.
- Sync metadata is additive and separate from SwiftData object identity.
- The inventory states which models sync in phase one and which remain local.

## Invariants

- Existing local records remain readable after the additive metadata change.
- Stable IDs must not be derived from array order, SwiftData object identity, or
  mutable display names.
- Name uniqueness rules, duplicate Delivery rules, and debt entity settings
  continue to be enforced by domain logic, not by sync IDs alone.

## Explicit Assumptions

- Backfilling IDs for existing records is idempotent and can be rerun.
- Soft-deleted records need IDs too, because tombstones must sync.
- Phase-one sync should include user-facing data and settings, not local-only
  notification delivery history.

## Atomic Work

- List current and planned models:
  - `Item`
  - `FoodEntry`
  - `SavedName`
  - `DineInEntry`
  - `FastingEntry`
  - `FastingDebt`
  - planned debt models
  - planned notification/sync settings
- Mark each model as `sync phase one`, `sync later`, or `local only`.
- Add additive metadata fields in a future schema task:
  - `syncID`
  - `createdDeviceID`
  - `updatedDeviceID`
  - `updatedAt`
  - `deletedAt` when deletion is possible
  - `schemaVersion`
- Define stable natural-key fallback only for legacy backfill.
- Define a duplicate-ID detection policy.

## Edge Cases

- Existing records with the same display name.
- Existing records with identical timestamps.
- Restored backup contains records without sync metadata.
- A deleted record is restored from an old backup.
- Planned debt migration imports legacy `ban` records before sync IDs exist.

## Done Criteria

- A sync inventory document exists and covers current plus planned debt models.
- Every phase-one model has a stable ID strategy.
- Additive metadata and backfill expectations are documented.

## Verification

- Cross-check the inventory against `foodtrackerApp.swift` schema and pending
  debt plan files.
- Confirm every phase-one sync model has create, update, delete, and restore
  semantics described.
