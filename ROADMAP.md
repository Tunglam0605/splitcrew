# SplitCrew Roadmap

SplitCrew is developed in vertical milestones. Every milestone must preserve deterministic money arithmetic, offline local use, and a green main branch.

## M0 — Foundation
- [x] Public repository
- [x] Apache-2.0 license
- [x] Architecture documentation
- [x] Contribution and security policies
- [x] CI foundation

## M1 — Domain Core
- [x] Integer-minor-unit money value object
- [x] Trip/member/expense entities
- [x] Multiple payers and allocation model
- [x] Money-conservation invariants

## M2 — Split Engine
- [x] Equal split
- [x] Exact-amount split
- [x] Percentage split with integer basis points
- [x] Share/weight split
- [x] Per-item allocation foundation
- [x] Deterministic remainder handling

## M3 — Settlement Engine
- [x] Per-member balances
- [x] Deterministic debt simplification
- [x] User-facing paid/share/net explanation
- [x] Expense audit view
- [ ] Persistent settlement confirmation history

## M4 — Local Mobile MVP
- [x] Flutter Android-first app
- [x] Trip/member/expense CRUD
- [x] Flexible payer/split UX
- [x] SQLite normalized persistence
- [x] SharedPreferences v0.1 migration
- [x] UUID/timestamp/version metadata
- [x] Android debug APK CI artifact
- [x] Encrypted backup/export/import foundation
- [ ] Production accessibility/usability pass

## M5 — Receipt & Payment
- [x] Camera/gallery receipt attachment
- [x] Managed local receipt storage
- [x] Payment-account abstraction
- [x] VietQR adapter
- [x] Exact repayment QR generation
- [x] Save/share repayment QR as PNG
- [x] Export/share polished trip summary image

## M6 — Owner-hosted Group Mode
- [x] Owner phone as authoritative LAN host
- [x] Short-lived one-time invite token
- [x] Owner/member permissions
- [x] REST join/snapshot/operation transport
- [x] Authenticated WebSocket revision notifications
- [x] REST polling fallback and reconnect backoff
- [x] Realtime canonical snapshot refresh
- [x] QR invite rendering
- [x] Member camera QR scan
- [ ] Encrypted LAN application transport / authenticated channel hardening
- [ ] Receipt-media synchronization

## M7 — Offline Synchronization
- [x] Durable SQLite pending-operation queue
- [x] Idempotent operation UUIDs
- [x] Queued create/update/delete expense mutations
- [x] Secure member-session storage
- [x] Optimistic trip revision checks
- [x] Expense entity-version conflict guards
- [x] Explicit blocked/conflict UX
- [x] Host reconnection and automatic queue flush
- [x] Cached member replica stays non-authoritative offline
- [x] Owner recovery/export-import foundation
- [x] Queued self-profile rename/payment-profile mutations with entity-version guards
- [ ] Generalize queue to remaining mutable operation types
- [ ] Settlement acknowledgement synchronization

## M8 — Smart Receipts
- [ ] OCR pipeline
- [ ] Detect item names, quantities and totals
- [ ] Assign people per item
- [ ] Tax/service-fee allocation
- [ ] Manual verification before commit

## M9 — Public Beta & Update Delivery
- [x] Automated Android debug APK build
- [x] Automatic non-blocking version check
- [x] Manual Check for updates action
- [x] Semantic-version comparison
- [x] GitHub Releases update provider
- [x] SHA-256 APK verification
- [x] User-authorized Android package installer flow
- [ ] Signed public GitHub Release APK
- [ ] Upgrade/migration matrix across released schemas
- [ ] Accessibility review
- [ ] Privacy review
- [ ] Beta feedback cycle
- [ ] Google Play in-app update adapter when Play Store distribution is enabled

> SplitCrew never silently installs updates. Android's system security flow remains authoritative.

## v1.0 exit criteria

A stable Android-first release with local-first expense management, receipt evidence, VietQR repayment, owner-hosted group synchronization, durable offline mutations, tested encrypted owner recovery, signed distribution, and production accessibility/privacy review.
