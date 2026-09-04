# Changelog

All notable changes to SplitCrew are documented here.

The project follows Semantic Versioning once public releases begin.

## [Unreleased]

### Added

- SQLite local persistence with normalized trip/member/expense/payer/allocation tables.
- Repository abstraction with an in-memory test adapter.
- One-time migration from the v0.1 SharedPreferences payload.
- UUID identifiers for newly created trips, members, and expenses.
- Persisted timestamps and versions for mutable entities.
- Rename/delete crew flows.
- Rename/remove member flows with financial-reference safety checks.
- Expense editing with domain money-conservation revalidation.
- Expense detail/audit screen showing payers and final integer allocations.
- Paid/share/net explanation in the balances screen.
- Local regression tests for reload, editing, versions, member-removal safety, and settlement recalculation.

### Changed

- Mobile package version advanced to `0.2.0-alpha.1+2`.
- SharedPreferences is no longer the primary local database and remains only as a v0.1 import source.
- Expense list now opens an auditable detail view instead of exposing destructive actions as the primary interaction.

### Existing foundation

- Pure Dart domain package with integer-minor-unit money invariants.
- Deterministic split engine: equal, exact, percentage, shares, and per-item aggregation.
- Settlement engine with net balances and deterministic suggested transfers.
- Flutter Android-first MVP source.
- Android debug APK build artifact through GitHub Actions.
- Linux/macOS and Windows Android bootstrap scripts.
- Open-source architecture, security and contribution documentation.

### Known limitations

- Receipt capture, VietQR, signed releases, owner-hosted sync, and OCR are not yet implemented.
- SQLite schema v1 is intentionally a minimal implemented subset of the broader target schema.
