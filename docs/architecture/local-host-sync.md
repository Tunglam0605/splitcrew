# Owner-Hosted Local Synchronization

## Goal

Allow a group travelling together to share one trip without requiring a public cloud server. The owner device is the authoritative host while each member device retains a local working copy.

## Roles

- **OWNER** — controls membership, trip settings and canonical state.
- **ADMIN** — optional delegated management role.
- **MEMBER** — can read the trip and perform allowed expense/payment operations.

## Data flow

```text
Member device
  Local DB
     │
     │ command + entity version
     ▼
Sync Client ───── LAN ─────▶ Owner Host
                              │
                              ├─ authenticate device/member
                              ├─ validate command
                              ├─ check entity version
                              ├─ commit canonical state
                              └─ broadcast accepted event
                                       │
                  ┌────────────────────┼─────────────────┐
                  ▼                    ▼                 ▼
               Member A             Member B          Member C
```

## Offline behavior

If the host cannot be reached, a member may continue using locally available data. Mutations that are safe to stage are written to an operation queue with status `PENDING`.

When the host returns:

1. client establishes a session;
2. client sends last known trip revision;
3. host returns missed canonical events;
4. client applies canonical events;
5. client submits pending operations in order;
6. host accepts or rejects each operation;
7. conflicts are surfaced explicitly instead of silently overwriting data.

## Identity

Joining a trip uses a short-lived, single-use invitation token encoded in a QR code. The owner displays the invite; the member can scan it with the camera or paste the same payload manually. The client verifies the invited host/trip identity before joining and pins the returned host identity for the saved member session.

A `TripMember` is not the same object as a global online account. This allows members to exist and join over the local network without an Internet account.

## Concurrency

Mutable synchronized entities carry a monotonically increasing `version`.

Example:

```text
Client reads Expense(version=7)
Client submits UpdateExpense(expectedVersion=7)
Host current version = 8
→ reject with VERSION_CONFLICT
```

Do not use silent last-write-wins for financial records.

The same optimistic concurrency rule now applies to member identity and repayment-routing profiles. A rename carries `expectedMemberVersion`. A payment-profile update carries `expectedPaymentAccountVersion`; `null` explicitly means the client expects no existing profile. Rebasing a stale trip revision must preserve these entity expectations so a later host apply can still detect an entity-level conflict.

## Transport

The protocol layer remains transport-independent. The current LAN implementation deliberately separates authority from notification:

- HTTP/REST is authoritative for join, snapshots, commands and the bounded event-feed fallback;
- WebSocket is notification-only and pushes the newest canonical trip revision after a committed operation;
- WebSocket messages do not carry financial payloads; clients fetch the canonical snapshot over authenticated REST;
- member clients keep slower REST polling as a fallback when the WebSocket is unavailable and reconnect the socket automatically;
- the same bearer session authenticates REST and WebSocket endpoints, and the member pins the invited host identity;
- local network discovery remains an infrastructure concern and does not change domain/sync semantics.

This keeps temporary socket loss from affecting correctness: it may increase refresh latency, but it cannot create a second source of truth. Bluetooth/Wi-Fi Direct or a cloud relay can be added later without changing domain rules.

## Host failure

The first implementation should support explicit encrypted/exportable trip backup. Host promotion/replication is a later capability and must not be faked with unsafe implicit election.
