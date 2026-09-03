# Contributing to SplitCrew

Thanks for helping improve SplitCrew.

## Development rules

1. Keep domain logic independent from UI, storage and transport layers.
2. Never use floating-point arithmetic for persisted money values or final balances.
3. Add tests for every money-calculation rule and rounding edge case.
4. Prefer small, reviewable pull requests with one clear responsibility.
5. Avoid introducing cloud dependencies into the core domain.
6. Preserve offline usability.

## Branch naming

- `feat/<topic>` — new capability
- `fix/<topic>` — bug fix
- `refactor/<topic>` — behavior-preserving restructuring
- `docs/<topic>` — documentation
- `chore/<topic>` — tooling/maintenance

## Pull requests

A pull request should include:

- What changed and why.
- Architectural impact.
- Tests added or updated.
- Any migration or compatibility risk.
- Screenshots for user-interface changes.

## Commit style

Conventional-style prefixes are preferred:

- `feat:`
- `fix:`
- `refactor:`
- `test:`
- `docs:`
- `chore:`

## Money-related changes

For split or settlement logic, include test cases covering:

- zero values;
- one member;
- uneven division/remainder;
- multiple payers;
- exact conservation of total amount;
- deterministic ordering;
- invalid input rejection.

## Security

Do not commit credentials, private banking information, signing keys, API secrets or real payment authentication data. See `SECURITY.md` for vulnerability reporting.
