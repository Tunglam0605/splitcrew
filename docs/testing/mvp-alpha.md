# SplitCrew MVP Alpha Test Plan

## Purpose

This build validates the local expense workflow before owner-hosted networking, receipt OCR, and payment QR are introduced.

## Current testable scope

- Create one local trip/crew.
- Add members without online accounts.
- Add an expense with one payer or multiple payers.
- Split equally.
- Split by exact amount.
- Split by percentage with up to two decimal places.
- Split by integer shares/weights.
- Persist the trip locally across app restarts.
- Calculate per-member net balances.
- Generate deterministic suggested settlement transfers.
- Delete an expense and recalculate balances.

Per-item splitting is implemented and unit-tested in the core engine but is not exposed in the alpha UI yet.

## Android installation from GitHub Actions

1. Open the repository's **Actions** tab.
2. Open the latest successful **MVP checks and Android build** run on `main`.
3. Download the `splitcrew-android-debug` artifact.
4. Extract `app-debug.apk`.
5. Copy the APK to an Android phone and allow installation from that source when Android asks.

This is a debug build intended only for testing.

## Local developer run

Requirements:

- Flutter 3.35.2 or a compatible newer stable version.
- Android SDK and a connected Android device/emulator.

Linux/macOS:

```bash
./scripts/bootstrap_mobile.sh
cd apps/mobile
flutter run
```

Windows PowerShell:

```powershell
./scripts/bootstrap_mobile.ps1
cd apps/mobile
flutter run
```

The bootstrap script generates only Flutter's Android platform boilerplate. Product source remains committed in `apps/mobile/lib`.

## Acceptance scenarios

### A. Equal split

1. Create `Da Nang 2026` with owner `Lam`.
2. Add `Hoang` and `Thanh`.
3. Add expense `Dinner` = `1,000,000` VND.
4. Select Lam as payer and all three as participants.
5. Select Equal.

Expected: allocations total exactly 1,000,000 VND, with any remainder distributed deterministically.

### B. Different amount per person

Use a 600,000 VND expense with:

- Lam: 120,000
- Hoang: 180,000
- Thanh: 300,000

Expected: save succeeds. If the values do not total 600,000, save is rejected.

### C. Multiple payers

Create a 1,000,000 VND expense and enable Multiple payers:

- Lam paid 600,000
- Hoang paid 400,000

Expected: save succeeds only when payer amounts total exactly 1,000,000 VND.

### D. Settlement

After several expenses, open Balances.

Expected:

- all member net balances sum to zero;
- positive members should receive money;
- negative members should pay;
- suggested transfers clear the balances exactly.

### E. Offline persistence

1. Add members and expenses.
2. Force-close the app.
3. Disable Wi-Fi/mobile data.
4. Reopen the app.

Expected: local trip, expenses, balances, and settlements remain available.

## Known alpha limitations

- Android-first; iOS platform scaffold is not generated yet.
- Local persistence currently uses `SharedPreferences` JSON as an alpha adapter; the production persistence milestone remains SQLite/Drift.
- No receipt image capture yet.
- No VietQR yet.
- No owner-host/member LAN synchronization yet.
- No member removal/editing or expense editing yet.
- No migration framework yet; use **Reset local trip** if the alpha schema changes between incompatible development builds.
