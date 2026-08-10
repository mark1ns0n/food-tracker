# 031 - iOS Sync Settings And Device Identity

## Goal

Add local sync settings and stable device identity to `foodtracker`.

## Previous Behavior

- The app has no sync settings, server URL, device ID, token, or sync status.
- Backup settings are local-only.

## New Behavior

- The app can store sync enabled/disabled state.
- The app stores a stable device ID and auth token.
- The user can see whether sync is configured.

## Invariants

- Token storage uses Keychain, not SwiftData plain text.
- Disabling sync does not delete local data or pending outbox entries.
- Missing/invalid server URL must not crash normal local app flows.

## Explicit Assumptions

- The first UI is a minimal settings area, not a full account screen.
- Device ID can be generated locally before pairing.
- Server URL may point to LAN or public domain depending on mPi5 exposure.

## Atomic Work

- Add `SyncSettings` model or settings storage.
- Add `DeviceIdentityService`.
- Add Keychain token storage.
- Add settings UI for:
  - enabled/disabled
  - server URL
  - pairing state
  - last sync status
- Add validation for server URL.
- Add tests for device ID persistence and token handling where feasible.

## Edge Cases

- App reinstall.
- Backup restore includes sync settings but not Keychain token.
- User disables sync with pending local outbox.
- User changes server URL.
- Device ID collision is detected by backend.

## Done Criteria

- Sync settings can be configured without starting actual sync.
- Device identity persists across app restarts.
- Secrets are not stored in backups by default.

## Verification

- Build the iOS app.
- Manually set sync settings and restart app to confirm persistence.
- Confirm backup output does not include auth token.
