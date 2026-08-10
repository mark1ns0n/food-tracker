# 035 - Remote Change Notification Strategy

## Goal

Make changes from another phone arrive promptly using a realistic iOS strategy.

## Previous Behavior

- There is no remote change notification.
- Another phone's changes are invisible until manual backup/import.

## New Behavior

- Backend can signal that remote changes exist.
- The app pulls changes after foreground, manual refresh, and optional push or
  polling trigger.
- User-visible data changes still come from pull/apply, not from notification
  payloads.

## Invariants

- Notification payloads must not be treated as authoritative data.
- If APNs/silent push fails, foreground pull still corrects state.
- Remote notification delivery must not create duplicate local operations.
- Private data should not be exposed in notification payloads.

## Explicit Assumptions

- iOS silent push is not guaranteed; the app must work without it.
- If the service is only reachable on home LAN, phones outside the LAN need VPN,
  public ingress, or delayed sync.
- Phase one may ship with foreground/manual pull before APNs is implemented.

## Atomic Work

- Decide phase-one remote-change trigger:
  - foreground/manual pull only
  - periodic polling while app is open
  - APNs silent push
- If APNs is chosen, add server-side device push token storage.
- Add iOS push token registration and update flow.
- Add backend "changes available" notification after accepted push from one
  device.
- Ensure notification handler only schedules a pull.
- Add fallback polling/foreground refresh.

## Edge Cases

- APNs token changes.
- Phone is offline when push is sent.
- Push arrives before backend transaction commits.
- App is force-quit.
- Backend is LAN-only and phone is on cellular.

## Done Criteria

- The app has a documented and implemented strategy for discovering
  other-device changes.
- Remote change trigger schedules pull, not direct mutation.
- Fallback behavior is explicit.

## Verification

- Test foreground/manual pull path first.
- If APNs is implemented, use a near-term manual remote push and confirm the app
  pulls afterward.
