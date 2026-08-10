# 042 - End To End Two Device Sync Verification

## Goal

Verify the full sync loop with two clients before calling the feature done.

## Previous Behavior

- No two-device sync exists.
- Local testing can only prove single-device behavior.

## New Behavior

- A change made on phone A is saved locally, pushed, pulled by phone B, and
  appears in phone B's app.
- A change made on phone B follows the same path back to phone A.
- Offline edits reconcile after internet returns.

## Invariants

- Local save always precedes remote push.
- Pull apply must be idempotent.
- Domain behavior must match the pre-sync app after data is synchronized.

## Explicit Assumptions

- Simulator plus physical phone is acceptable for the first end-to-end test if
  two physical phones are not available.
- LAN-only mPi5 endpoint limits testing outside home network unless VPN/public
  ingress exists.

## Atomic Work

- Prepare two device identities.
- Pair both clients to backend.
- Run create/update/delete flows for selected phase-one entities.
- Run offline queue scenario.
- Run conflict scenario from the policy file.
- Verify app restart and backend restart.
- Record manual test script.

## Edge Cases

- Phone A offline creates several entries, phone B edits same area online.
- Backend restarts between push and pull.
- Phone B pulls duplicate own operation.
- One phone has old app version.
- Delete/restore conflict.

## Done Criteria

- Two-device sync works for phase-one entity set.
- Offline queue flush works.
- Conflict fixtures behave as documented.
- Manual test script is stored in the repo.

## Verification

- Run backend tests and iOS build.
- Execute manual two-client script.
- Confirm backend logs and app UI state agree after sync.
