# System Architecture Overview

## Scope

SplitCrew is a mobile-first shared-expense application. The architecture must support two operating modes without changing the money-calculation core:

1. **Standalone local mode** — one phone manages the whole trip with no server.
2. **Owner-hosted group mode** — the owner phone becomes the authoritative host for nearby member devices.

Cloud synchronization may be added later as another infrastructure adapter.

## Layering

```text
Presentation (Flutter UI)
        │
        ▼
Application / Use Cases
        │
        ▼
Domain
├── Trip / Member
├── Expense
├── Money / Allocation
├── Split rules
└── Settlement
        │
        ▼
Repository Interfaces
   ┌────┴─────────────┐
   ▼                  ▼
Local persistence   Sync interfaces
(SQLite/Drift)      (protocol only)
                       │
              ┌────────┴────────┐
              ▼                 ▼
           Host adapter      Client adapter
```

## Dependency rule

Dependencies point inward. Domain packages must not import Flutter, SQLite, HTTP, WebSocket, camera, QR or platform APIs.

## Core modules

### Domain

Owns business entities, value objects and invariants.

### Split Engine

Transforms an expense and a split rule into exact member allocations. The sum of allocations must always equal the expense amount.

### Settlement Engine

Aggregates paid amounts and allocations into member balances, then produces a deterministic set of repayment instructions.

### Persistence

Stores trips, members, expenses, allocations, settlements, receipts and synchronization metadata locally.

### Sync Protocol

Defines commands, events, versions, acknowledgements and conflict responses. It does not define whether bytes travel through REST, WebSocket, LAN discovery or a future cloud service.

## Money invariant

Persist monetary values as integer minor units. Example: VND may use integer dong directly; currencies with cents store cents. Floating point is not permitted for final balance arithmetic.

## Non-functional constraints

- Normal expense entry should feel instant on-device.
- Core calculations must be deterministic and unit-testable.
- Loss of Internet must not block local usage.
- Loss of owner-host connection must not discard member-side pending operations.
- Every mutating synchronized entity must support stable IDs and version checks.
