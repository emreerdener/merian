# Inactive local photo preparation

P1-L1 owns exact delivered still-photo bytes and separate AI/display assets in a
private qualification root. `PhotoOriginalPreparationOwner` is the sole writer;
its account-work lease spans each operation. `PhotoPreparationFileStore` holds a
shared root lock then an exclusive namespace lock across fresh repository
contexts and file work. No upload, funding, inference or queue dependency
exists.

The four scalar V59 entities are record, asset, reference and lease. Migration
starts them empty; legacy snapshots and admitted operations retain their bytes.
Unknown or inconsistent state blocks fresh work. Original handles contain IDs
and generation/revision assertions, never paths or file authority.

Acquisition reserves before calling the provider. The 96 MiB acquisition subpool
counts the app-owned incoming source plus the sole partial/final copy; rename
does not duplicate it. A retained lease remains charged after an interruption.
The current preparation algorithms create encoded Data without application-owned
temporary files. Qualification excludes other allocators; this is not
product-wide allocator qualification. All approved aggregate caps and the 544
MiB worst-case free-space preflight remain in effect.
[`PhotoPreparationPolicy.swift`](PhotoPreparationPolicy.swift) owns the exact 32
MiB original, 64/5/8 MiB original/AI/display cohort and 1 MiB envelope caps,
including the existing bounded supporting-text rules.

Only a checked package may enter `preparedHeld`. That state is saved locally,
not admitted for AI. Cleanup retires references before unlinking, preserves
assets with surviving references and releases liability only after confirmed
unlink and synchronization. Unknown files remain quarantined and block work.
There is no age-based cleanup or eviction of the sole original.

An inbox source retains its exact source UUID and physical-byte liability even
after destination commit. The capture adapter must confirm source deletion or
explicit return to the still-owning inbox before that liability is released.
Account drain waits for actual callback termination. Purge removes the locked
namespace before its ledger; absence of an owner cannot bypass that barrier.

The bounded version-1 draft envelope retains ordered supporting contexts and
crop/display presentation separately from immutable original identities. Reopen
restores the last committed envelope; incomplete intent or missing files marks
the draft as needing recovery and blocks freeze. A failed edit stays unsaved.

`CaptureWorkspaceDependencies.live` supplies no access. The explicit
qualification factory requires a dedicated on-disk container/private root and
synthetic account. Installed/device use and shared allocation with ordinary
capture remain unqualified. Current implementation is undergoing NCO-1 review
and tests; this document does not claim acceptance.
