# Local Host Session API

SplitCrew's local group mode is host-authoritative: the owner's phone accepts commands, validates them against the canonical trip revision, persists the accepted change, then exposes the resulting committed event to member devices.

This API is intended for same-LAN/hotspot use. It is not a public Internet API.

## Session flow

```text
Owner starts Host Session
        │
        ├─ creates a short-lived, single-use invite
        │
Member scans invite
        │
POST /v1/join
        │
        ├─ validates host/trip identity
        ├─ redeems invite exactly once
        └─ returns session token + canonical snapshot
        │
Member submits operation
        │
POST /v1/operations
        │
        ├─ authenticates member session
        ├─ validates authorization
        ├─ checks expected canonical revision
        ├─ applies domain operation
        └─ returns committed revision/event
        │
GET /v1/events?afterRevision=N
        │
        └─ member catches up on canonical events
```

## Endpoints

### `GET /v1/health`

Public LAN health probe. Returns only protocol/host/trip/revision identity data. No financial snapshot is exposed.

### `POST /v1/join`

Body:

```json
{"invite":"splitcrew://join/..."}
```

The invite contains the trip/member/host identity, local endpoint, an expiry timestamp, and a cryptographically-random token. The server accepts it at most once.

A successful response contains a random bearer session token and the canonical trip snapshot.

### `GET /v1/snapshot`

Requires the session bearer token. Returns the current canonical snapshot and revision.

### `POST /v1/operations`

Requires the session bearer token. The authenticated member must match `actorMemberId` in the submitted operation. The host backend also enforces role/operation authorization.

Important results:

- `200 accepted` — operation committed and canonical revision advanced once.
- `200 duplicate` — the operation ID was already processed; the prior canonical result is returned without applying it again.
- `409 conflict` — `expectedTripRevision` is stale; refresh before retrying.
- `403` — session actor is not authorized for the operation.
- `422 rejected` — the operation is structurally valid but cannot be accepted by canonical state.

### `GET /v1/events?afterRevision=N`

Authenticated catch-up feed. The first implementation uses bounded REST polling so correctness can be stabilized before a WebSocket push adapter is added. Event semantics are transport-independent.

## Security boundaries

- Invite tokens are random, short-lived, and single-use.
- Session tokens are random and exist only while the Host Session is running.
- The member pins `hostId` from the invite/join handshake in the mobile integration layer.
- There is no raw SQL/database mutation endpoint.
- Financial credentials such as passwords, PINs, OTPs, access tokens, or banking sessions are never part of the protocol.
- Payment routing data may sync only through the existing safe `PaymentAccount` model.

## Next transport step

After REST integration is validated on two Android devices, a WebSocket event channel can replace polling for lower-latency committed-event delivery without changing operation, result, snapshot, or revision semantics.
