# SplitCrew Roadmap

SplitCrew is developed in vertical milestones. Each milestone must keep the money-calculation core deterministic and `main` testable.

## M0 — Foundation

- [x] Public repository
- [x] Apache-2.0 license
- [x] Architecture documentation
- [x] Contribution and security policies
- [x] CI foundation

## M1 — Domain Core

- [x] Money value object using integer minor units
- [x] Trip and member entities
- [x] Expense aggregate
- [x] Multiple payers per expense
- [x] Allocation model
- [x] Domain money-conservation invariants

## M2 — Split Engine

- [x] Equal split
- [x] Exact-amount split
- [x] Percentage split using integer basis points
- [x] Share/weight split
- [x] Per-item equal allocation and aggregation
- [x] Deterministic remainder tests

## M3 — Settlement Engine

- [x] Per-member balance calculation
- [x] Settlement generation
- [x] Deterministic debt simplification
- [x] User-facing paid/share/net explanation
- [x] Expense-level payer/allocation audit view
- [ ] Persistent settlement confirmation history

## M4 — Local Mobile MVP

- [x] Flutter application shell
- [x] Create a local trip
- [x] Add members
- [x] Add/delete expenses
- [x] One or multiple payers
- [x] Equal/exact/percentage/share split UI
- [x] Balance and settlement screens
- [x] Automated Android debug APK artifact
- [x] SQLite persistence with normalized tables
- [x] One-time v0.1 SharedPreferences import
- [x] UUID identifiers, timestamps, and versions
- [x] Rename/delete trip flow
- [x] Rename/remove member flow with reference guards
- [x] Edit expense flow
- [x] Expense detail/audit flow
- [ ] Backup/export/import UX
- [ ] Production accessibility/usability pass

## M5 — Receipt & Payment

- [ ] Receipt image attachment
- [ ] Payment-account abstraction
- [ ] VietQR adapter
- [ ] Shareable repayment QR
- [ ] Export/share trip summary image

## M6 — Owner-hosted Group Mode

- [ ] Owner device as authoritative trip host
- [ ] Invite token + QR join
- [ ] Member roles and permissions
- [ ] LAN host discovery
- [ ] REST/WebSocket transport adapter
- [ ] Realtime canonical-state broadcast

## M7 — Offline Synchronization

- [ ] Local operation queue
- [x] UUID identifiers suitable for multi-device creation
- [x] Base entity version fields
- [ ] Optimistic concurrency checks across devices
- [ ] Conflict UX
- [ ] Host reconnection/resync
- [ ] Host recovery/export-import strategy

## M8 — Smart Receipts

- [ ] OCR pipeline
- [ ] Detect item names, quantities and totals
- [ ] Assign people per item
- [ ] Tax/service-fee allocation
- [ ] Manual verification before commit

## M9 — Public Beta

- [x] Automated Android debug APK build
- [ ] Signed GitHub Release APK
- [ ] Upgrade/migration tests across released schemas
- [ ] Accessibility review
- [ ] Privacy review
- [ ] Beta feedback cycle

## v1.0

A stable Android-first release with local-first expense management, flexible splitting, settlement, receipts, QR repayment, and production-ready owner-hosted group synchronization.
