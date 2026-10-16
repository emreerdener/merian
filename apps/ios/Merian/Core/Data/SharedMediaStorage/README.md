# Inactive shared media storage foundation

`SharedMediaStorageRepository` is the sole writer of four scalar V60 ledger
entities. It has no AppDI composition, ordinary Capture access, file writer,
unlink operation, physical-release acknowledgement, network call or AI
admission. The product retains its existing media owners and activation hold.

## Authority and recovery

Construction requires an explicit persistent container, inventory ID and empty
authority directory separate from media and SQLite. Nonblocking exclusive locks
on the SQLite containing directory and authority directory are held for the
entire repository lifetime. This deliberately stronger L1 lock excludes a second
repository, including one proposing a different root for the same store. It is
not a lock shared with ordinary legacy producers. Distinct SQLite files in the
same containing directory are conservatively mutually exclusive. The SQLite file
is opened only for identity checks; Core Data retains its own file locks. Both
the containing directory and file identities are revalidated before
transactions. Qualification rejects any pre-existing legacy/P1 rows. Never
install this composition in a live library.

A bounded, versioned create-only directory xattr binds inventory UUID, Core Data
store UUID and the root/source binding digest. It survives loss or replacement
of the database at the same path. An existing marker with missing ledger rows
fails closed; it is never automatically cleared or overwritten, including after
an interrupted first save. This deliberately leaves initialization repair to a
future exact reconciliation procedure. No reservation can be issued meanwhile.

Each synchronous transaction opens a fresh non-autosaving context and checks
root/store identity, persisted binding, graph and generation/revision. Scalar
references cannot grant cross-account ownership; a package has one account.
Retiring allocations cannot gain references or leases. Closing admission retains
all liabilities. Only the same controller epoch may close a local qualification
lease; restart does not prove work ended. Retirement never refunds capacity in
L1, because no physical-release proof API exists yet.

Legacy observation accepts only tokens beneath explicitly registered roots. The
immutable registry (namespace, canonical path and directory identity) is hashed
into the persisted root binding and rechecked on reopen and save. Stat rejects
symlinks, hard links and changing identities. Progress pages contain at most 128
entries; tokens/cursors at most 1024 UTF8 bytes. Progress is advisory: L1
intentionally has **no completeness assertion**, stable-source-revision proof,
semantic reference import, promotion, adoption or cleanup. Those require
source-owner adapters. Changed source evidence fails closed instead of silently
replacing the prior observation.

## Accounting

Checked arithmetic preserves the adopted 96 MiB package, four/384 MiB pending,
96/64/32 MiB temporary subpools, 192 MiB temporary total and 256 MiB free
reserve. Preparation and transfer reservations each admit one package. Observed
library bytes are physical occupancy, not pending packages. Only unmaterialized
reservations are subtracted from current filesystem availability; materialized
bytes already reduced it. Per-role/media constraints remain the source owner's
responsibility. This inactive ledger does not qualify whole-product limits.

Any ledger row (including an orphan) blocks identity replacement and library
purge before existing cleanup callbacks. A failed lookup also blocks purge. Zero
rows preserve the existing path. Future integration must implement each owner's
intent/file/finalize handoff, reference reconciliation and physical release
proof before removing these barriers.

See
[SMA-1](../../../../../../docs/rfcs/shared-media-allocation-ownership-2026-10-16.md)
and the canonical
[local schema](../../../../../../docs/backend-and-data/04-database-schema.md).
