# 007 - Debts Tab Shell

## Goal

Add a `Долги` tab to `foodtracker` that displays computed debt state without
mutating data yet.

## Previous Behavior

- `foodtracker` tabs are `Food`, `Fasting`, and `Backup`.
- `ban` has a `Долги` tab implemented in `LimitsTabView`.

## New Behavior

- `foodtracker` has a `Долги` tab that reads the new debt models and shows the
  same main debt rows as `ban`.
- Buttons may be present but mutation can remain disabled until the next task.

## Invariants

- Existing tab order and behavior must remain understandable.
- Computed debt state comes from the domain engine, not duplicated row logic.
- Unknown HealthKit calorie state is displayed clearly.

## Explicit Assumptions

- A read-only shell is useful because it proves schema, engine, and HealthKit
  wiring before actions are added.

## Atomic Work

- Add `DebtsTabView` or port `LimitsTabView` under a clear foodtracker name.
- Add tab registration in `ContentView`.
- Display active/basal calorie summary.
- Display one row per configured debt item.
- Keep add/repay actions disabled or no-op until action task is complete.
- Preserve Russian labels where they are user-facing from `ban`.

## Edge Cases

- No ledger entries.
- HealthKit values are nil.
- Existing debt history but no weekly calorie balance.
- Small screen where row text can wrap.

## Done Criteria

- The new tab appears and renders without crashes.
- Existing tabs still render.
- The tab can show empty-state debt rows.

## Verification

- Build and launch the app.
- Open every tab and confirm no tab crashes.
- Seed in-memory ledger events and confirm the read-only row values match engine
  output.
