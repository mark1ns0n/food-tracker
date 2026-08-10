# 013 - Final Integration And Retirement Check

## Goal

Finish the transfer by verifying the product outcome and deciding whether the
standalone `ban` app can be retired.

## Previous Behavior

- Food tracking and debt tracking live in separate apps.
- User must switch apps to track food, drinks, active calories, and debt.

## New Behavior

- `foodtracker` contains the transferred food/drink debt workflow.
- The standalone `ban` app is no longer needed for the migrated scope once data
  is verified.

## Invariants

- Existing foodtracker workflows remain correct.
- Imported debt state matches the old app before retirement.
- Known gaps or excluded behavior are named explicitly.

## Explicit Assumptions

- The old app should not be deleted or disabled until migration counts and debt
  state have been verified on real data.

## Atomic Work

- Run the full app after all prior tasks.
- Verify each major workflow:
  - grocery tracking
  - delivery and dine-in
  - fasting
  - backup/restore
  - debts
  - ban rules
  - calorie repayment
  - data migration
- Compare source `ban` computed states with `foodtracker` computed states.
- Remove any temporary duplication introduced during the transfer.
- Document any behavior intentionally left out.

## Edge Cases

- Real store has no old ban data.
- Real store has partial imported data.
- HealthKit unavailable during final verification.
- Existing foodtracker backup contains no debt data.

## Done Criteria

- Transfer is verified end to end on real or representative data.
- No temporary duplicate business rules remain.
- No known in-scope technical debt is hidden.
- The user has a clear status for whether `ban` can be retired.

## Verification

- Run automated engine and backup checks.
- Launch app and manually exercise all transferred actions.
- Run migration on the real/copy store and compare source/target debt states.
- Review changed files for duplication, dead code, stale files, unused helpers,
  inconsistent naming, and partial refactors.
