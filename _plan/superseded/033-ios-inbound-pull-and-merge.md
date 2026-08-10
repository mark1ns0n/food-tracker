# 033 - iOS Inbound Pull And Merge

## Goal

Apply remote changes from other phones into local SwiftData safely.

## Previous Behavior

- The app cannot receive other-device changes.
- Local backup import is the only multi-device-like path and may delete current
  local records.

## New Behavior

- The app pulls remote operations after its local cursor.
- Pulled operations are applied idempotently through domain merge services.
- Local cursor advances only after operations are applied.

## Invariants

- Pull must not overwrite unsynced local changes incorrectly.
- Local cursor must not advance before successful local apply.
- Pulled copies of the client's own operations must be ignored or matched
  idempotently.
- Merge logic belongs in services/engines, not SwiftUI views.

## Explicit Assumptions

- Pull apply is serialized with local mutation writes.
- If a remote operation cannot be decoded, the app records sync error and does
  not advance past it silently.

## Atomic Work

- Add `SyncInbox` or applied-operation tracking.
- Add pull transport call.
- Add merge services per entity category.
- Add cursor persistence.
- Add idempotent apply for already-known operations.
- Add UI status for pull errors.
- Add tests with remote create/update/delete fixtures.

## Edge Cases

- Remote change arrives while local outbox has unsynced edit to same entity.
- Remote delete for an entity edited locally.
- Pull response includes unsupported schema version.
- Duplicate operation appears in pull response.
- App crashes after applying records but before saving cursor.

## Done Criteria

- Remote operations can be applied locally without destructive import.
- Cursor behavior is safe under failure.
- Conflict policy tests pass for inbound merge.

## Verification

- Unit-test remote create, update, delete, duplicate pull, and decode failure.
- Manual two-client test once backend is available.
