# 005 - Debt Config And Ban Rules

## Goal

Move the food/drink debt configuration and monthly coefficient rules into a
maintainable `foodtracker` domain layer.

## Previous Behavior

- `ban` hardcodes `LimitConfig` in `LimitsTabView`.
- Active ban coefficients are calculated by matching a configured `banName`
  against `BanEntry` records active on the current day of month.

## New Behavior

- `foodtracker` has explicit debt-item configuration for alcohol, energy drinks,
  and future similar consumables.
- Ban rules can adjust calorie repayment cost without duplicating logic in the
  view.

## Invariants

- `Corona Extra` remains tied to `Бухло` with base calorie cost `148`.
- `Энергетик` remains tied to `Сладкое` with base calorie cost `154`.
- A coefficient applies only when its day-of-month coefficient is greater than
  zero.
- If multiple matching rules are active, the highest coefficient wins.

## Explicit Assumptions

- The transfer keeps the existing day-of-month rule model from `ban`.
- Limits are still displayed as fixed product metadata, even though current debt
  calculation primarily uses ledger state.

## Atomic Work

- Extract debt item configs out of the view into a small static domain config.
- Add helper methods for active coefficient lookup.
- Preserve `BanEntry` selected-day coefficient migration behavior.
- Add or port a simple Ban-rule management view only after the domain helpers
  exist.
- Avoid putting coefficient calculation directly inside SwiftUI rows.

## Edge Cases

- No configured ban rule.
- Ban rule exists but has zero coefficient for today.
- Duplicate rules with different coefficients.
- Legacy rule with selected days but missing per-day coefficients.
- Invalid day values outside `1...31`.

## Done Criteria

- Debt config is readable and testable outside the view.
- Active coefficient lookup gives the same result as `ban`.
- Legacy coefficient migration is still supported.

## Verification

- Test active coefficient lookup for no rule, zero rule, one active rule, and
  duplicate active rules.
- Manually create a legacy `BanEntry` and confirm coefficient migration fills
  missing values.
