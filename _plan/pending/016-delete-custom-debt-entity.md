# 016 - Delete Custom Debt Entity

## Goal

Allow the user to remove a debt-tracked consumable entity without corrupting
existing debt history.

## Previous Behavior

- Debt entities are static or migrated configuration.
- There is no user-facing delete flow for an entity like `Corona Extra` or
  `Энергетик`.

## New Behavior

- `foodtracker` provides a delete action for debt entities.
- Deletion uses a safe strategy that preserves historical ledger data.
- The UI makes the consequence clear before the entity disappears from normal
  debt actions.

## Invariants

- Deleting an entity must not delete its historical ledger entries silently.
- Migration from `ban` remains rerunnable and must not recreate a user-deleted
  entity unless the delete strategy explicitly supports restore.
- Unresolved debt cannot become invisible without a deliberate archived/deleted
  state that the debt engine understands.
- Backup and restore must preserve deleted/archived entity state.

## Explicit Assumptions

- Prefer soft delete or archive over hard delete for the first implementation.
- A deleted entity is hidden from new consumption actions.
- Existing unresolved debt for a deleted entity remains visible until resolved,
  or deletion is blocked while unresolved debt exists.
- Hard deletion is out of scope unless all references are proven absent.

## Atomic Work

- Add an archived/deleted marker to the debt entity settings model.
- Add a delete confirmation flow in the `Долги` entity management UI.
- Implement deletion through a service that checks unresolved debt before
  applying the state change.
- Decide whether deletion is blocked with unresolved debt or allowed while
  keeping unresolved rows visible.
- Update migration idempotency so deleted migrated entities are not silently
  reenabled.
- Include archived/deleted state in backup and restore coverage.

## Edge Cases

- Delete entity with no ledger history.
- Delete entity with resolved historical ledger entries.
- Delete entity with unresolved active debt.
- Cancel delete confirmation.
- Delete a migrated default entity, then rerun migration.
- Restore backup containing an archived entity.

## Done Criteria

- User can delete or archive a debt entity from the app UI.
- Deleted entities no longer appear in new consumption actions.
- Historical and unresolved debt behavior is explicit and correct.
- Repeated migration/backfill does not undo the user's deletion choice.

## Verification

- Build the app or run an equivalent Xcode compile check.
- Test delete behavior for entities with no history, resolved history, and
  unresolved debt.
- Manually delete a custom entity and confirm it disappears from new action
  flows.
- Rerun the migration/backfill path and confirm deleted state is preserved.
