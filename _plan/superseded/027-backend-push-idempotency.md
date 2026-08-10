# 027 - Backend Push Idempotency

## Goal

Implement idempotent batch push so clients can retry local outbox entries
without duplicating remote operations.

## Previous Behavior

- No remote push exists.
- The `superapp` reference accepts every envelope and increments sequence even
  for duplicates.

## New Behavior

- Backend accepts a batch of operations.
- Duplicate `operationID` values return the original acceptance result.
- Accepted operations receive server sequence numbers.
- Batch validation is deterministic.

## Invariants

- Retrying after timeout must be safe.
- Partial batch failure must be explicit.
- Accepted operations must remain append-only.
- Backend must not trust client ordering as server ordering.

## Explicit Assumptions

- Phase one can accept batches in request order after validation, while server
  sequence is the source of truth for pull order.
- Large offline queues may be split by client batch size.

## Atomic Work

- Implement push transaction.
- Validate every envelope before writing.
- Store operations with unique operation IDs.
- Update entity state according to conflict policy.
- Return accepted/rejected status per operation.
- Add push metrics/log fields for debugging.
- Add tests for duplicate retry and partial failure.

## Edge Cases

- Same operation pushed twice by same phone.
- Same operation ID pushed with different payload.
- Batch contains valid and invalid operations.
- Batch updates the same entity multiple times.
- Database transaction fails halfway through.

## Done Criteria

- Backend push is idempotent.
- Client can safely retry the same outbox entries.
- Entity state matches accepted operation sequence.

## Verification

- Backend tests push the same batch twice and confirm operation count and server
  sequences do not duplicate.
- Backend tests cover altered duplicate payload rejection.
