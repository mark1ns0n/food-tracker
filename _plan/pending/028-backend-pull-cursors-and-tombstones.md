# 028 - Backend Pull Cursors And Tombstones

## Goal

Implement cursor-based pull so a phone can fetch changes made on other phones.

## Previous Behavior

- There is no remote pull.
- Local backup restore is the only way to move data between devices.

## New Behavior

- Client sends its last accepted cursor.
- Backend returns operations after that cursor, including tombstones.
- Client can acknowledge a cursor after applying pulled changes locally.

## Invariants

- Pull order is server sequence order.
- Tombstones must be returned until all relevant clients can observe deletion.
- Pull must not omit operations from other devices.
- A client may receive its own previously pushed operation and must handle it
  idempotently.

## Explicit Assumptions

- Cursor is opaque to iOS even if internally it is a server sequence.
- Phase one keeps tombstones indefinitely; compaction is a later task.

## Atomic Work

- Implement pull query after cursor.
- Include tombstones and schema versions in responses.
- Add optional page size/limit.
- Implement ack storage.
- Define behavior for unknown or too-old cursor.
- Add tests for empty pull, multi-device pull, and tombstone pull.

## Edge Cases

- Pull with no cursor.
- Pull after latest cursor.
- Cursor points beyond current sequence.
- Client has not acked for a long time.
- Deleted entity is pulled after deletion.

## Done Criteria

- Pull returns deterministic operations after cursor.
- Ack records last applied cursor.
- Tombstone behavior is documented and tested.

## Verification

- Backend tests push operations from two devices and pull from each cursor.
- Backend tests confirm deletes are visible in pull responses.
