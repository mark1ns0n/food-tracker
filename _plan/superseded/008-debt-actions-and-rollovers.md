# 008 - Debt Actions And Rollovers

## Goal

Enable debt mutations in `foodtracker`: add consumable units, repay debt with
other consumables, repay manually, and create missing rollovers.

## Previous Behavior

- `ban` writes `LimitHistoryEntry` deltas and rollovers from `LimitsTabView`.
- A negative delta adds consumed units.
- A positive delta repays debt.
- Missing rollovers are generated on refresh and saved as checkpoint entries.

## New Behavior

- `foodtracker` supports the same debt ledger mutations through the `Долги` tab.
- Rollover generation is idempotent and runs on appear/foreground.

## Invariants

- Refreshing the tab repeatedly must not duplicate rollover entries.
- Adding a unit creates ledger state or calorie repayment state exactly once per
  tap.
- Repaying with another consumable creates paired target/source events in stable
  timestamp order.
- Manual repayment cannot reduce debt below zero.

## Explicit Assumptions

- The source behavior for `repayDebtOther` remains: repay up to `7 * limit`.
- Paired events use millisecond offsets from the seed snapshot to preserve
  ordering.

## Atomic Work

- Implement `refreshAllLimits` equivalent in `foodtracker`.
- Implement `ensureSeededHistory`, seed repair, legacy history upgrade, and
  missing rollover insertion.
- Enable `Добавить +1`.
- Enable repayment with another configured consumable.
- Enable manual/other repayment.
- Save after each action and refresh computed state.

## Edge Cases

- First action when there is only legacy `DailyLimit` state.
- First action when there is no state at all.
- Debt already zero.
- Multiple rapid taps.
- Paired source/target actions after snapshot seeding.
- Foreground refresh after several missed days.

## Done Criteria

- All debt buttons mutate the ledger correctly.
- Re-opening the tab after missed days adds only missing rollovers.
- UI values reflect persisted ledger state after save.

## Verification

- Use deterministic fixtures to simulate add, repay, manual repay, and rollover.
- Run the engine checks after mutations.
- Manually tap each action and confirm persisted rows match expected deltas.
