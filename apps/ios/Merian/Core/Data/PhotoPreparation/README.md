## October 18 — native final-reference cleanup locally verified

`SharedMediaNativeRetirementFiles` consumes only the fenced native repository's
saved-retirement capability. The locked file owner verifies the original hash
and descriptor before lending scoped descriptors. The adapter checks exact
parent/namespace identities and absent partial files, unlinks only the saved
final object, syncs directories and returns an unforgeable absence proof. Native
accounting release occurs separately after fresh saved-state validation.
Interrupted cleanup retains the retirement and its physical charge. This does
not authorize reserved/held acquisition cleanup or change production
composition.

The existing bounded source-byte reader now lives alongside image header
validation; its API, byte bounds and cancellation behavior are unchanged. See
the [shared-media owner](../SharedMediaStorage/README.md) for current review and
qualification status. Activation remains disabled.

## Isolated shared-storage integration

`SharedMediaPhotoAcquisitionOwner` uses P1's original-byte validation and writer
with joint P1/shared transactions in the existing V60 schema. Its dedicated
fixture has exclusive store, authority and media fences. Standalone persistent
P1 construction now takes a shared lifetime lock on the zero-byte
`.merian-media-fence` file in the SQLite parent before media locks and rejects
shared-ledger rows; the root marker also rejects standalone file access before
namespace creation. Unbound standalone qualification remains available.

The adapter supports exact committed-original acquisition, sharing and reference
retirement with proof-backed physical release. Saved share requests recover by
exact identity and monotonic revision; reclaimed references cannot be recreated
by replay. The shared graph preserves surviving drafts and counts physical bytes
once. Explicit retirement recovery can reconcile synchronized absence under
saved directory identities; generic token unlink cannot release shared charges.
Uncertain acquisition still holds its maximum and never repeats the provider.
Source import, derivatives, metadata editing and freeze remain unavailable in
bound fixtures. Ordinary capture still has nil access. See the
[shared owner](../SharedMediaStorage/README.md).

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
capture remain unqualified. The local foundation and confinement checks do not
close those acceptance gates.

Generic `FileIOActor` operations accept only individual flat legacy files and
cannot adopt or delete this namespace or its descendants. Original/reference
retirement still belongs exclusively to the P1 owner; a generic path is never a
release capability. This protection is a separate local ownership prerequisite,
not mixed-allocator accounting or a live-composition qualification.

## Native streaming namespace inspection — locally verified

The native inspection path streams fixed-depth canonical UUID directories and
original/partial leaves. It holds ancestor descriptors, uses independent stream
offsets and checks named/opened identities around observers and recursion.
Symlinks, hardlinks, nonregular files, partial/final collisions, enumeration
errors, cancellation and observed mutations fail the traversal. Empty canonical
ancestors are preserved. The legacy inventory's 256-entry gate is unchanged; the
native path has no retained-library count cap or whole-library token set.

`visitNativeNamespace` awaits value-only structural observations under the
locked namespace, allowing database joins on their owning actor. The traversal
applies backpressure, retains its bounded ancestor/leaf descriptors across each
await and rechecks their identities before observing another leaf. Cancellation
requests do not detach an observer: the caller must await actual traversal
termination before releasing its enclosing fences. It does not establish media
hashes, receipt phases, missing-file completeness, writer closure or cleanup
authority. Callers must exclude cooperating writers, perform exact per-leaf
ownership joins and reverse row audits, and revalidate bytes before later use.
An earlier observed leaf can be modified by an uncooperative writer after its
callback; this is not a globally atomic filesystem snapshot. No callback may
commit partial audit authority. The native store constructor remains empty-only
and activation remains disabled.

Independent and IC-1 review cleared candidate02; all six focused suites passed
41 methods (84 parameterized executions), with zero failures/skips. Candidate
and shared-baseline hashes stayed unchanged. Exact evidence is retained in
`.artifacts/shared-media-native-namespace-20261017/`. This does not qualify the
complete native transaction owner or constitute a fresh full-target run.

The asynchronous observer update is separately qualified: candidate01 stopped
before tests on SwiftLint's tuple rule; corrected candidate02 passed all six
focused suites, 42 methods / 87 parameterized executions with zero failures or
skips. Both candidates had independent and IC-1 review; failed evidence is
retained. Exact records are in
`.artifacts/shared-media-native-async-inspection-20261017/`. This does not close
full-owner or live acceptance.
