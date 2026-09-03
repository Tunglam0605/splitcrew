# MVP Product Scope

## Primary user

A person managing shared expenses for a meal, outing or trip from a phone.

## Core workflow

```text
Create trip
  → add members
  → add expense
  → specify payer(s)
  → choose split method
  → validate allocation
  → save locally
  → view balances
  → settle debts
```

## Required split modes

1. Equal split.
2. Exact amount per member.
3. Percentage per member.
4. Shares/weights.
5. Per-item assignment (post-MVP if UI scope becomes too large, but domain model must allow it).

## Required expense properties

- title;
- total amount;
- one or more payers;
- participating members;
- allocation method;
- category;
- date/time;
- optional note;
- optional receipt image.

## UX constraints

- Normal expense entry target: roughly 10 seconds after members are already configured.
- Common actions must work one-handed on a phone.
- Users should not need accounting terminology.
- A member does not need an online account to exist in a trip.
- Offline use is a first-class path, not an error state.

## Settlement UX

For each member show:

- amount paid;
- amount consumed/allocated;
- net balance;
- who should pay whom;
- repayment QR when a supported payment adapter exists.

## Explicitly out of scope for first local MVP

- automatic bank transaction reconciliation;
- cloud multi-device synchronization;
- OCR receipt parsing;
- cryptocurrency/payment custody;
- direct handling of bank credentials or OTPs.
