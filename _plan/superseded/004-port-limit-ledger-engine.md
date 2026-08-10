# 004 - Port Limit Ledger Engine

## Goal

Move debt calculation logic from `ban` into a testable `foodtracker` domain
engine before wiring the UI.

## Previous Behavior

- Debt calculations live in `ban/ban/LimitBalanceEngine.swift` and
  `ban/ban/LimitHistoryWritePolicy.swift`.
- The engine uses a UTC business calendar for day boundaries.
- Ledger events include deltas, snapshots, and rollovers.

## New Behavior

- `foodtracker` has a standalone debt engine and write policy that can compute
  current debt state from persisted ledger events.
- UI views consume computed state instead of reimplementing business rules.

## Invariants

- UTC day-window behavior remains unchanged unless explicitly decided otherwise.
- Rollover entries are idempotent: running refresh more than once must not create
  duplicate rollovers.
- Delta ordering after seed snapshots remains deterministic.
- Overdrink/debt/surplus normalization remains bounded and non-negative.

## Explicit Assumptions

- The transferred day boundary is UTC, not the device local timezone.
- A debt unit has the same meaning as in `ban`: negative deltas add consumption
  debt, positive deltas repay debt.

## Atomic Work

- Copy or recreate `LimitBalanceEngine` under a foodtracker debt-domain name.
- Copy or recreate `LimitHistoryWritePolicy`.
- Keep the engine free of SwiftUI and SwiftData dependencies where possible.
- Add fixture builders for ledger events.
- Port the existing verification checks from `ban/Verification`.
- Fix any source/test mismatch found during the port before wiring UI.

## Edge Cases

- Empty ledger state.
- Same-day consume then repay.
- Snapshot followed by later same-day delta.
- Future same-day delta.
- Multi-day rollover.
- Rollover at penalty threshold.
- Dubai/local timestamp that still belongs to the UTC product day.
- Idempotent rollover backfill.

## Done Criteria

- The engine compiles in `foodtracker`.
- Edge-case tests/checks pass without involving SwiftUI views.
- Domain assumptions are documented near the engine or in tests.

## Verification

- Run the ported engine checks.
- Confirm the checks cover midnight boundaries, same-day transitions,
  rollovers, empty state, threshold values, and idempotent rebuilds.
