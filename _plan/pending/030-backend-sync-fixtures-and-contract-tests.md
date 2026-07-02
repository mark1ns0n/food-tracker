# 030 - Backend Sync Fixtures And Contract Tests

## Goal

Add deterministic fixtures and tests for the backend sync contract before iOS
integration depends on it.

## Previous Behavior

- No sync fixtures exist.
- Backup fixtures are local-only.

## New Behavior

- Backend has fixtures for representative `foodtracker` entities and sync
  operations.
- Contract tests validate request/response shapes and edge cases.

## Invariants

- Fixtures must not contain real personal data or secrets.
- Tests must cover edge cases, not only happy paths.
- Backend contract changes must break tests if iOS would break.

## Explicit Assumptions

- Fixtures are stored in the repo and reviewed like code.
- The iOS client may later reuse the same fixtures for decoding tests.

## Atomic Work

- Add fixture JSON files for create, update, delete, bootstrap, pull, and auth.
- Add backend decoding/validation tests.
- Add persistence tests for idempotency and cursor behavior.
- Add conflict-policy tests.
- Add a CI-friendly test command.

## Edge Cases

- Duplicate operation ID with changed payload.
- Delete followed by stale update.
- Unsupported schema version.
- Empty pull.
- Large batch split across requests.

## Done Criteria

- Backend sync behavior has deterministic test coverage.
- Fixtures document the contract better than prose alone.

## Verification

- Run backend test suite locally.
- Confirm fixture names and contents map to documented sync scenarios.
