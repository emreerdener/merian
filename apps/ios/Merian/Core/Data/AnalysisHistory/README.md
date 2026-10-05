# Analysis history admission

This prepared boundary is separate from ordinary `Database/HistoricalSync`,
which hydrates the current scan projection. Ordinary history admission remains
disconnected. The backend reader, enrollment and selection gates remain false.

- `ObservationHistoryCloudClient` owns the existing Auth work lease and the
  owner-only `get_owned_observation_analysis_page` RPC. Protocol 9 is explicit
  to this RPC; it does not advance the app's general Identify reader header.
- `ObservationHistoryPage` bounds bytes, versions, identities, ordinals,
  pagination and current media references. It reuses generated Identify/media
  decoders and primary-identification semantic validation, retaining the exact
  server snapshot bytes. Observation, analysis and optional source-analysis IDs
  must be distinct, matching the shared backend identity parser. It does not
  treat a URL as proof of media ownership or availability.
- `ObservationHistorySyncService` owns page admission and the shared immutable
  child insertion helper. Every call reads one page and returns the server
  continuation only after the local transaction succeeds. It never assigns
  enrollment, selection, review authority or a server revision.

Admission requires an existing local observation with an acknowledged owner,
initialized selection, selected analysis UUID and bounded server revision.
Migration defaults cannot enter through current login. The exact account lease
surrounds network work and is rechecked after suspension and immediately before
save. Cancellation and failures leave a page retryable.

The final transaction uses a fresh non-autosaving context inside the existing
`ConfirmedSpeciesReviewPersistence.transaction` gate. It rejects missing parents
and any pending cloud deletion, compares every duplicate's owner, observation,
completion, version and complete bytes before inserting, then attaches new
children through the one-way cascade relationship. A changed replay rejects the
whole page. Child uniqueness is not used as an upsert mechanism. Presentation
must use bounded child queries rather than the cascade array and preserve the
server ordinal. The prepared listing boundary below supplies bounded reads;
normal sync scheduling remains disconnected.

This final transaction runs synchronously on MainActor, so explicit MainActor
scan/account deletion cannot interleave it. Background non-biological deletion
uses the same process gate and a fresh context. Automatic expiry additionally
excludes enrolled history at discovery and locked revalidation; explicit
deletion still wins. No media cache, credit, share, notification or UI effect is
emitted by admission.

`ObservationHistorySyncTests` shares a synthetic fixture with the backend reader
tests and covers replay conflict/rollback, account change, deletion, preserved
current identification and expiry. The
[wire contract](../../../../../../docs/backend-and-data/05-api-contracts.md#prepared-owner-analysis-history-reader)
defines serialization and limits. The
[activation hold](../../../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold)
requires durable completion/protected evidence, enrollment, authority hydration,
normal scheduling and the remaining public/chat/deletion integrations before the
feature can be enabled.

Protocol 9 reads snapshot versions 1, 2 and 3. Photo resolution remains on its
separate protocol-8 contract. `ObservationHistoryPhotoReference` validates V2
manifests without converting private references to public captured media.
`ObservationHistoryPhotoLoader` resolves completed, locally admitted photos
through `resolve-history-photo`, with account/deletion checks, ephemeral bounded
transport and content hashes. Delivery URLs and bytes are never stored. It
returns verified Data. The separately injected History adapter downsamples this
data for one private preview; normal app access remains disabled. See the
[private resolution contract](../../../../../../docs/backend-and-data/05-api-contracts.md#prepared-protocol-8-reads-and-private-photo-resolution).
`ObservationHistoryPhotoTests` shares the mixed V1/V2 server fixture and covers
admission, replay, private references, ticket denial, content validation and
account/deletion changes.

V56 stores imported saved identifications with `completedAt = nil`.
`ObservationHistoryPage+SavedIdentification` validates the exact V3 origin,
allowlisted saved fields and unknown execution metadata. Import time remains
separate in the decoded result and exact snapshot bytes; it never becomes an
original completion date. Imported legacy candidate/pet JSON stays opaque, and
V3 evidence is unavailable with no photo resolution. Shared V3 fixture tests
cover admission, replay, account changes and malformed metadata. Prepared
selection/projection hydration and enrollment remain disconnected from ordinary
app callers. See the
[saved enrollment contract](../../../../../../docs/backend-and-data/05-api-contracts.md#prepared-saved-identification-enrollment-and-protocol-9).

The prepared `fetchState` adapter reads one selected or explicitly requested
result with its own mutable review at one observation revision.
`ObservationHistoryState` reuses immutable snapshot decoding and keeps the seven
review fields in `ObservationHistoryAuthority`. The shared `state-v1.json`
fixture proves the Deno/Swift boundary. `ObservationHistoryStateSyncService` now
refreshes the server-selected analysis and caches its exact result in one
transaction. Same-selection refresh preserves existing display/enrichment.
Changed-selection admission requires a strictly newer observation revision,
representable target authority and the target's complete display. It installs
that display and its own review with the selected ID/revision atomically. V1/V2
display comes from the target result; V3 requires that target's existing local
baseline. It never captures the old display as the new result. Media, notes,
tags, collections and capture identity remain intact. Normal sync and UI callers
remain disconnected.

`ObservationHistorySelectionProjection` first requires the previous selected
result, its own valid display and authority cache at the current acknowledged
observation revision. Stored evidence and cache identities are revalidated.
Display is canonically rederived from V1/V2 evidence or checked against V3
surviving fields and local provenance; matching an analysis ID alone is
insufficient. The prior cached review must match native authority, with an
acknowledged native review envelope present. Missing prior display/evidence or
ambiguous legacy Undo defers without writes. The outgoing cache is preserved
unchanged; this boundary cannot silently discard the only saved identification.

Admission repeats account/deletion checks, rejects stale observation and review
revisions, and rejects equal revisions with different native authority. The
existing selected projection treats nil confirmation/state as false/unreviewed;
comparison preserves that equivalence. Immutable result bytes remain exact.
Identical replay can hydrate a missing immutable result. The pre-fetch review
baseline must still match the fresh commit-context baseline. Pending/optimistic
or malformed AI review, every unfinished review outbox job (including unknown
statuses), and legacy verified intent defer the refresh. An unacknowledged
legacy correction cannot be erased. Without either acknowledged authority
envelope, any differing incoming review also defers: an old offline Undo can
leave the default local tuple with no durable pending marker. This conservative
case requires explicit reconciliation before live enrollment. Explicit
revisioned identity clears retain their revision when representable; a nonzero
revision on an unrepresentable legacy tuple defers with
`authorityStorageRequired`. Imported legacy tuples cannot manufacture a verified
species identity. The final lease/cancellation check and save cover result
insertion, review and observation revision together; failure rolls them all
back. No credit or publication effect is emitted.

V57 adds `LocalAnalysisStateRecord`, cascade-owned by each immutable result.
`ObservationHistoryStateCache` persists the exact seven-field authority object,
its review revision and the observation revision in the same admission
transaction. Revision replay must match exact canonical authority bytes; stale
observations, stale reviews and equal-revision changes fail. Nested AI/identity
revisions are checked against the same analysis's cache, never another
selection's revision. A higher review revision requires a higher observation
revision. This cache does not bypass the legacy pending-intent or
selected-projection representability guards above.

`ObservationHistoryDisplayProjection` derives a version-1 immutable display
allowlist from validated V1/V2 result bytes through the existing domain mapper.
`AnalysisDisplaySnapshot` includes identification, taxonomy, traits, confidence,
reasoning and result-owned enrichment. It excludes review, owner notes/tags,
location, media, collections and lifecycle state. It does not borrow the current
selection's species dictionary ID. Complete replacement clears absent fields and
derived lookalike caches. Once cached, display bytes cannot be overwritten. The
projection helper is applied only by fenced server-selected state admission. V3
lacks a complete provider response. `SavedIdentificationDisplayBaseline` can
instead capture the already-selected local display during same-selection
synchronization, only when settled authority and every surviving V3 evidence
field match. The pre-fetch display must still match at commit. The bounded
version-1 envelope declares `origin = saved_local_projection` and
`source_result_version = 3`; it is local cache data, not a new server snapshot
version. It preserves no private notes, media or review state. The first
baseline is immutable despite later enrichment. An unencodable local display or
oversized optional envelope is omitted without blocking result/authority
admission. Missing or mismatched evidence leaves display unavailable. Migration
neither captures a baseline nor changes the existing scan projection. A baseline
cannot reconstruct original provider output or supply display on another device.

`ObservationHistoryPreviewService` explicitly fetches one result and admits its
result, own review and available display in one transaction. Account, deletion,
cancellation and immutable replay checks still apply. Both response revision and
selected ID must equal the locally acknowledged observation state: stale state
is rejected, a newer revision returns `refreshRequired`, and conflicts roll
back. Preview never advances parent revision, changes selection or review,
settles pending intent, or captures a saved display. Its typed display origin
lets eventual presentation distinguish result evidence from saved local display.
Pending review jobs remain intact. There is no ordinary preview caller yet.

Explicit selection requests and Undo are prepared below; enrollment scheduling,
ordinary Restore/Undo access require subsequent integration. A gated owner
transport and injected presentation are prepared below.
`ObservationHistoryStateSyncTests` covers these admission fences.
`ModelsIntegrationArchitectureTests` allows only this prepared service to
advance the observation revision and apply server-acknowledged selection, while
allowing only `ObservationHistoryEnrollmentService` to acknowledge enrollment
and continuing to forbid ordinary scheduling. The
[state contract](../../../../../../docs/backend-and-data/05-api-contracts.md#prepared-owner-observation-state-read)
owns this separate default-off endpoint.

## Prepared native enrollment

`ObservationHistoryEnrollmentService` is the sole local enrollment writer. Its
protocol-9 adapter calls `enroll_owned_observation_history` under an exact
account lease, decodes the bounded four-field `ObservationHistoryEnrollment`
receipt, then fetches current selected state. A login, upload flag or receipt
alone is never ownership or selection authority. The baseline UUID must still be
the selected V3 result. A replay after another selection defers; it never
restores that baseline implicitly.

Fresh bounded local queries before dispatch and at commit require an unenrolled
parent, no existing result/state rows, no pending deletion, no same-ID queued
scan or unfinished ingestion/review job, and settled local review. A baseline
comparison protects display and review edits across both requests. Current
server authority must exactly match native authority and all surviving V3
identification fields must match a bounded saved-local display. Missing
evidence, unrepresentable authority, divergent correction or oversized display
defers without acknowledging enrollment or changing the saved identification. If
dispatch has begun, the durable hold remains. Enrollment does not overwrite
display or review to make these comparisons pass.

The immutable result, own authority cache, saved display, owner account,
selected analysis and acknowledged revision commit atomically in a fresh
non-autosaving context. Final cancellation/account checks roll everything back.
Private notes, media and collections remain observation-owned. Before dispatch,
`ObservationHistoryEnrollmentIntent` commits a bounded owner/observation/nonce
receipt in `OfflineJobRecord`, using the exact
`observation-history-enrollment:<lower UUID>` namespace, `.future` kind and
`.needsAttention` status with no deadline. This adds no schema or wire version.
A lost response or failed admission retains the same hold across restart; an
explicit retry must match its owner and validated receipt. Unknown metadata,
terminal status or a changed nonce cannot reopen or acknowledge it. Successful
admission removes the exact hold in the same save as history and selection.
Failed saves roll back both. No autonomous retry or ordinary caller exists.

Presence in this namespace protects the observation even if metadata is damaged.
`ScanRepository.eradicateScan` checks a fresh context under the shared
transaction before any non-explicit deletion side effects. Both the hold and
acknowledged history protect against a delayed replacement with a different scan
ID, including rejection-carry completion. Automatic non-biological expiry pages
past held rows and repeats protection checks at commit. Historical scan
hydration skips held or acknowledged rows before validation, recovery
registration or insertion; it also skips all pending cloud deletions. Point
enrichment uses fresh contexts under the same lock and defers while a hold
exists. Explicit local review remains user intent and can require reconciliation
rather than being discarded.

Explicit user deletion supersedes protection. For a held or acknowledged scan it
atomically replaces/creates the namespace row as `.future/.cancelled`, removes
metadata and diagnostic payloads, enqueues normal cloud deletion and erases the
scan/history. This identity-only terminal fence survives cloud-deletion receipt
cleanup, preventing late historical pages from recreating the observation. It
cannot be used for enrollment and is removed by full account purge. Unprotected
legacy scans retain their existing erasure behavior. Both normal and malformed
namespace rows are excluded from scheduler deadlines; active holds remain
visible in the existing pending-library-mutation inventory. These safeguards do
not authorize enabling the remaining history/public/chat/review/deletion gates.

`ObservationHistoryEnrollmentTests` covers shared receipt decoding, preserved
confirmation/rejection and display, retry, changed remote selection, local
edits, deletions, account rollback and pending work. The shared
`enrollment-v1.json` fixture is consumed by both Swift and Deno tests.

`ObservationHistoryEnrollmentIntentTests` and
`ObservationHistoryEnrollmentProtectionTests` cover durable retry after store
reopen, failed staging/admission saves, owner/nonce conflicts, damaged and
terminal metadata, stale-context replacement deletion, explicit-erasure
tombstones, historical resurrection, expiry paging and deferred enrichment.

## Prepared selection and Undo

`ObservationHistorySelectionService` owns explicit native request preparation
and replay. `prepare` requires an enrolled owner, settled current review,
retained current evidence/display, and a target preview cached at the current
observation revision with representable authority and complete display. It
stores the exact six-field server request with a new operation UUID before
dispatch. This leaves the visible identification and credits unchanged.
`prepareUndo` uses the latest acknowledged receipt only when its revision and
selection still match the parent; the prior result must retain its own display
and review revision. Undo creates a new conditional selection request, never an
unconditional local overwrite.

`ObservationHistorySelectionIntent` stores one pending operation or the latest
terminal outcome per observation in the existing `.future` job namespace
`observation-history-selection:<lower UUID>`. Its bounded version-1 envelope
contains owner, previous analysis/review revision, request, and an optional
exact receipt; no display, media or private notes are copied. Pending rows use
`.needsAttention`, success rows use `.complete`, and durable revision-conflict
rows use a version-2 envelope with `rejection` and `.cancelled`. Version-1
pending/success rows remain readable. No state has a deadline; cancellation
without a validated rejection is invalid. Unknown fields, malformed metadata,
wrong owner/status and changed operation identity fail closed. Pending intent
cannot be replaced by a new request or ordinary selected-state sync. Both
namespaces are excluded from scheduler wakes even with damaged status/deadline
metadata. Account purge clears all rows; explicit scan deletion removes pending
and completed selection payloads while retaining the existing identity-only
enrollment deletion fence.

`sendPending` uses an exact account lease, replays the same request, validates
all seven receipt fields against that request and the previous selection, then
reads current selected state. A receipt alone never supplies display or
authority. An equal revision must match the receipt's target and review
revision; a newer current state is admitted without reinstalling the older
selection. The shared `ObservationHistoryStateSyncService.apply` writer retains
all previous review, evidence and display checks. Current projection, own
authority/cache, parent revision and completed receipt commit in one save under
the shared transaction. Save failure, cancellation, account change, deletion or
local edits leave no partial acknowledgment. Ambiguous failures retain the same
pending operation. An older receipt cannot enable Undo after a newer selection
or authority change.

The live protocol-9 adapter calls `select_owned_observation_analysis` behind
closed server gates. The injected client initializer still defaults to
unavailable when no selection implementation is supplied. No scheduler or normal
UI caller is connected; the injected History adapter is prepared below. A strict
seven-field `revision_conflict` rejection binds every request field and proves
that exact operation can never apply. `sendPending` reads current state after
either outcome and atomically admits it with the terminal intent. A failed
read/save keeps the original pending request for exact replay. A rejected
operation cannot enable Undo; a new request needs a fresh target preview.
Missing or deleted targets and ambiguous failures are not terminal conflict
proofs; callers must not delete or rewrite pending intent to escape them. No
Field Trip credit or public publication side effect is emitted. Shared
`selection-v1.json` exercises canonical Deno request/receipt production and
native decoding. Native `ObservationHistorySelectionIntentTests` covers staging,
replay, Undo, newer-state receipt admission, rollback, deletion, account/review
fences, corruption, restart persistence and scheduler exclusion.

## Prepared bounded listing and presentation

`ObservationHistoryListingService` returns a maximum 20-entry window. The sync
receipt now retains the already-validated page revision and ordered analysis IDs
only after atomic admission. Listing compares the page and current parent
revision, then performs bounded exact-child queries in that order. It never
sorts by completion dates, enumerates `analysisRecords`, or treats the cache as
complete. A newer page may be cached as immutable evidence but requires a
selected-state refresh before it can be presented as current authority.

`hasMultiple` uses a two-row limit. `cached` validates a single result's own
stored identity, bytes, display provenance and authority cache; missing or stale
authority is not borrowed from the selected scan. Context reads retain exact
owner, selected analysis, revision and pending/latest eligible operation IDs.

`Features/Insights/History/Services/IdentificationHistoryDependencies.swift` is
the sole prepared presentation adapter. It composes state refresh, listing,
preview, durable selection/Undo and private photo decoding under a value-only
account/session baseline. Only individual Core operations retain work leases; an
idle or background sheet cannot block Auth transition draining. Normal
`InsightShellDependencies` supplies no access. The Debug UI fixture exercises
domain values without live services. Opening/paging requires the server index;
already-loaded previews may use a valid cache on transport failure. This is not
a complete offline history browser. See the
[product contract](../../../../../../docs/features-and-hardware/05-insight-sheet.md#prepared-identification-history-sheet)
for interaction, memory and lifecycle limits.

## Prepared publication persistence

`ObservationPublicationIntent` stores version-1 exact consent before I/O. Its
local SHA-256 fingerprint covers lowercase UUIDs, explicit nulls, bounded
integer revisions, ordered media, sorted-key UTF-8 JSON with unescaped slashes
and no Unicode normalization. It is an anti-drift check, not backend
authorization or a server-compatible digest. After validated admission/status,
storage removes the request (including note and media consent), retaining owner,
three identities, fingerprint, bounded status and local observation time.
Historical `admitted` does not assert current visibility or provide a post ID.

`ObservationPublicationPersistence` owns prepared transactional stage and
compare-and-save acknowledgement. Its job key includes both observation and
operation UUIDs for erasure lookup; the operation UUID remains globally
single-use across observations. Stage rejects any reuse with another owner,
observation, analysis or consent fingerprint before I/O; it never calls generic
job upsert or revives terminal work. Acknowledgement checks the exact prior
envelope, fresh enrolled observation, original analysis owner, delete/enrollment
fences and the caller's current account-work guard before save. Both `admitted`
and `needs_action` finish the job as complete; their distinct outcomes remain in
minimal receipts across restart without blocking account transitions as
unfinished work. Same-terminal replay preserves its first local observation
time. Storage never selects a result or modifies review authority.

Direct and bulk scan deletion erase the scan-qualified job namespace in the same
transaction as the observation. This does not depend on intact consent or
subject metadata. Confirmed cloud deletion additionally checks the exact owner;
ambiguous owner metadata keeps deletion retryable. Whole-account purge already
erases all offline jobs. Late acknowledgements refetch parent and job and cannot
recreate either.

The raw `observationPublicationSync` kind changes no SwiftData stored field or
schema version. `ObservationPublicationClaims` increments the existing attempt
counter without resetting it and saves a 180-second recovery deadline before
I/O. Dispatch, acknowledgement and retry verify that exact attempt, start time
and immutable envelope. Only new dispatch requires unexpired work; a late
completion may settle an unchanged claim. A successor claim defeats old
responses even when consent is identical. Generic job upsert/reset is forbidden.

The account-bound delivery service checks status first. Only an owner-visible
404 with `analysis_history_not_found` permits replay of the original saved
request. Acknowledged receipts can only poll; they never reconstruct consent.
Proven request/revision conflicts and missing acknowledged operations park local
work for attention without inventing a server terminal status. Transient errors
retain the exact operation with bounded backoff. Failed persistence requests a
process-local recovery wake; the saved claim deadline survives restart.

Unknown raw kinds and unknown `future` namespaces cannot create wake-only loops;
known `library-details:` work keeps its existing deadlines. Older app binaries
still require a capability gate before enqueue activation. No ordinary UI caller
or rollout activation is added by delivery.

`ObservationPublicationPersistenceTests` covers exact consent/fingerprint drift,
Unicode and null distinctions, strict corruption rejection, stale response and
account guards, disk reopening, terminal replay, direct/bulk deletion and scoped
cleanup. `ObservationPublicationDeliveryTests` covers lost replies, exact 404
classification, account changes, deletion during status, stale claims, save
failure, single-flight cancellation and owner-scoped wake recovery.

## Explicit publication consent

`ObservationPublicationConsentService` prepares owner-bound descriptive photo
candidates for an explicitly requested historical analysis. It checks the
result's own retained state against the observation revision before and after
preflight, preserving pending review, selection, enrollment and deletion fences.
The target does not have to be selected. The caller supplies its foreground
session guard; no idle session owns an Auth work lease.

Final acceptance chooses 1–6 distinct candidates in user order and creates one
immutable operation value. The caller retains that value across save retries.
This initial flow explicitly shares photos without a public note; private scan
notes are never copied. Preparation does not mint an operation or choose media.
Stage validates new intent in the existing transaction, after exact
saved-operation recovery, then saves before waking the durable scheduler.
Historical terminal receipts remain recoverable after review/selection changes
and do not wake work. The ordinary UI remains unconnected and all activation
gates remain closed.

## Parent deletion of queued reanalyses

`ObservationReanalysisErasure` is used by direct and non-biological deletion. It
removes exact canonical parent-linked queue children, ingestion jobs and goal
hints within the existing parent transaction, even if routing or job metadata is
damaged. It does not save, dispatch, cancel tasks or erase files itself. Callers
return cleanup only after save; failures roll back both parent and children.
Every future qualified queue writer must share the same serialized parent
transaction and deletion fence.

Its cleanup projection accepts only the dedicated Documents-relative
`ReanalysisQueue/<child-ID>/<file>` namespace. Parent/library references do not
grant deletion authority. Offline Sync owns post-commit transport cancellation
and file cleanup; surviving queue rows and changed model containers reject stale
cancellation. The [Offline Sync contract](../OfflineSync/README.md) describes
these fences and the disabled producer.

## Prepared immutable reanalysis staging

`ObservationReanalysisIntent` retains the exact validated request bytes and
owner in a bounded version-1 envelope. Its ordered local photo paths are derived
from the immutable media UUIDs under `ReanalysisQueue/<child>/<media>.jpg` or
`.png`. The preparation caller must durably copy verified input files there
before staging; parent-owned file references are never adopted. Execution must
recheck length and digest before private upload. This persistence boundary does
not read files or claim that remote evidence is ready.

`ObservationReanalysisPersistence.stage` writes the qualified V58 queue row and
its dedicated `observationReanalysisSync` job in one fresh, non-autosaving
transaction under the shared parent-deletion lock. It requires the enrolled
owner, retained source analysis and no deletion/enrollment fence. Existing row
and job must both survive and match the original request, owner and ordered
paths. Missing or damaged metadata fails closed. Replay never changes attempts,
clears a hold or revives a complete or cancelled job. New work rejects collision
with scans, results, deletion tasks and enrollment tombstones. Save failure or a
changed account rolls back both rows. No selection, authority, quota or
complimentary hold changes occur; server admission owns funding.

`ObservationReanalysisDraft` adds a separate local version-2 `draft` envelope
for offline identity and ordered evidence before recipient preflight. It
contains no processor, request body, URL or funding claim. It shares the final
request's strict evidence validator without inventing a provider. `stageDraft`
persists the same qualified child and job under the existing
owner/source/deletion transaction. `bindDraft` compares the entire draft and
replaces only its metadata with the version-1 immutable request envelope once a
concrete recipient is available. `recoveryOnly` cannot bind a draft. The full
saved request is required to recover an existing server intent; reconstructing
it from today's provider is forbidden.

Exact draft replay recovers an already-bound request without downgrading it.
Binding to another processor, changing evidence, missing either row, attempted
or terminal draft metadata, and account/deletion changes fail closed. Save
failures retain the original draft. Binding preserves files, identities,
attempts, holds, selection and review state. Bound terminal receipts remain
terminal. These APIs still require the producer to durably copy verified files
before staging; they do not perform or authorize upload.
`ObservationReanalysisDraftTests` covers one-time binding, consent-free draft
encoding, mutation denial, rollback, terminal replay and damaged/deleted work.

The prepared stage remains held without a deadline until dedicated delivery is
connected. Ordinary scheduling ignores qualified, malformed and orphan ingestion
work, including misleading retry dates. There is no UI enqueue caller yet.
`ObservationReanalysisPersistenceTests` covers disk reopen, exact and terminal
replay, damaged identity, atomic rollback, parent deletion and scheduler fences.

The new raw job kind preserves the existing string column and V58 stored shape.
It retains `scan-ingestion:<child>` as its deletion key, but ordinary funding
restoration cannot interpret its exact request as a legacy complimentary-credit
blocker. No retired snapshot or model field changes.

`ObservationReanalysisResult.decode` is the prepared completion provenance
check. It reruns the full V2 snapshot/provider validation, then requires the
exact child, parent, source and saved request digest. Canonical comparison
covers the complete ordered evidence manifest, including descriptions and every
photo reference; matching only photo IDs is insufficient. Original snapshot
bytes are retained. It performs no mutation or authority/selection update and
cannot substitute for the future execution owner's account, deletion and claim
checks.

### Frozen refinement source

`ObservationReanalysisSource` prepares a frozen owner, observation, historical
analysis and exact validated snapshot for capture entry. Its revalidation uses
that historical analysis rather than the current selection, while retaining
parent deletion, enrollment and owner fences. Replaced snapshot bytes fail even
when their decoded meaning is equivalent. Review or selection revision changes
do not retarget the source; they remain subject to the later server admission.

V1 and imported V3 results remain eligible source identifications. Only V2
supplies reusable protected photo references. A source with no verified photos
requires explicitly added evidence; mutable observation media must not silently
become protected source evidence. Source capture is a prepared local boundary,
not an account lease, upload permission or connected refinement entry point.

Staged photographs separately track added, original and edited-original
provenance. Cropping clears authority to reuse original bytes while retaining
lineage; thumbnail/display replacement does not. Submission admission snapshots
include this provenance and chronological position, so suspended admission is
invalidated by edits even when compressed bytes happen to match. The prepared
producer below preserves the final user-selected sequence. Capture entry and
ordinary UI submission remain unconnected in this checkpoint.

### Verified file production

`CaptureReanalysisPreparation` maps only the final staged timeline into an
`ObservationReanalysisPreparationPlan`. Audio/video and invalid source lineage
fail closed. The immutable plan mints one child and new photo identities once,
including for byte-identical originals; no source media ID can be reused.
Original and edited references must belong to the frozen source. V1/V3 require
newly added photos. Input is bounded to five photos and 5 MiB before decoding;
output retains the same aggregate limit. Descriptions retain their relative
position. Retry uses the same plan; it cannot mint a successor implicitly.

`ObservationReanalysisProducer` holds an account lease and rechecks
cancellation, account, draft generation and frozen source after every
preparation suspension. It obtains original bytes through the private verified
photo loader, preserving their exact JPEG/PNG bytes. Added or edited photos use
single-frame ImageIO preparation on the detached request-preparation worker:
bounded 1024-pixel raster, explicit JPEG encoding and no copied metadata.
Ordinary WebP output is never relabeled. Unsupported or oversized evidence fails
before queue admission.

`ObservationReanalysisFileStore` owns an exclusive child-directory lock through
the synchronous queue commit. Descriptor-relative paths reject symlinks;
exclusive temporary files, synchronization and atomic exclusive rename cannot
overwrite existing data. Exact retries verify length and digest. Failed
preparation/commit removes only files created by that invocation; existing files
are retained. Retained file descriptors prevent inode recycling; the directory
descriptor prevents deletion/recreation from redirecting rollback. The final
frozen snapshot comparison runs inside `stageDraft`'s shared persistence
transaction. Successful save transfers cleanup to the existing child erasure
flow, even when cancellation arrives immediately after the save. No network
admission, funding or selection mutation occurs.

A crash before queue commit can leave unmodeled canonical files. No automatic
orphan cleanup is enabled. Future maintenance must take the same filesystem lock
before a fresh database lookup and must never acquire it while holding the
shared persistence lock. Full account erasure qualification remains required.
Individual-observation erasure also needs durable preparation ownership before
photo I/O, so unmodeled files can be attributed after a process interruption.
Neither boundary may be activated before those cleanup paths are integrated and
tested. The prepared producer still has no live capture-entry caller or
execution wake; new durable children stay held and every activation gate remains
closed.
