# Changelog

All notable changes to SplitCrew are documented here.

## [Unreleased] — v0.10.0-alpha

### Added

- Encrypted portable owner backup/recovery for canonical trip data, payment-routing profiles and receipt evidence.
- Argon2id passphrase key derivation and AES-GCM-256 authenticated encryption.
- ZIP payload validation with bounded sizes, strict entry allow-listing and receipt SHA-256 verification.
- Fresh-device restore UX and destructive-restore confirmation.
- Staged receipt restore plus atomic canonical SQLite replacement.
- Regression tests for encrypted round-trip, wrong passphrase, ciphertext tampering and canonical restore.

### Safety

- Restore is blocked while the phone is a member client or while Owner Host Session is running.
- Backup passphrases are never persisted or recoverable by SplitCrew.
- Stale pending operations are cleared after canonical recovery.

## v0.9.0-alpha

### Added

- Camera scanning for owner-host invite QR codes.
- Manual invite paste remains available as a fallback.
- Invite scans reuse the existing expiry, host identity and trip identity validation path.

## v0.8.0-alpha

### Added

- Authenticated WebSocket revision notifications for LAN member sessions.
- REST event polling remains as a fallback with reconnect behavior.

## v0.7.0-alpha

### Added

- Durable SQLite pending-operation queue.
- Offline create/update/delete expense intents.
- Secure member-session storage.
- Idempotent retry and explicit conflict/blocked operation handling.

## Earlier alpha foundation

- Integer-minor-unit domain model and deterministic split/settlement engines.
- SQLite local persistence and legacy preference migration.
- Receipt capture, managed local evidence, payment profiles and VietQR repayment.
- Owner-host LAN protocol, invite/session model and canonical snapshots.
- GitHub Releases updater with semantic version comparison and SHA-256 APK verification.

### Remaining major work

- Signed public release pipeline and migration matrix.
- Receipt media synchronization.
- Settlement acknowledgement history/synchronization.
- Accessibility/privacy acceptance.
- OCR/item assignment.
