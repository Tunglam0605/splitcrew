# SplitCrew Roadmap

SplitCrew is developed in vertical milestones. Each milestone must keep the main branch buildable and the money-calculation core deterministic.

## M0 — Foundation

- [x] Public repository
- [x] Apache-2.0 license
- [x] Architecture documentation
- [x] Contribution and security policies
- [x] CI foundation

## M1 — Domain Core

- [ ] Money value object using integer minor units
- [ ] Trip and member entities
- [ ] Expense aggregate
- [ ] Multiple payers per expense
- [ ] Allocation model
- [ ] Domain invariants and validation

## M2 — Split Engine

- [ ] Equal split
- [ ] Exact-amount split
- [ ] Percentage split
- [ ] Share/weight split
- [ ] Per-item split
- [ ] Deterministic rounding tests

## M3 — Settlement Engine

- [ ] Per-member balance calculation
- [ ] Settlement generation
- [ ] Debt simplification
- [ ] Settlement audit trail

## M4 — Local Mobile MVP

- [ ] Flutter application shell
- [ ] Local SQLite persistence
- [ ] Create/manage trips
- [ ] Add/manage members
- [ ] Add/edit expenses
- [ ] Balance and settlement screens
- [ ] Works fully offline

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
- [ ] UUID identifiers
- [ ] Entity versioning
- [ ] Optimistic concurrency checks
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

- [ ] Automated Android APK build
- [ ] GitHub Releases
- [ ] Upgrade/migration tests
- [ ] Accessibility review
- [ ] Privacy review
- [ ] Beta feedback cycle

## v1.0

A stable Android-first release with local-first expense management, flexible splitting, settlement, receipts, QR repayment, and production-ready owner-hosted group synchronization.
