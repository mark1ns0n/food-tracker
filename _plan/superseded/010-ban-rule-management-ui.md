# 010 - Ban Rule Management UI

## Goal

Add the `Ban` rule-management UI needed to configure debt calorie coefficients
inside `foodtracker`.

## Previous Behavior

- `ban` has a separate `Ban` tab with:
  - current active rules shown in `Today`
  - all rules sorted by selected-day count and creation time
  - add/edit/delete dialogs
  - 1...31 day grid with per-day coefficient values

## New Behavior

- `foodtracker` lets the user manage the rules that affect debt calorie costs.
- Active rule count is visible enough to explain why a calorie repayment cost is
  increased.

## Invariants

- Ban-rule UI must not duplicate coefficient business logic.
- Editing a rule preserves existing selected-day coefficients unless changed.
- Deleting a rule does not delete debt ledger history.

## Explicit Assumptions

- This UI can be a tab or a section of `Долги`; final placement should favor
  clarity over exact source-app layout.

## Atomic Work

- Port `BanEntryRow`, `BanEntryDialog`, and `DaysGridView` or create equivalent
  foodtracker components.
- Add add/edit/delete flows.
- Run legacy selected-day coefficient migration on appear.
- Show active-today rules and coefficient values.
- Decide whether the UI lives as a separate tab or nested in `Долги`.

## Edge Cases

- Rule with no active days.
- Coefficient text input with negative value.
- Editing existing legacy rule.
- Delete confirmation cancellation.
- Multiple active rules with the same name.

## Done Criteria

- User can create, edit, and delete coefficient rules.
- Debt calorie cost reflects the configured active rules.
- UI remains usable on compact screens.

## Verification

- Create a `Бухло` rule for today and confirm Corona calorie cost increases.
- Edit the coefficient and confirm the debt tab updates.
- Delete the rule and confirm the cost returns to base.
