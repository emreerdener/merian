# Inactive shared media storage

`SharedMediaPhotoAcquisitionOwner` is the isolated P1 adapter. It opens a
distinct `p1Qualification` inventory with sibling database, authority and photo
roots, outside live Documents. First binding requires empty P1 rows and
namespace; reopen validates exact paired rows and markers. No automatic adoption
or mode promotion exists. Ordinary capture and AppDI remain disconnected.

The lock order is the SQLite parent's `.merian-media-fence` control file, parent
directory, authority, P1 root and P1 namespace, held for the adapter lifetime.
Standalone persistent P1 owners hold the control file shared and deny any shared
ledger, including when given another media root. The zero-byte regular fence is
opened without following links, has exactly one link, and is never removed,
replaced or upgraded. Every opener synchronizes the file and parent, including
after EEXIST, and revalidates both identities before admission. Held/named
identities and size are rechecked before mutations; a mismatch permanently
invalidates that owner. All shared-storage modes hold this fence exclusively.
Thus standalone purge can upgrade its separate media-root lock even when photos
and SQLite share a parent, without releasing allocator exclusion. This
coordinates participating owners; arbitrary external filesystem mutation is not
supported. A create-only P1-root binding blocks another database's standalone
owner after adapter closure. Partial initialization stays closed. File work uses
the already held descriptors on a dedicated actor; it does not reacquire locks
from a lower-ranked namespace.

A single fresh non-autosaving context commits the P1 reservation and shared
allocation/lease together before loading bytes. A verified namespace-owner proof
then permits one joint asset/reference and measured-allocation completion save.
Lost save acknowledgements require fresh exact readback. The provider is never
replayed; restart may restore only committed handles. `p1Reserved` and `p1Held`
retain their maximum and fixed partial/final destinations; `p1Materialized`
retains actual bytes and the exact original reference. Missing or changed files
block use, preserving the ledger and sole original.

The allocation ID is the deliberate P1 asset UUID. The paired shared lease uses
the P1 lease UUID, asset UUID, process epoch and fixed `p1AcquireV1` purpose.
Shared reference IDs and owner IDs identify the exact P1 reference and revision.
Every transaction validates both directions. One physical allocation counts once
against filesystem availability and durable limits; the P1 lease contributes the
same ceiling logically to acquisition/temporary budgets, and the encoded empty
P1 envelope contributes once per package. No schema field or numeric limit
changes.

The adapter exposes no source handoff, metadata editing, derivatives, sharing,
freeze, deletion, physical release, transport or AI admission. Generic L1
mutation APIs reject adapter mode, and any shared row still blocks ordinary
library purge. These local mechanisms do not qualify mixed production
allocators.

## Original L1 foundation

The following foundation behavior remains applicable to observation and
synthetic qualification modes. These modes have no file writer and cannot be
promoted to the adapter mode.

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
