# 032 - iOS Sync Transport And Retry Worker

## Goal

Add the iOS REST client and retry worker that pushes pending outbox entries.

## Previous Behavior

- There is no network sync client.
- Local mutations cannot reach a backend.

## New Behavior

- A sync transport sends authenticated REST requests.
- Pending outbox entries are pushed when sync is enabled and network is
  available.
- Retry state is persisted locally.

## Invariants

- Network failure must not remove pending outbox entries.
- Successful backend acceptance marks only accepted operations as synced.
- Retry scheduling must avoid tight loops.
- SwiftUI views must trigger high-level sync actions only, not build requests.

## Explicit Assumptions

- `URLSession` is enough for phase-one REST transport.
- Background execution is opportunistic; foreground/app lifecycle sync is the
  reliable baseline.

## Atomic Work

- Add `SyncTransport` protocol and REST implementation.
- Add request signing/auth header logic.
- Add `SyncRetryWorker` or orchestrator push path.
- Add exponential backoff metadata.
- Add batch sizing.
- Add logs/status for last error and last successful push.
- Add tests with fake transport.

## Edge Cases

- No internet.
- Backend returns unauthorized.
- Backend returns partial acceptance.
- Backend timeout after accepting batch.
- App exits during retry.

## Done Criteria

- Pending outbox entries can be pushed to a fake or local backend.
- Retry behavior is deterministic and persisted.
- Network errors preserve local pending work.

## Verification

- Unit-test worker with fake transport for success, failure, timeout, and
  partial acceptance.
- Run against local backend health/push endpoint once backend exists.
