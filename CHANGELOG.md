# Changelog

All notable changes to SplitCrew are documented here.

The project follows Semantic Versioning once public releases begin.

## [Unreleased]

### Added

- Pure Dart domain package with integer-minor-unit money invariants.
- Deterministic split engine: equal, exact, percentage, shares, and per-item aggregation.
- Settlement engine with net balances and deterministic suggested transfers.
- Flutter Android-first MVP source.
- Local alpha persistence using SharedPreferences JSON.
- Create trip, add members, add/delete expenses, multiple payers, and four split modes in the UI.
- Balance and settlement screens.
- Android debug APK build artifact through GitHub Actions.
- Linux/macOS and Windows Android bootstrap scripts.
- MVP alpha test plan.
- Initial open-source repository foundation, architecture, security and contribution documentation.

### Known limitations

- Production persistence is not yet SQLite/Drift.
- Receipt capture, VietQR, owner-hosted sync, and OCR are not yet implemented.
