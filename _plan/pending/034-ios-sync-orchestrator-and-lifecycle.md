# 034 - iOS Sync Orchestrator And Lifecycle

## Goal

Coordinate push, pull, retry, and status updates through one sync orchestrator.

## Previous Behavior

- The app starts backup checks on launch but has no sync lifecycle.
- There is no single owner for sync state.

## New Behavior

- A sync orchestrator runs push then pull on app launch, foreground, manual
  refresh, and scheduled opportunities.
- UI can display a concise sync status.
- Sync work is serialized to avoid overlapping pushes/pulls.

## Invariants

- Multiple triggers must not run overlapping sync loops.
- Local domain writes remain available while sync is idle or failed.
- App lifecycle sync must not duplicate backup or notification logic.

## Explicit Assumptions

- Foreground sync is the reliable path.
- Background refresh is best effort and may not run when iOS decides not to run
  it.

## Atomic Work

- Add `SyncOrchestrator`.
- Add app lifecycle hooks.
- Add manual "sync now" action in settings.
- Add serialized run guard.
- Add status model:
  - idle
  - pushing
  - pulling
  - success
  - failed
- Add tests for trigger coalescing.

## Edge Cases

- User taps sync repeatedly.
- App foregrounds while retry is already running.
- Sync disabled mid-run.
- Auth revoked during pull.
- Backup restore happens before next sync.

## Done Criteria

- Sync has one orchestration entry point.
- UI status is accurate enough for debugging.
- Repeated triggers do not create overlapping network work.

## Verification

- Unit-test orchestrator with fake worker/transport.
- Manual test repeated foreground/manual sync triggers.
