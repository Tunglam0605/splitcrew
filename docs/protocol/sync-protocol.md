# Synchronization Protocol

## Purpose

Define stable synchronization semantics independently from REST, WebSocket or future cloud transports.

## Command envelope

```text
command_id
trip_id
device_id
member_id
client_sequence
command_type
entity_id
expected_version
payload
created_at
```

## Initial command types

- `CREATE_EXPENSE`
- `UPDATE_EXPENSE`
- `DELETE_EXPENSE`
- `ADD_MEMBER`
- `UPDATE_MEMBER`
- `REMOVE_MEMBER`
- `MARK_SETTLEMENT_SENT`
- `CONFIRM_SETTLEMENT`

## Host result

A host response is one of:

- `ACCEPTED`
- `REJECTED_VALIDATION`
- `REJECTED_PERMISSION`
- `VERSION_CONFLICT`
- `DUPLICATE_COMMAND`

Accepted commands produce canonical events containing the new entity version and trip revision.

## Idempotency

`command_id` is globally unique. Re-sending a command after a network interruption must not apply it twice.

## Ordering

Each client keeps a monotonic `client_sequence`. The host keeps a monotonic per-trip `revision`. Client sequence protects operation ordering; trip revision supports catch-up synchronization.

## Snapshot/catch-up

Client reconnect flow:

1. send `last_known_trip_revision`;
2. host returns missing canonical events when history is available;
3. otherwise host returns a current snapshot;
4. client reconciles local replica;
5. client submits pending commands.

## Conflict rule

Financial entities use optimistic concurrency. Update/delete commands must carry `expected_version`. A mismatch is reported as `VERSION_CONFLICT`; the host must not silently overwrite canonical state.
