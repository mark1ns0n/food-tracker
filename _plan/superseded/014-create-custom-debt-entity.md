# 014 - Create Custom Debt Entity

## Goal

Allow the user to add a new debt-tracked consumable entity, similar to
`Corona Extra` or `Энергетик`, from the `Долги` flow.

## Previous Behavior

- Debt entities are expected to come from transferred `ban` configuration.
- `Corona Extra` and `Энергетик` are effectively predefined examples.
- A new food/drink debt type requires a code/config change.

## New Behavior

- `foodtracker` exposes an `Add` action for debt entities.
- The add flow captures all settings needed to calculate and display the
  entity:
  - display name
  - linked ban/rule name
  - daily/ledger limit, if still used by the debt engine
  - calories per one unit
  - cost to complete/repay one unit by calories
  - cost to complete/repay one unit by another allowed method
  - daily unpaid-debt accrual percent
  - default enabled/visible state
- Newly created entities become available in the `Долги` list and action flows.

## Invariants

- Existing `Corona Extra` and `Энергетик` behavior must not change.
- Creating a debt entity must not create ledger debt by itself.
- Entity creation must be additive; no existing debt history is rewritten.
- Entity names used for matching should be normalized consistently, but the
  user-facing name should preserve the entered casing.
- Business rules for repayment cost calculation must live outside SwiftUI views.

## Explicit Assumptions

- `calories per one unit` is the base calorie value for consuming one item.
- `cost to complete/repay one unit by calories` is the base repayment cost
  before any active ban-rule coefficient is applied.
- `cost to complete/repay by another method` is product metadata until a later
  repayment method explicitly consumes it.
- `daily unpaid-debt accrual percent` is a per-entity setting; `0%` means no
  extra debt accrues for unpaid days.
- Name uniqueness is checked case-insensitively after trimming whitespace.

## Atomic Work

- Add an additive SwiftData model for user-configurable debt entity settings or
  extend the planned debt schema additively if that model already exists.
- Add a domain value object or service that validates debt entity settings.
- Add a `Долги` add button and a create form/dialog.
- Wire creation through a view model or service, not directly from row logic.
- Seed or migrate the existing predefined entities into the same settings model
  without duplicating them.
- Show validation errors for missing name, invalid calories, invalid repayment
  cost, invalid accrual percent, or duplicate normalized name.

## Edge Cases

- Empty name.
- Name with only whitespace.
- Duplicate name with different casing.
- Zero calories per unit.
- Negative calories or repayment cost.
- Negative daily accrual percent.
- Very large numeric values.
- Create, cancel, then create again.
- Existing migrated `Corona Extra` and `Энергетик` records already present.

## Done Criteria

- User can create a new debt entity from the app UI.
- The entity appears in `Долги` and can be used by the existing debt action
  flows.
- Invalid input is rejected before persistence.
- Existing source-app entities are represented once and keep their behavior.

## Verification

- Build the app or run an equivalent Xcode compile check.
- Test debt entity validation for empty, duplicate, zero, negative, and valid
  settings.
- Manually create a custom entity and confirm it appears in the debt list.
- Confirm creating the entity does not add debt ledger history.
