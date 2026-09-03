# ADR-001: Local-first architecture

- Status: Accepted
- Date: 2026-09-03

## Context

SplitCrew is intended for restaurants, trips and travel scenarios where Internet access may be slow, expensive or unavailable. Core expense entry and calculation must not depend on a remote service.

## Decision

Each device keeps a local database. Core use cases read and write local state first. Synchronization is an optional outer capability and never a prerequisite for split/settlement calculations.

## Consequences

### Positive

- App remains useful without Internet.
- Fast local interactions.
- Cloud backend is not required for MVP.
- The same core can support standalone and synchronized modes.

### Costs

- Schema migrations require care.
- Multi-device mode needs an operation queue, conflict handling and resynchronization.
- Device loss requires an explicit backup/recovery strategy.
