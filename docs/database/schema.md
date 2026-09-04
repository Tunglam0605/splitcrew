# Local Database Schema

SplitCrew keeps the financial core independent from persistence. SQLite is the physical local store for the Android MVP; future schema upgrades must use explicit database-version migrations.

## Implemented SQLite schema v1

### `trips`

- `id` UUID/text primary key
- `name`
- `currency_code`
- `created_at_ms`
- `updated_at_ms`
- `version`

### `members`

- `id` UUID/text primary key
- `trip_id` foreign key
- `name`
- `is_owner`
- `created_at_ms`
- `updated_at_ms`
- `version`

### `expenses`

- `id` UUID/text primary key
- `trip_id` foreign key
- `title`
- `total_minor` integer
- `created_by_member_id`
- `created_at_ms`
- `updated_at_ms`
- `version`

### `expense_payers`

- `expense_id`
- `member_id`
- `amount_minor`

Primary key: `(expense_id, member_id)`.

### `expense_allocations`

- `expense_id`
- `member_id`
- `amount_minor`

Primary key: `(expense_id, member_id)`.

The controller/domain boundary validates both money-conservation constraints before data is committed:

```text
sum(expense_payers.amount_minor)
              ==
       expenses.total_minor
              ==
sum(expense_allocations.amount_minor)
```

## Migration from v0.1 alpha

If SQLite contains no current trip, the application checks the legacy `splitcrew.trip.v1` SharedPreferences payload once. A valid payload is normalized with timestamps, validated through the current domain invariants, written to SQLite, and then removed from SharedPreferences.

SharedPreferences is not used for ongoing financial persistence after this import.

## Planned schema extensions

The logical target remains broader than SQLite v1. Later migrations may add:

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
- `sequence`
- `operation_type`
- `entity_id`
- `expected_version`
- `payload_json`
- `status` (`PENDING`, `ACCEPTED`, `REJECTED`, `CONFLICT`)
- `created_at`

## Invariants

1. Money is persisted as integer minor units.
2. A committed expense conserves money exactly.
3. New local entity IDs are UUIDs so future offline devices can create records without central ID allocation.
4. Mutable synchronized candidates carry versions and timestamps.
5. Member deletion is rejected while financial records still reference that member.
6. Financial deletion/tombstone semantics will be introduced before multi-device synchronization requires immutable history.
