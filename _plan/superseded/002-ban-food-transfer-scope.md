# 002 - Ban Food Transfer Scope

## Goal

Define exactly which food-related behavior moves from the standalone `ban` app
into `foodtracker`, before copying code or changing schemas.

## Source Behavior

- `ban` has two main tabs: `Долги` and `Ban`.
- `Долги` tracks debt for configured consumables:
  - `Corona Extra`, limit `10`, ban name `Бухло`, calorie repayment base `148`.
  - `Энергетик`, limit `1`, ban name `Сладкое`, calorie repayment base `154`.
- `Ban` defines named day-of-month rules with per-day percentage coefficients.
- HealthKit active calories can offset or repay consumable debt.
- HealthKit basal calories are reduced by completed meal calories.
- Current `ban` bundle id is `com.mark1ns0n.ban`; `foodtracker` is
  `com.mark1ns0n.foodtracker`, so persisted stores are separate.

## Target Behavior

- `foodtracker` gains the food-related `Долги` workflow from `ban`.
- Tracking of alcohol, energy drinks, active kilocalories, meal completions, and
  repayment logic works inside `foodtracker`.
- The transfer does not regress existing `Food`, `Fasting`, `Dine-In`,
  `Delivery`, or backup behavior.

## Explicit Assumptions

- The first migrated scope is food/drink debt tracking, not a general habit ban
  product.
- The existing Russian labels from `ban` can be kept for the transferred debt
  UI.
- The old `ban` app remains the source of truth until the final migration task
  has verified imported data in `foodtracker`.

## Atomic Work

- Inventory all `ban` source files used by `Долги`.
- Mark which files are domain logic, persistence, HealthKit, and presentation.
- Identify which existing partial `foodtracker` Ban files are user changes and
  must not be overwritten blindly.
- Decide final names for transferred models and services.
- Write a short transfer boundary note in the implementation summary.

## Done Criteria

- The implementation team knows which `ban` behavior is in scope.
- Non-food `ban` behavior is explicitly excluded or deferred.
- Existing dirty worktree state in `foodtracker` is understood before edits.

## Verification

- Re-read `ban/ban/LimitsTabView.swift`, `BanEntry.swift`,
  `DailyLimit.swift`, `LimitBalanceEngine.swift`, `LimitHistoryEntry.swift`,
  `HealthKitManager.swift`, `CalorieRepaymentEntry.swift`,
  `CalorieWeeklyBalance.swift`, and `MealCompletionEntry.swift`.
- Compare the planned model list with `foodtrackerApp.swift` schema before
  changing the schema.
