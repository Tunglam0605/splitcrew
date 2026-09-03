# SplitCrew

**Offline-first group expense sharing for trips, friends, and everyday life.**

SplitCrew is an open-source mobile application for tracking shared expenses, flexible bill splitting, group settlements, receipt evidence, and QR-based repayment. It is designed to remain useful without Internet access and to support an optional owner-hosted local group mode.

> Status: early architecture and MVP foundation.

## Product goals

- Fast expense entry on mobile.
- Equal, exact-amount, percentage, share-based, and per-item splitting.
- Multiple payers per expense.
- Clear per-member balances and optimized settlements.
- Receipt photos and auditable expense history.
- QR-assisted repayment, with VietQR as the first payment adapter.
- Offline-first operation.
- Optional owner-hosted local synchronization for travel groups without a cloud server.
- Architecture that can later add cloud synchronization without rewriting the domain core.

## Architecture principles

1. **Domain logic first** — split and settlement calculations are independent from Flutter, SQLite, networking, and UI.
2. **Local-first** — every device keeps a local database and remains usable while offline.
3. **Host-authoritative groups** — in local group mode, the owner device validates and publishes canonical trip state.
4. **Transport independence** — synchronization semantics are separate from HTTP/WebSocket/Bluetooth implementations.
5. **Auditable money calculations** — monetary values use integer minor units; no floating-point arithmetic for balances.
6. **Open source by default** — documentation, decisions, roadmap, issues, and releases are public.

## Planned repository structure

```text
splitcrew/
├── apps/
│   └── mobile/                  # Flutter application
├── packages/
│   ├── domain/                  # Core business entities and rules
│   ├── split_engine/            # Expense allocation algorithms
│   ├── settlement_engine/       # Group balance and debt minimization
│   ├── sync_protocol/           # Commands, events, versions and conflicts
│   └── shared_models/           # Stable cross-package DTOs/value objects
├── docs/
│   ├── architecture/
│   ├── database/
│   ├── protocol/
│   ├── product/
│   └── decisions/
├── .github/
│   ├── workflows/
│   └── ISSUE_TEMPLATE/
├── ROADMAP.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
└── LICENSE
```

## MVP scope

The first usable release will focus on the local mobile experience:

- Create a trip/group.
- Add members without requiring every member to create an online account.
- Add expenses and multiple payers.
- Split equally or by custom amount, percentage, or shares.
- Calculate member balances.
- Generate settlement instructions.
- Store data locally.
- Attach receipt images.
- Generate QR-based repayment information.

Owner-hosted LAN synchronization will be added only after the local calculation and persistence layers are stable.

## Development order

```text
Domain model
   ↓
Split engine
   ↓
Settlement engine
   ↓
Local database
   ↓
Mobile UI
   ↓
Receipt + QR
   ↓
Owner-hosted sync
   ↓
Offline synchronization + recovery
```

## Documentation

Start with:

- [`ROADMAP.md`](ROADMAP.md)
- [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
- [`docs/architecture/local-host-sync.md`](docs/architecture/local-host-sync.md)
- [`docs/database/schema.md`](docs/database/schema.md)
- [`docs/decisions/ADR-001-local-first.md`](docs/decisions/ADR-001-local-first.md)

## Contributing

Contributions are welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## Security

Please report security-sensitive issues according to [`SECURITY.md`](SECURITY.md) instead of posting sensitive details in a public issue.

## License

Licensed under the [Apache License 2.0](LICENSE).
