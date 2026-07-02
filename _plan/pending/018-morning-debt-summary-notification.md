# 018 - Morning Debt Summary Notification

## Goal

Send a morning local notification with the current debt amount and the amount of
debt added by daily unpaid-debt accrual.

## Previous Behavior

- Debt and accrual state are visible only when the user opens `foodtracker`.
- There is no scheduled reminder or morning summary.
- The app does not request notification permission for the debt workflow.

## New Behavior

- The user can enable a morning debt summary notification.
- The notification shows:
  - current total unresolved debt
  - how much debt was added by unpaid-day percent accrual since the previous
    summary window
- The app recalculates debt/accrual using the same domain engine as `Долги`
  before scheduling or presenting the summary.

## Invariants

- Notification numbers must come from the debt domain/service layer, not from
  duplicated SwiftUI logic.
- A scheduled notification must not create duplicate accrual ledger events.
- Opening the app after receiving or missing the notification must show the same
  debt state as the notification calculation.
- If notifications are denied, the debt engine still refreshes normally on app
  open/foreground.
- Existing debt behavior must remain unchanged when the notification feature is
  disabled.

## Explicit Assumptions

- iOS does not provide a reliable user-space cron job; use local notifications
  and app lifecycle/background refresh where available.
- Default notification time is morning local device time, initially `09:00`.
- Debt day-boundary and accrual calculation still use the debt engine's UTC
  product-day rule.
- `added by percent accrual` means accrual ledger/events generated for the last
  completed product day or since the previous delivered summary, whichever rule
  the implementation documents before shipping.
- If the app was not allowed to run before the scheduled time, the notification
  may show the last calculated summary; the next app foreground refresh must
  correct the debt state.

## Atomic Work

- Add a notification settings model for enabled/disabled state and morning time.
- Add a notification permission request flow in settings or the `Долги` area.
- Add a debt summary builder that returns total unresolved debt and newly added
  accrual amount from the shared debt engine.
- Add a scheduler service for local morning notifications.
- Decide whether to use `BGAppRefreshTask` as an opportunistic refresh before
  scheduling the next notification.
- Store enough metadata to avoid sending duplicate summaries for the same
  product day.
- Add a small UI control to enable/disable the summary and choose notification
  time.
- Ensure backup/restore preserves notification settings but does not duplicate
  delivered notification history.

## Edge Cases

- Notifications permission denied.
- Notification enabled, then app is force-quit before morning.
- No unresolved debt.
- Unresolved debt exists but `0%` accrual added nothing.
- Multiple debt entities accrue on the same day.
- Accrual created by foreground refresh before the scheduled notification.
- Device local timezone changes.
- UTC midnight differs from local morning date.
- User changes notification time after a notification is already scheduled.
- App restore from backup with an old scheduled notification state.

## Done Criteria

- User can enable and disable morning debt summary notifications.
- Morning notification content includes total unresolved debt and daily accrual
  added amount.
- Notification scheduling does not duplicate debt accrual.
- Denied permissions and disabled state are handled cleanly.
- The app UI and notification summary agree after refresh.

## Verification

- Build the app or run an equivalent Xcode compile check.
- Test the debt summary builder for no debt, debt without accrual, one accrued
  entity, and multiple accrued entities.
- Test scheduler behavior for enable, disable, time change, and duplicate
  product-day prevention.
- Manually schedule a near-future notification and confirm the delivered text
  matches the `Долги` screen after refresh.
