# Local Database Schema

SplitCrew keeps deterministic financial logic independent from persistence. SQLite is the Android canonical local store; every schema change uses an explicit versioned migration.

## Current canonical schema: v4

### v1 — Core trip ledger

#### `trips`

- `id` TEXT primary key
- `name`
- `currency_code`
- `created_at_ms`
- `updated_at_ms`
- `version`

#### `members`

- `id` TEXT primary key
- `trip_id` foreign key
- `name`
- `is_owner`
- `created_at_ms`
- `updated_at_ms`
- `version`

#### `expenses`

- `id` TEXT primary key
- `trip_id` foreign key
- `title`
- `total_minor` integer
- `created_by_member_id`
- `created_at_ms`
- `updated_at_ms`
- `version`

#### `expense_payers`

- `expense_id`
- `member_id`
- `amount_minor`

Primary key: `(expense_id, member_id)`.

#### `expense_allocations`

- `expense_id`
- `member_id`
- `amount_minor`

Primary key: `(expense_id, member_id)`.

The controller/domain boundary enforces:

```text
sum(expense_payers.amount_minor)
              ==
       expenses.total_minor
              ==
sum(expense_allocations.amount_minor)
```

### v2 — Payment routing

#### `payment_accounts`

- `id` TEXT primary key
- `member_id` UNIQUE foreign key
- `provider`
- `holder_name`
- `routing_identifier`
- `account_identifier`
- `created_at_ms`
- `updated_at_ms`
- `version`

Only transfer-routing data is stored. Passwords, PINs, OTPs, CVVs and banking login/session credentials are prohibited.

### v3 — Receipt evidence

#### `receipt_assets`

- `id` TEXT primary key
- `expense_id` foreign key
- `local_path`
- `sha256`
- `original_name`
- `mime_type`
- `size_bytes`
- `created_at_ms`
- `version`

Binary receipt files remain outside normal canonical JSON snapshots. Metadata references SplitCrew-managed local evidence.

### v4 — Settlement acknowledgement ledger

#### `settlement_acknowledgements`

- `id` TEXT primary key
- `trip_id` foreign key
- `from_member_id` foreign key
- `to_member_id` foreign key
- `amount_minor`
- `confirmed_by_member_id` foreign key
- `created_at_ms`
- `version`

These rows are append-only payment ledger entries. They do not rewrite expense history. Current balances are computed from all expenses and then offset by accepted payment entries:

```text
payer / debtor settlement:
from_member balance += amount
to_member balance   -= amount
```

At command commit time the owner host verifies that the exact `from/to/amount` is still a current settlement suggestion. On reload/restore, validation checks structure, member references, authorization and append-only sequence; it does not replay old payments against the final expense set because later expenses may legitimately change the current debt graph.

## Durable member operation queue

Offline member mutations use a separate SQLite database (`splitcrew-sync-queue.db`) containing serialized `SyncOperation` envelopes with:

- operation id
- trip id
- actor member id
- operation JSON
- queue state (`queued` or `blocked`)
- attempt count
- last error
- updated timestamp (diagnostics/retry metadata only)
- stable enqueue sequence

The queue remains non-authoritative. The owner-host commit is the only canonical mutation. Flush order is determined only by the stable enqueue sequence; retry timestamps must never reorder user intent.

## Migration guarantees

- v1 → v2 creates payment routing storage.
- v2 → v3 creates receipt metadata storage.
- v3 → v4 creates settlement acknowledgement history.
- pending queue v1 → v2 adds and deterministically backfills stable enqueue sequence using the legacy `updated_at_ms, operation_id` order.
- Missing JSON fields for newer collections normalize to empty lists so older backups/snapshots remain readable.
- The legacy `splitcrew.trip.v1` SharedPreferences payload is imported only when SQLite has no current trip, then removed after a successful normalized write.

## Invariants

1. Money is persisted as integer minor units.
2. A committed expense conserves money exactly.
3. New local entity IDs use UUIDs.
4. Mutable synchronized entities carry versions/timestamps where applicable.
5. Member deletion is rejected while expense, payment, or settlement history references that member.
6. Settlement acknowledgement history is append-only and cannot double-clear the same current debt through the normal command path.
7. Canonical state replacement during backup restore is atomic at the repository boundary.
