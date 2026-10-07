# SplitCrew

**Offline-first group expense sharing for trips, friends, and everyday life.**

SplitCrew is an Apache-2.0 Flutter application for shared expenses. It works as a standalone local app and also supports an owner-hosted LAN group mode where one owner's phone is authoritative and nearby member phones keep cached replicas. A public cloud server is not required for same-network use.

> **Current development line: v0.14 alpha — stable durable-queue ordering and migration hardening on top of the tested v0.13 settlement baseline.**

## What is implemented

- Deterministic integer money arithmetic; no floating-point balance calculations.
- Equal, exact, percentage and share/weight splitting.
- Multiple payers, deterministic balances and debt simplification.
- SQLite persistence with UUIDs, timestamps and entity versions.
- Trip/member/expense editing with financial-reference guards.
- Camera/gallery receipt evidence stored in SplitCrew-managed local storage.
- Safe payment-routing profiles and VietQR repayment QR generation.
- In-app GitHub Releases version checks, SHA-256 APK verification and Android-authorized installation.
- Owner-hosted LAN sessions with short-lived single-use invites.
- QR invite rendering and member camera scanning.
- REST-authoritative commands/snapshots with authenticated WebSocket revision notifications and polling fallback.
- Durable offline mutation queue with stable enqueue sequencing across retry/restart for expense, profile/payment and settlement mutations.
- Idempotent operation IDs, optimistic revisions and explicit entity-version conflicts.
- Secure local storage for member session credentials.
- Encrypted backup/recovery for canonical trip data and receipt evidence.
- Save/share repayment VietQR as a PNG without taking a screenshot.
- Canonical trip summary PNG with totals, balances, deterministic settlement and revision metadata.
- Append-only settlement acknowledgement history that adjusts balances and synchronizes through the durable member queue.

See ROADMAP.md for remaining production work.

## Architecture

Presentation / Flutter UI → application controllers → deterministic domain/split/settlement core.

Persistence and synchronization remain adapters around that core: local SQLite, owner-host REST commands/snapshots, authenticated WebSocket revision notifications, durable offline queue, and encrypted backup/recovery.

### Core invariants

1. Domain logic does not depend on Flutter, SQLite, HTTP, WebSocket, camera or QR APIs.
2. Monetary values use integer minor units.
3. Every expense conserves money: sum(payers) == total == sum(allocations).
4. Split and settlement outputs are deterministic for identical inputs.
5. Local use remains available without Internet access.
6. The owner's host is authoritative; cached member state never silently becomes canonical.
7. Synchronized writes are idempotent and use explicit revision/version conflict handling.
8. Receipt binaries are not embedded in normal canonical sync snapshots.
9. Recovery import validates encryption, archive structure, receipt hashes and domain invariants before replacing local canonical state.

## Android alpha

GitHub Actions builds a debug Android APK from tested branches and main. Open Actions, select the latest successful MVP checks and Android build run, then download the splitcrew-android-debug artifact.

The debug APK is for testing. A signed public release is still a later milestone.

## Next production slices

1. Generalize the durable queue to the remaining mutable operation types.
2. Add receipt-media synchronization without putting binary data in JSON snapshots.
3. Harden authenticated LAN transport and session lifecycle.
4. Run accessibility/privacy/migration acceptance before signed public beta.
5. Add OCR/item assignment only after data recovery and sync surfaces are stable.

## Documentation

- docs/architecture/system-overview.md
- docs/architecture/local-host-sync.md
- docs/architecture/backup-recovery.md
- docs/database/schema.md
- docs/protocol/sync-protocol.md
- docs/testing/mvp-alpha.md

## Security

Do not post bank credentials, OTPs, private signing keys, session tokens, backup passphrases or sensitive receipt data in public issues. See SECURITY.md.

## License

Apache License 2.0 — see LICENSE.
