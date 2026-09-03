# ADR-002: Owner device is authoritative in local group mode

- Status: Accepted
- Date: 2026-09-03

## Context

SplitCrew should support nearby multi-device collaboration without requiring a cloud server. Pure peer-to-peer multi-master synchronization would significantly increase conflict and recovery complexity for financial records.

## Decision

When a trip enables local group mode, the owner device acts as the authoritative host. Member devices maintain local replicas and submit commands. The host validates commands, checks entity versions, commits canonical state and broadcasts accepted events.

## Consequences

### Positive

- Clear source of truth.
- Deterministic conflict handling.
- Easier permissions and membership control.
- No public server required for nearby groups.

### Costs

- Realtime collaboration depends on host reachability.
- Member devices require pending-operation queues while disconnected.
- Backup and host-recovery mechanisms are necessary.

## Non-decision

This ADR does not require the domain layer to know about networking. A future cloud service may implement the same command/event contract.
