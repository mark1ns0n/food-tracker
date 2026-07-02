# 029 - Backend Bootstrap Snapshot

## Goal

Let a new or reset phone initialize from backend state without replaying an
unbounded operation log.

## Previous Behavior

- A new phone starts empty unless manually restored from a local backup.
- There is no backend state snapshot.

## New Behavior

- Backend can return current entity state plus a cursor.
- A newly paired phone can bootstrap, then continue incremental pull after the
  returned cursor.

## Invariants

- Bootstrap must include tombstone state needed to avoid resurrecting deleted
  records from old local data.
- Bootstrap cursor must represent the exact snapshot boundary.
- Bootstrap must not mutate server state except optional audit metadata.

## Explicit Assumptions

- Phase one bootstrap returns JSON state, not a compressed binary archive.
- Large datasets are small enough for paginated JSON bootstrap in this personal
  app.

## Atomic Work

- Add bootstrap endpoint implementation.
- Return current non-deleted state and relevant tombstones.
- Include server cursor.
- Add optional entity type filter only if needed.
- Add tests for empty, populated, and deleted-state bootstrap.

## Edge Cases

- New phone bootstraps while another phone pushes.
- Bootstrap interrupted halfway.
- Backend contains entity schema newer than app supports.
- Phone has local unsynced outbox before bootstrap.

## Done Criteria

- A newly paired phone can get backend state and cursor.
- Subsequent pull after bootstrap does not duplicate bootstraped records.

## Verification

- Backend test creates state, calls bootstrap, then pulls after returned cursor
  and confirms only later operations appear.
