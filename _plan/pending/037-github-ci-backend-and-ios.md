# 037 - GitHub CI Backend And iOS

## Goal

Add GitHub build jobs for backend and iOS verification.

## Previous Behavior

- Build and verification are local/manual.
- There is no GitHub Actions workflow for `foodtracker` sync backend or iOS app.

## New Behavior

- Pull requests and commits run backend tests.
- iOS build/test checks run where available.
- CI produces clear failure output before deploy.

## Invariants

- CI must not require secrets for ordinary test jobs.
- Deploy jobs must be separated from test jobs.
- CI should not commit generated files back into the repo.

## Explicit Assumptions

- GitHub will be the build system.
- Backend container build can run on GitHub-hosted runners.
- iOS build requires macOS runner; if unavailable, backend CI still runs.

## Atomic Work

- Add backend build/test workflow.
- Add iOS build/test workflow or documented Xcode build check.
- Add contract fixture validation to CI.
- Add lint/format step if the selected stack supports it.
- Add dependency cache conservatively.
- Add branch protection guidance if needed.

## Edge Cases

- GitHub runner lacks required Xcode version.
- Backend tests need PostgreSQL.
- CI cache becomes stale.
- Workflow runs on docs-only plan changes.

## Done Criteria

- Backend tests run in GitHub Actions.
- iOS verification path is available and documented.
- Deploy cannot run before tests pass.

## Verification

- Trigger workflow on GitHub.
- Confirm backend test job passes.
- Confirm iOS job either passes or has a documented runner limitation.
