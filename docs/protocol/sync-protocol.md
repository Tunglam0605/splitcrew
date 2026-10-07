# Synchronization Protocol

## Purpose

Define owner-authoritative synchronization semantics independently from REST, WebSocket, Wi-Fi transport, or any future relay.

## Operation envelope

The implemented protocol uses `SyncOperation`:

```text
protocolVersion
operationId
tripId
actorMemberId
expectedTripRevision
type
payload
createdAtEpochMs
```

`operationId` is globally unique and is the idempotency key. `expectedTripRevision` protects canonical ordering.

## Implemented operation types

- `createExpense`
- `updateExpense`
- `deleteExpense`
- `addMember`
- `renameMember`
- `updatePaymentAccount`
- `markSettlement`

### Entity-level optimistic concurrency

Trip revision and entity version solve different problems.

- `updateExpense` / `deleteExpense` carry `expectedExpenseVersion`.
- `renameMember` carries `expectedMemberVersion`.
- `updatePaymentAccount` carries nullable `expectedPaymentAccountVersion`; `null` explicitly means “no owner-side account is expected yet”.
- `markSettlement` is validated semantically against the current owner-side settlement suggestion after any trip-revision rebase.

A stale trip revision may be rebased, but the operation payload keeps its entity expectation. The host must not silently overwrite a stale entity.

## Host result

`SyncOperationResult.status` is one of:

- `accepted`
- `duplicate`
- `conflict`
- `rejected`

Common error codes include:

- `STALE_REVISION`
- `ENTITY_VERSION_CONFLICT`
- `OPERATION_FORBIDDEN`
- `OPERATION_INVALID`
- `TRIP_MISMATCH`

Accepted operations produce a `CommittedSyncEvent` containing the resulting canonical trip revision.

## Idempotency

If the owner host receives the same `operationId` again, it returns `duplicate` and does not reapply the mutation.

This is especially important for payment acknowledgements: retrying a network request must never clear a debt twice.

## Offline queue and reconnect

A member device never promotes its cached replica to canonical state.

When the owner host is unavailable:

1. an allowed mutation is serialized to the durable SQLite pending queue;
2. the cached canonical trip remains unchanged;
3. the UI reports the mutation as queued.

When the host is reachable again:

1. the client refreshes or receives a revision notification;
2. queued operations are submitted in order;
3. `STALE_REVISION` causes a canonical refresh/rebase;
4. entity expectations remain unchanged;
5. an entity conflict becomes a blocked operation requiring user review;
6. an accepted commit removes the queue entry and refreshes the canonical replica.

## Settlement acknowledgement semantics

A non-owner member may submit `markSettlement` only for their own outgoing transfer. The owner may record any current suggested transfer.

The owner host revalidates the exact:

```text
fromMemberId
toMemberId
amountMinor
```

against the current deterministic settlement result before committing an append-only acknowledgement. If the debt changed or was already acknowledged, the host returns an entity conflict.

## Transport

Current LAN mode uses:

- REST for join, snapshots and authoritative operations;
- authenticated WebSocket messages as revision notifications only;
- REST polling as fallback/reconnect support;
- the same member session token for REST/WebSocket authentication;
- invite-pinned host/trip identity.

Notification transport never becomes a second source of truth.
