# Changelog

All notable changes to SplitCrew are documented here.

## [Unreleased] — v0.13.0-alpha

### Added

- Append-only settlement acknowledgement records in canonical trip state.
- Settlement history UI showing payer, recipient, amount, recorder and timestamp.
- Owner-authorized and member self-outgoing `markSettlement` operations through the existing durable queue.
- SQLite schema v4 migration with persisted settlement acknowledgement history.
- Backup/snapshot round-trip coverage for settlement history.
- Focused tests for restart persistence, offline queueing, idempotency, authorization, stale/double acknowledgement rejection and schema migration.

### Ledger semantics

- Recorded payments adjust member balances without mutating or deleting expense history.
- A payment is accepted only when its exact from/to/amount is a current owner-side settlement suggestion at commit time.
- Historical payments remain valid after later expenses change the current debt graph; restore validation therefore checks append-only structure and authorization rather than replaying old payments against the final expense set.

## v0.12.0-alpha

### Added

- Member self-profile editing from the synchronized member workspace.
- Durable queued rename-member and payment-profile mutations using the existing SQLite pending-operation queue.
- Member entity-version and payment-account entity-version guards in addition to canonical trip revision checks.
- Focused regression tests for offline queue behavior, idempotency, self-only authorization and stale member/payment versions.

### Safety / consistency

- Member devices never mutate their cached canonical replica before the owner host accepts the operation.
- Entity-version conflicts refresh the canonical snapshot when possible before the queued operation is blocked for review.
- Payment profile creation uses a nullable expected version: null explicitly means the member expects no existing owner-side profile.
- Member-side payment removal is not silently emulated until a dedicated remove operation exists.

## v0.11.0-alpha

### Added

- Canonical trip summary screen with total spend, member/expense/receipt counts, per-member balances, deterministic settlement, trip revision and generation timestamp.
- Save the canonical trip summary as a PNG.
- Share the canonical trip summary directly through the platform share sheet.
- Save or share an exact-amount VietQR repayment card as PNG without taking a screenshot.
- Reusable PNG export adapter for Flutter render boundaries.
- Member devices may export summaries from owner-committed canonical snapshots; pending local operations remain excluded.

### Safety / robustness

- PNG rendering uses a hard pixel budget to reduce out-of-memory risk on unusually long summaries.
- Repayment exports include recipient, bank routing details, transfer content and exact integer-VND amount so users can verify the transfer before confirming it.

## v0.10.0-alpha

### Added

- Encrypted portable owner backup/recovery for canonical trip data, payment-routing profiles and receipt evidence.
- Argon2id passphrase key derivation and AES-GCM-256 authenticated encryption.
- ZIP payload validation with bounded sizes, strict entry allow-listing and receipt SHA-256 verification.
- Fresh-device restore UX and destructive-restore confirmation.
- Staged receipt restore plus atomic canonical SQLite replacement.
- Regression tests for encrypted round-trip, wrong passphrase, ciphertext tampering and canonical restore.

### Safety

- Backup/restore is blocked while live owner-host synchronization can mutate canonical state.
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
- Accessibility/privacy acceptance.
- OCR/item assignment.
