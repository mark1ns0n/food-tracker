# 026 - Backend Device Auth And Pairing

## Goal

Add private device authentication so only approved phones can sync.

## Previous Behavior

- There is no backend auth.
- The `superapp` reference returns a hard-coded local token.

## New Behavior

- Each device has a durable device ID and a scoped sync token.
- New devices are paired intentionally.
- Backend rejects unauthenticated sync requests.

## Invariants

- Tokens are never stored in plan files, source code, or `mPi5.md`.
- Auth failure must not delete local data or local outbox entries.
- Device identity must be stable across app restarts.
- Revoked devices must not be able to push new operations.

## Explicit Assumptions

- Phase one can use a personal pairing code or admin-created token instead of a
  full account system.
- Token storage on iOS uses Keychain.
- Server secrets are provided via Kubernetes Secret, not ConfigMap.

## Atomic Work

- Define auth model and token scopes.
- Add pairing endpoint with one-time pairing code or admin bootstrap token.
- Hash server-side tokens before storage.
- Add auth middleware to sync routes.
- Add token revocation endpoint or admin procedure.
- Add tests for accepted, missing, invalid, and revoked tokens.

## Edge Cases

- Pairing code reused.
- Device token leaked and revoked.
- Phone reinstall creates a new device ID.
- Backend clock differs from client clock.
- User restores backup containing old device metadata.

## Done Criteria

- Sync routes require valid device auth.
- Pairing creates durable device records.
- Token handling is documented and tested.

## Verification

- Backend tests cover auth success/failure.
- Manual local `curl` confirms unauthenticated sync is rejected and paired token
  succeeds.
