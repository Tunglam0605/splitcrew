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

Joining a trip should use a one-time invitation token encoded in a QR code. After approval, the device receives/creates a persistent device identity associated with a `TripMember`.

A `TripMember` is not the same object as a global online account. This allows members to exist without an Internet account.

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

## Transport

The protocol layer must remain transport-independent. Initial implementations may use:

- HTTP/REST for request-response commands and snapshots;
- WebSocket for realtime canonical events;
- local network discovery for host discovery.

Bluetooth/Wi-Fi Direct or a cloud relay can be added later without changing domain rules.

## Host failure

The first implementation should support explicit encrypted/exportable trip backup. Host promotion/replication is a later capability and must not be faked with unsafe implicit election.
