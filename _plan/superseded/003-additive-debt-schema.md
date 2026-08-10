# 003 - Additive Debt Schema

## Goal

Add the debt-tracking SwiftData models to `foodtracker` with an additive-first
schema change.

## Previous Behavior

- `foodtracker` schema contains `Item`, `FoodEntry`, `SavedName`,
  `DineInEntry`, `FastingEntry`, and `FastingDebt`.
- `foodtracker` does not persist `ban` debt ledger, calorie repayment, weekly
  calorie balance, meal completion, or ban-rule data.

## New Behavior

- `foodtracker` schema can store the transferred debt domain without deleting or
  changing existing models.
- Old `foodtracker` records remain readable after the schema update.

## Invariants

- Existing food, fasting, delivery, dine-in, and backup data must remain intact.
- Schema introduction must be additive; no destructive migration is allowed.
- The schema must support rerunning later data import without duplicate records.

## Explicit Assumptions

- Keep the source model shape close to `ban` initially to reduce migration risk.
- Rename only where it improves clarity without changing persisted semantics.

## Atomic Work

- Add debt models equivalent to:
  - `BanEntry`
  - `DailyLimit`
  - `LimitHistoryEntry`
  - `CalorieRepaymentEntry`
  - `CalorieWeeklyBalance`
  - `MealCompletionEntry`
- Add them to `foodtrackerApp` `Schema`.
- Add preview/in-memory model-container support for the new models.
- Ensure model filenames and type names do not conflict with existing partial
  user changes in the worktree.
- Do not remove any legacy fields in the first schema task.

## Edge Cases

- Launch with an existing `foodtracker` store that has none of the new models.
- Launch with the current dirty partial Ban files present or deleted.
- Launch an in-memory preview container with all models registered.

## Done Criteria

- App container initializes with the new additive schema.
- Existing `foodtracker` data remains visible after launch.
- No old model is removed or renamed.

## Verification

- Build the app or run an equivalent Xcode compile check.
- Launch with an existing local `foodtracker` store and confirm old tabs still
  load.
- Run a small in-memory SwiftData smoke check for the expanded schema.
