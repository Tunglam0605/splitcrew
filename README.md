# SplitCrew

**Offline-first group expense sharing for trips, friends, and everyday life.**

SplitCrew is an Apache-2.0 open-source mobile app for recording shared expenses, splitting each bill fairly, and calculating who should pay whom. The long-term architecture supports an optional owner-hosted local group mode without requiring a public cloud server.

> **Status: v0.1.0 MVP alpha — Android test build available through GitHub Actions.**

## What is testable now

- Create a local trip/crew.
- Add members without online accounts.
- Add expenses with one or multiple payers.
- Equal split.
- Exact amount per person.
- Percentage split using integer basis points internally.
- Share/weight split.
- Deterministic per-item split in the core engine.
- Offline local persistence for the alpha app.
- Per-member net balances.
- Deterministic settlement/debt simplification.
- Delete expenses and recalculate immediately.

See [`docs/testing/mvp-alpha.md`](docs/testing/mvp-alpha.md) for the full test plan.

## Install the Android alpha

The repository automatically builds a debug APK on `main`:

1. Open **Actions**.
2. Select the latest successful **MVP checks and Android build** run.
3. Download the `splitcrew-android-debug` artifact.
4. Extract and install `app-debug.apk` on an Android phone.

The debug APK is for testing only and is not yet a signed public release.

## Run locally

Flutter's generated Android boilerplate is intentionally not maintained by hand in the repository. Generate it from the pinned project metadata first.

### Linux/macOS

```bash
git clone https://github.com/Tunglam0605/splitcrew.git
cd splitcrew
./scripts/bootstrap_mobile.sh
cd apps/mobile
flutter run
```

### Windows PowerShell

```powershell
git clone https://github.com/Tunglam0605/splitcrew.git
cd splitcrew
./scripts/bootstrap_mobile.ps1
cd apps/mobile
flutter run
```

## Architecture

```text
Flutter UI
   │
   ▼
Application state / local adapter
   │
   ├───────────────┐
   ▼               ▼
Domain        Split Engine
   │               │
   └───────┬───────┘
           ▼
   Settlement Engine
           │
           ▼
   Local persistence
           │
     future sync adapter
           │
      Owner Host / Client
```

### Dependency rules

1. Domain logic is independent from Flutter, storage, and networking.
2. Money is stored and calculated using integer minor units, never floating-point balances.
3. Every expense conserves money: `sum(payers) == total == sum(allocations)`.
4. Split and settlement results are deterministic for identical input.
5. Local use must remain possible without Internet access.
6. Owner-hosted synchronization is added only after the local financial core is stable.

## Repository structure

```text
splitcrew/
├── apps/
│   └── mobile/                  # Flutter MVP source
├── packages/
│   ├── domain/                  # Money, trip, member, expense invariants
│   ├── split_engine/            # Equal/exact/%/shares/per-item allocation
│   └── settlement_engine/       # Balances and suggested transfers
├── docs/
│   ├── architecture/
│   ├── database/
│   ├── decisions/
│   ├── product/
│   ├── protocol/
│   └── testing/
├── scripts/                     # Android scaffold bootstrap
└── .github/workflows/           # CI + Android APK artifact build
```

## Next milestones

The alpha intentionally does **not** pretend to have features that are not implemented yet. Next priorities are:

1. SQLite/Drift production persistence and migrations.
2. Receipt image capture.
3. Payment-account abstraction and VietQR.
4. Exportable trip summary.
5. Owner-hosted LAN mode with invite QR, roles, sync queue, versions, and conflict handling.
6. OCR/item assignment after the core UX is stable.

See [`ROADMAP.md`](ROADMAP.md) for details.

## Documentation

- [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
- [`docs/architecture/local-host-sync.md`](docs/architecture/local-host-sync.md)
- [`docs/database/schema.md`](docs/database/schema.md)
- [`docs/protocol/sync-protocol.md`](docs/protocol/sync-protocol.md)
- [`docs/testing/mvp-alpha.md`](docs/testing/mvp-alpha.md)

## Contributing

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## Security

Do not post bank credentials, OTPs, private signing keys, or sensitive receipt data in public issues. See [`SECURITY.md`](SECURITY.md).

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
