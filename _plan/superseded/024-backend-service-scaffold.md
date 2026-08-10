# 024 - Backend Service Scaffold

## Goal

Create the REST backend service skeleton for `foodtracker` sync.

## Previous Behavior

- `foodtracker` has no backend service.
- `superapp/Server/sync-server` has a Vapor skeleton with in-memory sync routes,
  but it is not part of `foodtracker`.

## New Behavior

- The repository contains a backend service with health checks and versioned
  REST routes.
- The service can run locally and in a container.
- The service has tests before persistence is added.

## Invariants

- The backend must not depend on iOS-only frameworks.
- The scaffold must keep routes, validation, storage, and auth boundaries
  separate.
- Health checks must work without requiring a database connection unless the
  endpoint explicitly checks readiness.

## Explicit Assumptions

- The first scaffold may reuse the route shape from `superapp` but must not
  reuse in-memory persistence as production behavior.
- The service will eventually run in K3s on `mPi5`.

## Atomic Work

- Add backend directory structure.
- Add package/module setup for the chosen stack.
- Add routes:
  - `GET /health`
  - `GET /v1/health`
  - `POST /v1/auth/device-pair`
  - `GET /v1/sync/bootstrap`
  - `POST /v1/sync/push`
  - `POST /v1/sync/pull`
  - `POST /v1/sync/ack`
- Add request/response DTOs.
- Add local run instructions.
- Add initial route tests.

## Edge Cases

- Empty push payload.
- Pull before bootstrap.
- Invalid JSON body.
- Unknown route version.
- Health check during service startup.

## Done Criteria

- Backend service builds locally.
- Health and placeholder sync routes respond.
- Tests cover route availability and basic validation.

## Verification

- Run backend build/test command.
- Run service locally and `curl` health plus one sync endpoint.
- Confirm no iOS app behavior changes in this scaffold step.
