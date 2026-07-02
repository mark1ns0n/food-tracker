# 009 - Calorie Repayment And Meals

## Goal

Port calorie repayment, weekly calorie balances, and meal completion behavior
from `ban` into `foodtracker`.

## Previous Behavior

- `ban` can use weekly active calories to offset or repay debt.
- `ban` tracks weekly calorie balances with carry-in, burned, used, and
  carry-out calories.
- `ban` tracks completed meals:
  - `Завтрак` 500 kcal
  - `Обед` 600 kcal
  - `Ужин` 600 kcal
- Basal calories available for repayment are reduced by completed meal calories.

## New Behavior

- `foodtracker` debt actions can consume available calorie credit using the same
  rules.
- Meal completion records affect basal calorie availability.
- Weekly calorie balance refresh can be rerun safely.

## Invariants

- Calories spent for repayment must never be negative.
- Completed meal records must only count within their day window.
- Current-week calorie balance includes carried-in prior weeks plus current
  active/basal availability minus used repayments.
- Historical weekly backfill must not duplicate existing weekly balances.

## Explicit Assumptions

- Week starts on Monday using the current locale/week settings from `ban`.
- Active calories and basal surplus are both counted in kilocalories.
- Completing a meal is idempotent per meal id per product day.

## Atomic Work

- Port `CalorieRepaymentEntry`, `CalorieWeeklyBalance`, and
  `MealCompletionEntry` behavior.
- Implement weekly balance refresh.
- Implement historical weekly backfill.
- Implement meal completion rows.
- Enable calorie repayment option in the debt confirmation dialog.
- Keep calorie math in services/helpers, not directly in row views.

## Edge Cases

- No HealthKit active calories.
- Negative basal surplus after meals.
- Current week with previous carried-in calories.
- Historical repayments before any stored weekly balance.
- Completing the same meal twice.
- Repayment when remaining calories are exactly equal to the required cost.

## Done Criteria

- Calorie summary matches the source app behavior.
- Calorie repayment inserts both debt repayment and calorie usage records.
- Weekly balance refresh is idempotent.
- Meal buttons disappear after completion for the current day.

## Verification

- Run deterministic tests for weekly balance carry-in/carry-out.
- Manually complete each meal and verify basal remaining changes.
- Repay with calories at below, equal, and above threshold values.
