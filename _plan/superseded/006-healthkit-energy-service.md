# 006 - HealthKit Energy Service

## Goal

Bring HealthKit active and basal energy reads into `foodtracker` in a contained
service before debt UI depends on it.

## Previous Behavior

- `ban` uses `HealthKitManager` to read:
  - weekly active energy burned
  - today basal energy burned
  - active/basal energy for arbitrary date intervals
- `ban` has a HealthKit entitlement.
- `foodtracker` does not currently request HealthKit access for this workflow.

## New Behavior

- `foodtracker` can request HealthKit read authorization and expose active/basal
  kilocalorie values to the debt feature.
- Missing or denied HealthKit data degrades gracefully.

## Invariants

- The app must not crash when HealthKit is unavailable.
- Missing HealthKit values must not silently create fake calorie credit.
- Authorization should be requested once and refreshed when the app becomes
  active.

## Explicit Assumptions

- HealthKit active calories are used for weekly repayment credit.
- HealthKit basal calories are used only after subtracting completed meal
  calories.

## Atomic Work

- Add the HealthKit entitlement to `foodtracker`.
- Port `HealthKitManager` or create a renamed equivalent service.
- Wire app lifecycle refresh hooks without touching unrelated tabs.
- Add permission-denied and unavailable-state handling.
- Keep all HealthKit queries out of SwiftUI rows.

## Edge Cases

- HealthKit unavailable on simulator/device.
- User denies HealthKit permission.
- Weekly interval cannot be calculated.
- Query throws an error.
- Start date is not before end date.

## Done Criteria

- HealthKit service compiles and can be instantiated by `foodtracker`.
- Active and basal calorie reads refresh on launch/foreground.
- Debt UI can distinguish unknown calories from zero calories.

## Verification

- Build with the entitlement enabled.
- Run on a target where HealthKit is unavailable and confirm the app still
  launches.
- Run on a target with HealthKit access and confirm non-nil values appear when
  data exists.
