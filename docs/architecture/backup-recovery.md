# Encrypted Backup and Owner Recovery

## Purpose

The owner phone is authoritative in local group mode. SplitCrew therefore needs an explicit recovery path that does not rely on unsafe implicit host election.

The backup subsystem is separate from the financial domain and live synchronization stack. TripBackupService coordinates receipt I/O and restore semantics, while TripBackupCodec owns the portable format, compression, key derivation and authenticated encryption.

## Export rules

- Only a local/owner device may create an owner recovery backup.
- Owner Host Session must be stopped during export so the canonical snapshot and receipt set cannot change underneath the backup.
- Member cached replicas are not presented as authoritative recovery sources.
- Receipt bytes are re-read from SplitCrew-managed storage and SHA-256 verified before packaging.
- Backup metadata stores bounded KDF parameters so future readers can reproduce key derivation.
- The passphrase is never persisted by SplitCrew.

## Restore rules

Restore is disabled while the phone is an active member client or while Owner Host Session is running.

Before canonical replacement, SplitCrew validates backup format/version, bounded Argon2id parameters, AES-GCM authentication, ZIP structure, size limits, receipt SHA-256/size, and StoredTrip/domain invariants.

Receipt files are staged under new managed paths first. Only after staging succeeds is the canonical SQLite root replaced inside one repository transaction. Old receipt files are cleaned after the database commit.

Pending member operations associated with the previous/restored trip are cleared after a successful restore so obsolete queued writes cannot replay against a recovered canonical state.

## Cryptography

Current format v1 uses Argon2id with default memory 19,456 KiB, iterations 2, parallelism 1 and a 32-byte derived key; a random 16-byte KDF salt; and AES-GCM with a 256-bit key and library-generated nonce.

A wrong passphrase or modified ciphertext must fail closed.

## Non-goals

This feature does not implement cloud backup, automatic host election, multi-owner consensus, receipt media sync between active members, or passphrase recovery.
