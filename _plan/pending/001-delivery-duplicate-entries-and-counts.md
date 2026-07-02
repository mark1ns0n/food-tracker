# 001 - Delivery Duplicate Entries And Counts

## Goal

Allow Delivery to contain several active entries with the same Delivery name, and
show how many active entries with that name already exist while the user is
adding another one.

## Current Behavior

- Delivery rejects duplicate active names with `That name is already in the list.`
- `talabat mart` is a special case and can be added more than once.
- Dine-In still blocks adding Delivery for a name that is active in Dine-In.

## New Behavior

- Any Delivery name can be added multiple times while it is active.
- When the add-Delivery sheet is open and the user selects or types a name, the
  UI shows the current active count for that normalized name before adding.
- If the same name is added again, the new entry is inserted as a separate
  `FoodEntry`; existing entries are not merged or overwritten.
- The Delivery section summary continues to count entries, not unique names.

## Invariants

- Expired Delivery entries must not count toward the visible duplicate count.
- Dine-In conflict protection remains active: an active Dine-In name still
  prevents creating a Delivery entry with the same normalized name.
- Saved names remain unique and only update `lastUsed`; duplicate Delivery
  entries must not create duplicate `SavedName` records.
- Existing active Delivery entries remain valid after the change.

## Explicit Assumptions

- Name matching uses the existing normalized-name rule: trim whitespace and
  compare lowercased strings.
- Count display is informational only. It must not prevent submitting a valid
  duplicate Delivery entry.
- The displayed count is the count before the current add action is submitted.

## Atomic Work

- Remove the Delivery duplicate guard and the `talabat mart` special case from
  the add-Delivery flow.
- Add a reusable helper that counts active Delivery entries by normalized name.
- Pass the active duplicate count into the Delivery add sheet as the typed or
  selected name changes.
- Show the count in the sheet only when the normalized name is non-empty and the
  count is greater than zero.
- Keep the Dine-In conflict check before insertion.
- Add focused tests or deterministic validation for duplicate insertion and
  count calculation.

## Edge Cases

- Empty or whitespace-only name.
- Same name with different capitalization.
- Same name with leading or trailing spaces.
- Existing expired entry with the same name.
- Active Dine-In entry with the same name.
- Saved name selected from the list versus typed manually.

## Done Criteria

- The same Delivery name can be added two or more times.
- While adding Delivery, the sheet displays how many active entries with that
  name already exist.
- Expired entries do not affect the displayed duplicate count.
- Dine-In conflict behavior is unchanged.
- The implementation does not duplicate Delivery business rules in multiple
  views.

## Verification

- Add the same Delivery name twice and confirm two separate active entries are
  visible.
- Open the add-Delivery sheet, type that same name, and confirm the displayed
  count matches the active entries already in the list.
- Create or simulate an expired entry with that name and confirm it is excluded
  from the count.
- Try a name that is active in Dine-In and confirm Delivery still rejects it.
