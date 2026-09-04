# SplitCrew

**Offline-first group expense sharing for trips, friends, and everyday life.**

SplitCrew is an Apache-2.0 open-source mobile app for recording shared expenses, splitting each bill fairly, and calculating who should pay whom. The architecture is intentionally local-first and can later add an owner-hosted local group mode without requiring a public cloud server.

> **Status: v0.2.0-alpha local-hardening candidate — Android test APK is built by GitHub Actions.**

## What is testable now

- Create, rename, and delete a local trip/crew.
- Add and rename members without online accounts.
- Safely remove members that are not referenced by financial records.
- Add expenses with one or multiple payers.
- Edit and delete expenses.
- Expense detail/audit view showing payers and final integer allocations.
- Equal split.
- Exact amount per person.
- Percentage split using integer basis points internally.
- Share/weight split.
- Deterministic per-item split in the core engine.
- SQLite persistence on Android with a normalized schema.
- One-time import of v0.1 SharedPreferences local data.
- UUID identifiers, timestamps, and entity versions prepared for future sync.
- Per-member paid/share/net explanation.
- Deterministic settlement/debt simplification.

See [`docs/testing/mvp-alpha.md`](docs/testing/mvp-alpha.md) for the alpha test plan.

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
TripController / application state
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
   TripRepository interface
           │
      ┌────┴────┐
      ▼         ▼
   SQLite     Memory test adapter
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
6. Persistent entities carry UUIDs, timestamps, and versions before multi-device synchronization is introduced.
7. Owner-hosted synchronization is added only after the local financial core and database are stable.

## Repository structure

```text
splitcrew/
├── apps/
│   └── mobile/                  # Flutter Android-first app
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

The next product slice is deliberately focused on evidence and repayment rather than networking:

1. Receipt image capture/attachment.
2. Payment-account abstraction and VietQR.
3. Shareable repayment QR and trip summary.
4. Owner-hosted LAN mode with invite QR, roles, sync queue, versions, and conflict handling.
5. OCR/item assignment after the core UX is stable.

See [`ROADMAP.md`](ROADMAP.md) for details.

## Documentation

- [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
- [`docs/architecture/local-host-sync.md`](docs/architecture/local-host-sync.md)
- [`docs/database/schema.md`](docs/database/schema.md)
- [`docs/protocol/sync-protocol.md`](docs/protocol/sync-protocol.md)
- [`docs/product/v0.2.0-alpha-plan.md`](docs/product/v0.2.0-alpha-plan.md)
- [`docs/testing/mvp-alpha.md`](docs/testing/mvp-alpha.md)

## Contributing

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## Security

Do not post bank credentials, OTPs, private signing keys, or sensitive receipt data in public issues. See [`SECURITY.md`](SECURITY.md).

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
