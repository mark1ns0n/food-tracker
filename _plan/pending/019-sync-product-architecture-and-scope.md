# 019 - Sync Product Architecture And Scope

## Goal

Define the offline-first synchronization architecture for `foodtracker` before
building the REST backend or changing local persistence.

## Previous Behavior

- `foodtracker` is local-first SwiftData storage with local backup/restore.
- A change made on one phone is not visible on another phone.
- There is no remote source of truth, sync cursor, device identity, or conflict
  policy.

## New Behavior

- The product has a documented sync contract:
  - every local mutation is saved locally first
  - unsynced mutations are retried when network is available
  - other-device changes are pulled into the app without replacing local state
  - REST backend stores an append-only change log and durable entity state
  - deploy target is GitHub-built containers running on `mPi5` K3s
- The selected baseline follows common offline-first apps: local durable store,
  local outbox, idempotent push, cursor-based pull, tombstones, and a
  deterministic merge policy.

## Invariants

- The app must remain usable when the backend or internet is unavailable.
- Local UI must reflect the user's own tap immediately after the local save.
- Sync must never require destructive restore of the local SwiftData store.
- Backend unavailability must not corrupt local debt, food, fasting, delivery,
  dine-in, or backup data.
- Domain rules remain in app domain services; sync transports records and
  events but does not invent food/debt calculations.

## Explicit Assumptions

- `mPi5` means the K3s host documented in `/Users/mark1ns0n/projects/m/mPi5.md`.
- iOS cannot receive arbitrary backend pushes directly; any "remote change
  arrived" behavior uses APNs/silent push where available or foreground/polling
  pull as a fallback.
- The first production backend is a private personal service, not a public
  multi-tenant SaaS.
- The existing `superapp/Server/sync-server` is a useful API-shape reference
  (`push`, `pull`, `bootstrap`, `ack`), but its in-memory store is not
  production-ready.

## Atomic Work

- Write a short architecture note describing local outbox, backend log, pull
  cursor, tombstones, conflict handling, and deployment path.
- Decide the first backend stack after comparing:
  - Swift/Vapor reuse from `superapp`
  - Go or Rust minimal REST service
  - Node/TypeScript service
- Choose the initial syncable feature set for phase one.
- Document what is intentionally out of scope for phase one.
- Define high-level API routes and data flow diagrams.
- Add a risk list for iOS background execution and home-server availability.

## Edge Cases

- Phone is offline for several days and accumulates many local edits.
- Two phones edit the same entity before either phone pulls.
- Backend accepts a push, but the phone crashes before storing the returned
  cursor.
- Backend is reachable on LAN but not from mobile internet.
- User restores an old local backup after sync has already run.

## Done Criteria

- The project has a written sync architecture and phase-one scope.
- The architecture explicitly states how local saves, retries, remote pulls,
  deletions, conflicts, and deployment work.
- The chosen backend stack and reasons are recorded.
- Later implementation tasks can reference this contract without re-deciding
  the whole system.

## Verification

- Review the architecture note against `mPi5.md` and the current
  `foodtracker` SwiftData/backup model list.
- Compare the proposed API shape with `superapp/Server/sync-server` and confirm
  all production gaps are listed.
- Confirm no SwiftData schema, backend code, or deployment manifests changed in
  this planning step.
