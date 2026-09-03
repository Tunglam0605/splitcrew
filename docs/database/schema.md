# Initial Local Database Schema

This document defines the logical schema. Physical Drift/SQLite implementation may evolve through migrations.

## Tables

### `trips`

- `id` UUID primary key
- `name`
- `currency_code`
- `owner_member_id`
- `revision` integer
- `created_at`
- `updated_at`

### `trip_members`

- `id` UUID primary key
- `trip_id` foreign key
- `display_name`
- `role` (`OWNER`, `ADMIN`, `MEMBER`)
- `status` (`ACTIVE`, `REMOVED`)
- `device_identity_id` nullable
- `created_at`
- `updated_at`
- `version`

### `expenses`

- `id` UUID primary key
- `trip_id`
- `title`
- `amount_minor` integer
- `currency_code`
- `category`
- `occurred_at`
- `created_by_member_id`
- `created_at`
- `updated_at`
- `version`
- `deleted_at` nullable tombstone

### `expense_payers`

- `expense_id`
- `member_id`
- `amount_minor`

Constraint: payer amounts sum exactly to `expenses.amount_minor`.

### `expense_allocations`

- `expense_id`
- `member_id`
- `amount_minor`
- `source` (`EQUAL`, `EXACT`, `PERCENT`, `SHARES`, `ITEMS`)

Constraint: allocation amounts sum exactly to `expenses.amount_minor`.

### `expense_items`

- `id` UUID primary key
- `expense_id`
- `name`
- `quantity`
- `amount_minor`
- `version`

### `expense_item_allocations`

- `item_id`
- `member_id`
- `amount_minor`

### `receipt_assets`

- `id` UUID primary key
- `expense_id`
- `local_uri`
- `sha256`
- `created_at`

### `payment_accounts`

- `id` UUID primary key
- `member_id`
- `provider_type`
- `holder_name`
- `routing_identifier`
- `account_identifier`
- `metadata_json`

No password, PIN, OTP or banking authentication credential is allowed.

### `settlements`

- `id` UUID primary key
- `trip_id`
- `from_member_id`
- `to_member_id`
- `amount_minor`
- `status` (`OPEN`, `SENT`, `CONFIRMED`, `CANCELLED`)
- `created_at`
- `updated_at`
- `version`

### `sync_operations`

- `id` UUID primary key
- `trip_id`
- `device_id`
- `sequence` integer
- `operation_type`
- `entity_id`
- `expected_version` nullable
- `payload_json`
- `status` (`PENDING`, `ACCEPTED`, `REJECTED`, `CONFLICT`)
- `created_at`

## Invariants

1. Money is persisted as integers in minor units.
2. A committed expense must conserve money: total payer amount = expense total = total allocation amount.
3. IDs are generated client-side as UUIDs so offline devices do not collide.
4. Synchronized mutable records carry versions.
5. Financial records use explicit deletion/tombstone semantics when synchronization requires history.
