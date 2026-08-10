# 023 - Conflict Resolution Policy

## Goal

Define deterministic conflict resolution before syncing edits from multiple
phones.

## Previous Behavior

- Conflicts cannot happen because all data is local to one app instance.
- Backup restore is effectively a local replacement flow.

## New Behavior

- When two devices change the same entity, merge behavior is predictable and
  testable.
- Domain-sensitive records can use append-only events instead of overwriting
  totals.

## Invariants

- Debt ledger, food entries, fasting debts, and financial/amount-like records
  must not be silently overwritten by last-writer-wins if that changes meaning.
- Deletes are tombstones and should win over stale updates unless a later
  explicit restore action exists.
- Conflict policy must be implemented in a service/engine, not SwiftUI views.

## Explicit Assumptions

- Phase one favors append-only event records where possible because they are
  easier to merge safely.
- Settings records may use last-writer-wins with server sequence tie-breaking
  if the field has no additive history.
- User-visible conflict prompts are out of scope until a real conflicting case
  requires them.

## Atomic Work

- Categorize records as:
  - append-only event
  - mutable setting
  - soft-deletable entity
  - derived view state
- Define merge rules per category.
- Define tie-breakers:
  - server sequence first
  - client timestamp only as metadata
  - device ID as final deterministic tie-breaker if needed
- Add conflict test fixtures.
- Document which records should never use last-writer-wins.

## Edge Cases

- Two phones add the same Delivery name at nearly the same time.
- One phone deletes a custom debt entity while another edits its percent.
- One phone repays debt while another adds consumption debt.
- One phone restores a backup with old settings.
- Two phones update notification settings differently.

## Done Criteria

- Conflict policy document exists.
- Every phase-one entity category has a merge rule.
- Known high-risk domain records avoid silent destructive overwrite.

## Verification

- Review the policy against debt, Delivery duplicates, and backup restore
  plans.
- Later implementation must add edge-case tests from this file before enabling
  sync writes.
