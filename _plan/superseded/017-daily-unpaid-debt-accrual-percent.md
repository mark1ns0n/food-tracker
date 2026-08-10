# 017 - Daily Unpaid Debt Accrual Percent

## Goal

Add a configurable daily percent that increases unresolved debt for every full
day it remains unpaid.

## Previous Behavior

- Debt grows only through explicit consumption events and existing rollover
  behavior transferred from `ban`.
- A debt entity can have calorie and repayment settings, but there is no
  per-day unpaid penalty configured by the user.

## New Behavior

- Each debt entity can define a daily unpaid-debt accrual percent.
- When debt remains unresolved across full product days, the engine adds the
  configured percent of the unpaid debt for each missed day.
- The debt UI shows enough information for the user to understand that part of
  the current debt came from unpaid-day accrual.

## Invariants

- `0%` accrual must preserve the old debt behavior exactly.
- Accrual must be idempotent: recalculating, relaunching the app, or rerunning a
  backfill must not double-charge the same unpaid day.
- Accrual must not be implemented in SwiftUI views.
- Historical consumption and repayment ledger events must not be rewritten.
- Accrual events must be distinguishable from user-entered consumption events.
- The day-boundary rule must remain the same as the debt engine unless a
  separate task explicitly changes it.

## Explicit Assumptions

- Use the debt engine's existing UTC product-day boundary from the transferred
  `ban` logic.
- Accrual applies only after a full unpaid product day has completed; the
  current partial day does not accrue yet.
- The percent is calculated from the unresolved debt amount at the start of the
  accrual day.
- Percent values are stored as decimal percentages, for example `10` means
  `10%`, not `0.10%`.
- Fractional accrued debt is rounded by a documented domain rule before it is
  persisted or displayed.

## Atomic Work

- Add an additive persisted setting for daily unpaid-debt accrual percent on the
  debt entity settings model.
- Add a domain policy that calculates accrual from unresolved debt, percent, and
  elapsed full product days.
- Extend the ledger/write policy with an accrual event type or equivalent
  idempotency key.
- Add the field to create and edit entity flows.
- Show accrued debt separately or with a clear label in the `Долги` UI.
- Include accrual settings and generated accrual events in backup/restore.
- Ensure migration seeds existing `Corona Extra` and `Энергетик` with `0%` unless
  the user explicitly configures another value.

## Edge Cases

- `0%` accrual.
- Empty ledger state.
- Debt created and repaid on the same product day.
- Debt unpaid across one full product day.
- Debt unpaid across multiple full product days.
- Partial repayment between accrual days.
- Accrual around UTC midnight with an Asia/Dubai local timestamp.
- Repeated refresh/backfill for the same unpaid day.
- Fractional percent and fractional accrued amount.
- Very large percent value.

## Done Criteria

- User can configure the daily unpaid-debt accrual percent per debt entity.
- Current debt includes unpaid-day accrual according to the documented rule.
- Repeated calculation does not duplicate accrual.
- Existing entities with `0%` behave exactly as before.
- The UI makes accrual visible enough that the debt amount is explainable.

## Verification

- Build the app or run an equivalent Xcode compile check.
- Test the accrual policy for `0%`, same-day repay, one-day unpaid, multi-day
  unpaid, partial repayment, UTC midnight, and repeated rebuilds.
- Manually set a non-zero percent, leave debt unresolved across a simulated full
  product day, and confirm the displayed debt increases once.
- Confirm migrated/default entities with `0%` do not accrue additional debt.
