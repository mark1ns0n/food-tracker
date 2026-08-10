# 021 - Local Change Journal And Outbox

## Goal

Persist every local mutation in a durable local outbox so it can be pushed to
the backend after internet returns.

## Previous Behavior

- Local changes are written directly to SwiftData.
- There is no durable queue of changes waiting for remote sync.
- Failed network calls are not tracked because sync does not exist.

## New Behavior

- Domain write services write the local model change and a sync outbox record in
  the same logical operation.
- Outbox entries have stable operation IDs for idempotent backend push.
- Failed pushes remain pending and retry safely.

## Invariants

- Local state must be correct even if the outbox has not pushed yet.
- A local mutation must not be lost if the app exits immediately after the user
  taps.
- Retrying the same outbox entry must not create duplicate remote effects.
- SwiftUI views must not construct sync envelopes directly.

## Explicit Assumptions

- Outbox persistence uses SwiftData additively.
- The sync operation ID is generated before the local write is committed.
- If local model save succeeds but outbox save fails, the domain service reports
  an error and does not pretend the mutation is syncable.

## Atomic Work

- Add a `SyncOutboxEntry` model with operation ID, entity ID, entity type,
  action, payload, created timestamp, retry metadata, and status.
- Add a domain-level mutation writer helper.
- Route Delivery, Dine-In, fasting, and debt writes through domain services
  before sync is enabled.
- Ensure delete operations create tombstone outbox entries.
- Add retry scheduling metadata without starting network sync yet.
- Add tests for atomic local write plus outbox creation.

## Edge Cases

- App crashes after local save and before sync attempt.
- User edits the same entity multiple times while offline.
- User deletes an entity that still has unsynced create/update operations.
- Outbox payload schema changes between app versions.
- Duplicate operation ID appears after backup restore.

## Done Criteria

- Every phase-one syncable local mutation creates an outbox entry.
- Outbox entries survive app restart.
- Domain services, not SwiftUI views, own mutation and outbox creation.

## Verification

- Unit-test create/update/delete mutations for at least one simple model and
  one debt-related model.
- Kill/reopen the app or use an in-memory persistence test that simulates
  reload and confirm pending outbox entries remain.
- Confirm duplicate retries use the same operation ID.
