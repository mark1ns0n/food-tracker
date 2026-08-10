# 022 - Sync Envelope Contract

## Goal

Define the JSON contract sent between iOS and the REST backend.

## Previous Behavior

- Backup JSON exists for local file backup.
- There is no remote JSON contract for incremental sync.
- The `superapp` sync skeleton has `SyncEnvelope`, but it only stores opaque
  payloads in memory.

## New Behavior

- `foodtracker` has versioned sync envelopes that can represent creates,
  updates, deletes, and settings changes.
- The REST backend can validate, store, and return envelopes by cursor.
- Payloads are schema-versioned per entity type.

## Invariants

- Sync envelope format must be backward compatible across app versions when
  possible.
- Backend must reject malformed envelopes instead of storing ambiguous data.
- Entity payloads must preserve domain-relevant timestamps and day-boundary
  fields.
- Secret tokens and local file paths must never be included in sync payloads.

## Explicit Assumptions

- JSON is the first wire format because it is easy to inspect and test.
- Binary payloads are out of scope for phase one.
- Server cursor order is append-log order, not client timestamp order.

## Atomic Work

- Define common envelope fields:
  - `operationID`
  - `entityID`
  - `entityType`
  - `action`
  - `schemaVersion`
  - `deviceID`
  - `clientCreatedAt`
  - `clientUpdatedAt`
  - `payload`
- Define backend-assigned fields:
  - `serverSequence`
  - `serverReceivedAt`
- Add JSON examples for at least `FoodEntry`, `DineInEntry`, `FastingEntry`,
  and one debt entity.
- Define tombstone payload shape.
- Define validation errors.

## Edge Cases

- Client sends a newer schema version than backend knows.
- Client sends duplicate operation ID.
- Client sends update for unknown entity ID.
- Client sends delete for already-deleted entity.
- Client clock is wrong.

## Done Criteria

- Envelope contract file exists and is referenced by backend and iOS tasks.
- Example payloads can be used as fixtures in later tests.
- Validation and versioning rules are explicit.

## Verification

- Validate example JSON fixtures with a deterministic parser or backend test
  once the scaffold exists.
- Manually check that every phase-one entity has enough fields to reconstruct
  local state.
