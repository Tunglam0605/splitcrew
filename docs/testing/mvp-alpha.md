# SplitCrew Android Alpha Test Plan

## Purpose

Validate the Android-first local-first application and owner-hosted LAN workflow without allowing a green build to depend on manual smoke tests alone.

The current development line is v0.13 alpha.

## Automated acceptance gates

Every feature branch and `main` must keep these gates green:

1. Foundation package analyze/tests.
2. Flutter analyze.
3. Focused regression tests for high-risk feature slices.
4. Full Flutter test suite.
5. Android debug APK build.
6. APK artifact upload.

Current focused mobile gates include:

- trip summary PNG/share UI;
- repayment VietQR PNG/share UI;
- member profile/payment offline synchronization;
- settlement ledger, SQLite v3→v4 migration, settlement UI and encrypted backup/restore.

## Current testable scope

### Local canonical mode

- Create a trip and members.
- Add/edit/delete expenses with multiple payers.
- Equal, exact, percentage and share/weight allocation.
- Deterministic balances and debt simplification.
- SQLite canonical persistence with migrations.
- Receipt evidence in SplitCrew-managed local storage.
- Safe VietQR routing profiles.
- Exact repayment QR generation, save and share.
- Canonical trip summary PNG export/share.
- Encrypted owner backup and recovery.
- Append-only settlement acknowledgement history.

### Owner-host LAN mode

- Start/stop owner host.
- Generate short-lived one-time member invite.
- Scan invite QR or paste the payload.
- Authenticate/pin host + trip identity.
- Fetch canonical snapshots.
- Receive WebSocket revision hints with polling fallback.
- Queue offline expense/profile/payment/settlement mutations.
- Idempotently retry queued operations.
- Surface entity conflicts instead of silent last-write-wins.

## Core invariants

1. Monetary values are integer minor units.
2. Every expense conserves money exactly.
3. All member balances sum to zero.
4. Deterministic settlement transfers clear the current balances.
5. Cached member state is never canonical before owner acceptance.
6. Retrying an operation UUID cannot apply it twice.
7. A member may mutate only the resources allowed for that member.
8. Settlement acknowledgement is append-only and can record only a current exact suggested transfer at commit time.
9. Historical settlement payments remain valid if later expenses change the current debt graph.
10. Backup restore validates authenticated encryption, archive structure, receipt hashes and canonical model invariants before replacement.

## Manual acceptance scenarios

### A. Expense conservation

Create a 1,000,000 VND expense with multiple payers and any supported split method.

Expected: payer sum and allocation sum must both equal exactly 1,000,000 VND. Invalid totals cannot be committed.

### B. Offline member mutation

1. Join an owner-hosted trip from another phone.
2. Disconnect the member phone from the owner LAN.
3. Edit an expense created by that member or change that member's own profile.
4. Reconnect to the owner network.

Expected: the cached canonical state is not silently modified while offline; the operation appears pending, then commits or becomes explicitly blocked after owner validation.

### C. Repayment QR

1. Configure a safe payment-routing profile for the repayment recipient.
2. Open a deterministic suggested transfer.
3. Generate the VietQR.

Expected: bank/account/recipient and exact integer-VND amount match the current suggested transfer. The user can save or share the QR PNG without taking a screenshot.

### D. Settlement acknowledgement

1. Create expenses so member A owes member B.
2. On A's member device, choose **Record paid**.
3. Confirm the dialog.
4. Test once online and once while temporarily offline.

Expected:

- online: owner accepts the exact current suggestion and the debt disappears;
- offline: an acknowledgement is queued while the cached canonical debt remains visible;
- reconnect: owner revalidates the exact transfer before commit;
- duplicate retries cannot clear the debt twice;
- stale/changed debt becomes a conflict;
- settlement history records payer, recipient, amount, recorder and time.

### E. Historical payment plus later expense

1. Record a settlement payment that clears the current debt.
2. Add a later expense that creates a new debt, potentially in the opposite direction.
3. Restart the app and perform an encrypted backup/restore.

Expected: the old payment history remains valid and the new current debt is computed from the combined expense + payment ledger.

### F. SQLite migration

Install/open a database created with schema v3, then start v0.13.

Expected: schema upgrades to v4 without deleting the existing trip/member data; the settlement acknowledgement table becomes available and future acknowledgement history survives restart.

### G. Owner recovery

Create expenses, receipts, payment routing and settlement history; export an encrypted backup and restore it onto a clean local state.

Expected: canonical trip data, settlement history and receipt evidence are restored; a wrong passphrase or modified ciphertext is rejected.

## Android CI artifact

1. Open GitHub Actions.
2. Open the latest successful **MVP checks and Android build** run on `main`.
3. Download `splitcrew-android-debug`.
4. Extract and install `app-debug.apk` using Android's user-authorized package installation flow.

The debug APK is for testing. Signed public distribution remains a later release gate.

## Remaining production acceptance

- Authenticated/encrypted LAN transport hardening.
- Receipt-media synchronization between owner/member devices.
- Accessibility and privacy review.
- Signed public release and upgrade/migration matrix across released schemas.
- Smart receipt OCR/item assignment after the recovery/sync surfaces remain stable.
