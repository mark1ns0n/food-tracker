# 015 - Edit Custom Debt Entity

## Goal

Allow the user to edit settings for an existing debt-tracked consumable entity.

## Previous Behavior

- Debt entity settings are static or migrated from `ban`.
- Changing calories, repayment cost, names, or matching rules requires a code
  change or data migration.

## New Behavior

- `foodtracker` provides an edit action for debt entities.
- Editable settings include the same fields used by create:
  - display name
  - linked ban/rule name
  - daily/ledger limit, if still used by the debt engine
  - calories per one unit
  - calorie repayment cost
  - other-method repayment cost
  - daily unpaid-debt accrual percent
  - enabled/visible state

## Invariants

- Editing entity settings must not delete historical debt ledger records.
- Ledger entries already written keep their original event identity and dates.
- If historical records need to display the old name or old cost, that behavior
  must be explicit and tested before the read path changes.
- Editing a normalized name must not create a duplicate conflict with another
  entity.
- Active ban-rule coefficient calculation must keep using the entity's linked
  ban/rule name after edit.

## Explicit Assumptions

- The first implementation applies changed settings to future calculations and
  current unresolved debt views.
- Historical raw events are not rewritten during edit.
- If a user edits the display name only, migrated ledger records still map to
  the same entity through a stable entity identifier, not by display text alone.

## Atomic Work

- Add stable identifiers for configurable debt entities if the create task did
  not already add them.
- Add an edit form/dialog that reuses create validation without duplicating the
  rules.
- Add a service method for applying entity updates atomically.
- Decide and document whether unresolved debt rows recalculate with new costs or
  keep old captured costs.
- Update the `Долги` list to expose edit actions without cluttering the main
  consumption workflow.
- Add tests for edit validation and ledger preservation.

## Edge Cases

- Editing name to an existing entity's name.
- Editing only casing or surrounding whitespace.
- Editing costs while unresolved debt exists.
- Editing daily unpaid-debt accrual percent while unresolved debt exists.
- Editing linked ban/rule name while a coefficient is active today.
- Canceling an edit after changing fields.
- Disabling/hiding an entity that has unresolved debt.

## Done Criteria

- User can edit a debt entity from the app UI.
- Validation rules match create behavior.
- Existing ledger history remains intact.
- The debt list and calculation behavior after edit are documented and tested.

## Verification

- Build the app or run an equivalent Xcode compile check.
- Test edit validation for duplicate and invalid numeric values.
- Manually edit an entity with existing debt and confirm ledger records remain.
- Confirm the UI reflects the edited settings after app reload.
