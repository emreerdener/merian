# Analysis history admission

This prepared boundary is separate from ordinary `Database/HistoricalSync`,
which hydrates the current scan projection. Ordinary history admission remains
disconnected. The backend reader, enrollment and selection gates remain false.

- `ObservationHistoryCloudClient` owns the existing Auth work lease and the
  owner-only `get_owned_observation_analysis_page` RPC. Protocol 10 is explicit
  to this RPC; it does not advance the app's general Identify reader header.
- `ObservationHistoryPage` bounds bytes, versions, identities, ordinals,
  pagination and current media references. It reuses generated Identify/media
  decoders and primary-identification semantic validation, retaining the exact
  server snapshot bytes. Observation, analysis and optional source-analysis IDs
  must be distinct, matching the shared backend identity parser. It does not
  treat a URL as proof of media ownership or availability.
- The prepared result decoder also accepts audio result V4 with a closed
  manifest-3 WAV reference, separate from photo references. It preserves exact
  ordered description/audio bytes, matches the backend's ECMAScript whitespace
  and Unicode bounds, and rejects private locator fields. `LocalAnalysisRecord`
  stores V4 in the existing V58 opaque snapshot fields with finite completion;
  disk reopening does not select the new child or change the parent's review.
  Named history page/state/selection and review transports use reader 10. V4
  review tickets strictly decode the WAV snapshot before admitting review and
  receipt-bound confirmation/rejection Undo through the existing reader-10
  owners. V4 cannot enter photo publication, photo loading, or become an empty
  legacy Capture source. Explicit selection and receipt-bound selection Undo
  admit V4 only after validating both results' retained evidence, authority and
  display; staging does not change the visible identification. Explicit
  `captureForAudio` can retain V4 as immutable source provenance for a new WAV
  with optional caller-supplied descriptions; it never loads the original WAV.
  Candidate selection, publication and selected chat remain unavailable for V4.
  Enrollment remains reader 9 and photo resolution remains 8.
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

`ObservationHistoryEnrollmentOwner`, retained by `OfflineQueueManager`, bounds
explicit enrollment to four active observations. Requests for the same parent
coalesce only when owner, auth generation and `ModelContainer` identity match.
Foreign scopes and cancelled work cannot join. The supplied current-environment
predicate fences the service's account checks across both requests and commit,
and each caller is checked again before receiving the result. This owner does
not require inference consent, create another durable identity or run a timer.

Explicit callers can freeze `EnrollmentService.baseline` before suspending. The
local eligibility read creates no intent. The owner also captures it when no
ticket is supplied, includes the exact review/display baseline in coalescing,
and passes it to the service's pre-staging comparison. A later tap for a changed
correction cannot join an earlier request even after an A → B → A transition.
The existing final comparison still fences the commit. Presentation checks
belong to each waiter, separately from the common account/container predicate.

Cancelling one waiting caller does not cancel work shared with another caller.
The queue retains the operation; cancelled callers discard its eventual result.
Auth cancels and awaits retained enrollment before draining account leases;
coalesced drains keep new admission closed, and cancelled operation slots remain
occupied until transport exits. `ScanRepository.eradicateScan` cancels only the
matching parent/container after its database save. Denied or failed deletion
does not cancel it. Other erasure paths retain their durable deletion fences.
Cancellation never removes the durable intent: lost responses and account
transitions remain explicit retries under the original owner-bound hold. An
already committed admission may survive caller cancellation, but stale callers
cannot receive its private result. `HistoryEnrollmentOwnerTests` covers
coalescing, scope changes, capacity, cancel/await, original-intent retry and
committed deletion. Ordinary entry remains disconnected.

The imported V3 editor regression continues into an empty editor, rejects empty
submission, adds fresh photo evidence and persists only that explicit evidence.
It never resolves an original photo or borrows mutable parent media, and retains
the selected identification.

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

After exact UUID replay, new staging also checks observation-wide occupancy
under the same transaction. Any prior operation, including a terminal receipt,
blocks another UUID even when a different historical analysis is chosen.
`readTarget` returns the one original local operation and historical child,
without consent payloads; duplicate, malformed or cross-scope records throw.
Namespace and kind/subject indexes independently detect damaged work rather than
treating it as vacancy. Known exact operations remain recoverable even when
legacy duplicates exist. There is no automatic replacement policy and no server
target-discovery HTTP caller yet; local absence alone is not evidence of remote
vacancy.

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

`ObservationPublicationOperationStatus` reads only an exact owner, observation,
analysis and operation under one fresh locked context. It validates the enrolled
parent, enrollment hold and child linkage before returning an optional result.
Only a missing exact job in that valid scope is absence; corrupt or foreign
state throws and cannot authorize a new operation. The closed phases distinguish
pending, acknowledged reconciliation, local attention and terminal receipt. They
expose no consent, media, notes or raw errors and never assert visibility.

Discovery, direct claim and this reader share status-specific structural
validation. A running row needs its original positive attempt, start and
180-second expiry; missing deadlines cannot become another dispatch. Pending
rows must be pristine, while acknowledged waiting rows may legitimately have
zero attempts when a receipt was saved without dispatch. Waiting requires a
finite deadline and held/terminal work never schedules. Exhausted attempt counts
stop discovery and direct claims, and read as local attention; the original last
in-flight claim can still settle its unchanged receipt. Storage failures in
candidate scope validation reach the existing bounded retry owner rather than
being swallowed as absence. No stored schema shape changes.

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
candidates for an explicitly requested historical analysis. The caller supplies
the immutable `ObservationAnalysisReviewTicket` captured when the result was
presented. Preparation compares that full ticket (owner, target, selection, both
revisions and result/authority digests) to retained state before and after
preflight. The returned server revisions must match the displayed ticket; newer
authority requires a fresh preview rather than silently rebasing consent. The
target does not have to be selected. The caller supplies its foreground session
guard; no idle session owns an Auth work lease.

New preparation and admission require completed native analysis review work for
the entire observation, as well as settled legacy review, idle selection and
valid enrollment/owner/deletion state. Pending, received-but-unreconciled, held
and damaged review jobs fail closed. This check uses the existing transaction's
context; it does not nest a status-reader lock or change the shared legacy
settlement predicate needed by review recovery.

Final acceptance chooses 1–6 distinct candidates in user order and creates one
immutable operation value. The caller retains that value across save retries.
This initial flow explicitly shares photos without a public note; private scan
notes are never copied. Preparation does not mint an operation or choose media.
The prepared value retains the displayed ticket through acceptance. Stage
validates new intent against that same ticket in the existing transaction, after
exact saved-operation recovery, then saves before waking the durable scheduler.
An existing exact operation remains recoverable even if a newer review is now
pending; that does not authorize another operation. Historical terminal receipts
remain recoverable after review/selection changes and do not wake work. The
ordinary UI remains unconnected and all activation gates remain closed.

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
owner in a bounded version-seven envelope. Original version-one envelopes stay
readable as recovery-only unknown work. Its ordered local photo paths are
derived from the immutable media UUIDs under
`ReanalysisQueue/<child>/<media>.jpg` or `.png`. The preparation caller must
durably copy verified input files there before staging; parent-owned file
references are never adopted. Execution must recheck length and digest before
private upload. This persistence boundary does not read files or claim that
remote evidence is ready.

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
replaces only its metadata with the version-seven immutable request envelope
once a concrete recipient is available. `recoveryOnly` cannot bind a draft. The
full saved request is required to recover an existing server intent;
reconstructing it from today's provider is forbidden.

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
supplies reusable protected photo references and its exact ordered descriptions.
`ObservationHistoryPhotoReference.decodeEvidence` is the shared closed-shape
manifest validator for both photo-only reads and this complete timeline; source
capture retains the original text without trimming or borrowing parent notes. A
source with no verified photos requires explicitly added evidence; mutable
observation media must not silently become protected source evidence. Source
capture is a prepared local boundary, not an account lease, upload permission or
connected refinement entry point.

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
descriptor prevents deletion/recreation from redirecting rollback. Before file
I/O, `ObservationReanalysisPreparationIntent` persists a closed `files_pending`
envelope: version 3 for held-only work, or version 4 for explicit submission.
Both retain the exact ordered draft and a SHA-256 identity for the frozen source
snapshot bytes. The existing qualified child provides parent/owner/source
linkage even when metadata is damaged. This phase has no processor or request
and cannot pass draft binding or execution decoders. The producer hashes the
source on its preparation worker. Persistence accepts only a verified proof with
a file-restricted constructor, requiring the digest and identity to match the
frozen source. The exact source bytes are revalidated inside both database
transactions. For held-only preparation, the digest fences the pending-to-ready
transition and is discarded by ready version-2 metadata. Ready replay recovers
already-committed state; subsequent delivery retains its own source, server,
account and deletion checks.

After taking the filesystem lock, the producer rechecks the exact unattempted
pending pair, source, account, generation and deletion fences before writing.
Completion performs a fresh compare-and-save of that same pair into a held
version-2 draft or submitted version-5 admission intent; it cannot reinsert a
deleted child. Submitted work retains the source fingerprint through admission,
as specified in the
[submission-intent contract](#submission-intent-before-private-writes). Both
checks use the shared persistence transaction without holding it across file
I/O. A ready/bound retry returns existing state without downgrading it or
changing files. Cancellation after successful save cannot roll back committed
files. After the file-store await, the producer rechecks the account, generation
and source before returning private state to Capture. A lost lease withholds
that result while preserving the committed files and ready child; retry retains
the same plan. No network admission, funding or selection mutation occurs.

Parent erasure creates a minimal durable `ObservationReanalysisErasureReceipt`
before removing child rows and ingestion metadata in the same transaction. Its
canonical parent/child identities authorize only local namespace cleanup;
damaged source/owner metadata cannot strand that receipt. Any receipt, including
a completed receipt, prevents reuse of the child identity. The raw local job
kind changes no stored schema and is excluded from network scheduler wakes.

Interrupted preparations remain indexed by either their held child or erasure
receipt. `ObservationReanalysisErasureOwner` drains pending local receipts in
bounded pages, coalescing requests and advancing past failures. Post-deletion,
repository configuration and foreground activation trigger recovery without
network, onboarding or consent gates. Test execution suppresses automatic
lifecycle triggers; focused tests invoke the same owner explicitly.

`ObservationReanalysisErasurePersistence` validates the exact receipt, child
absence and current model container before file I/O and acknowledgement. The
filesystem owner keeps the child lock through both transactions and cleanup,
unlinks regular files and file symlinks without following them, and retains
pending receipts after any failure or unexpected subdirectory. Empty child
directories remain stable locks. Before acknowledgement, the queue and child
entries must still name the held directory inodes; replacement retains the
pending receipt. Discovery yields between pages, including pages containing only
malformed jobs. Existing-photo reads use nonblocking descriptors and reject
special files before reading bytes. Completed receipts remain identity
tombstones and never authorize another erasure. Generic observation-media
deletion no longer receives child paths. No network timer or provider retry is
involved. Writers and cleanup share a Documents root lock; full-account purge
takes its exclusive side before removing the namespace.

`ObservationReanalysisPreparationRecovery` now provides targeted local recovery
for the same saved child. It acquires the expected account lease, captures the
exact historical source and verifies its persisted fingerprint off the main
actor. The file store opens only existing directories, holds the shared root and
exclusive child locks, and requires the exact canonical file set. Every photo
must be a regular nonsymlink file with its original length, digest and
single-frame JPEG/PNG container. It synchronizes verified files and directories,
checks directory identities, then performs a fresh pending-to-ready database
compare-and-save under those locks. Source, account, generation, deletion and
pair ownership are rechecked; no provider work or selection change occurs. Ready
or bound replay returns existing state, including terminal state, without
repairing files or reviving work. Missing, partial, extra or changed evidence
remains held for explicit remediation. Storage errors, cancellation and busy
locks likewise cannot mint a successor or discard evidence.

`ObservationReanalysisRecoveryTests` covers complete adoption without changing
the child or file inode, selection preservation, terminal replay, missing and
extra files, interrupted temporary files, wrong digests, symlinks, FIFOs,
source/account changes, late deletion and failed database save. Targeted
recovery remains available for explicit callers; submitted files now also have
the dedicated automatic advisory recovery owner. Full-account purge is now
awaited by the existing account cleanup boundary: it drains the local receipt
owner, commits row deletion, then erases the complete namespace, including
orphans, before preferences, runtime state or recovery markers may retire.
Failures retain the account barrier. `ObservationReanalysisFileStoreTests`
covers more than 256 orphan directories, symlink and FIFO removal without
following links, preservation of unrelated files and exclusive-root lock
contention. Never wait for a file lock inside the shared database transaction.
Execution may not activate before its recovery paths are integrated and tested.
The prepared producer still has no live capture-entry caller or execution wake;
new durable children stay held and every activation gate remains closed.

### Explicit local preparation discard

`ObservationReanalysisPersistence.discardPreparation` retires one explicitly
chosen, unbound preparation under the existing shared database transaction. It
requires the frozen source, expected owner and current caller generation; exact
pending or ready row/job linkage must match. Bound requests, attempted or
terminal jobs, malformed/missing counterparts and a colliding completed result
fail closed. Row upload/inference state, an attempt timestamp, staged upload
keys, error diagnostics or server-response evidence also block discard even when
counters are zero. Malformed uppercase receipt aliases cannot create a second
cleanup authority; numeric-only UUIDs still replay their canonical keys. The
method never cancels provider execution or refunds funding.

The same save records the minimal existing erasure receipt, removes only that
child and ingestion job, and removes its optional goal hint. Siblings, source
history, selection and authority remain intact. A plan discarded before its
first write also receives a tombstone, so a delayed producer cannot later insert
it. Failed saves or late account invalidation roll back removal and receipt
together. Exact receipt replay requires no surviving child/job or result
collision and returns before parent/source lookup, preserving prior parent
deletion and cleanup completion.

The transaction performs no file I/O. After successful discard, the caller must
request the existing local erasure owner; cleanup can remain pending across
interruption or a busy writer. The receipt immediately blocks preparation, ready
promotion and identity reuse. `ObservationReanalysisDiscardTests` covers sibling
preservation, pending/ready and pre-write discard, deletion replay,
invalid-state denial, rollback and discard during a file write. Normal Capture
presentation and automatic execution remain disconnected.

### Verified delivery bytes

`ObservationReanalysisFileStore.readPhotos` shares the complete-cohort verifier
with preparation recovery. It opens existing directories, holds the root and
child locks, checks the exact file set, and verifies every ordered length,
digest and single-frame JPEG/PNG container before returning any photo. The
validated manifest limits retained input to 5 MiB. Original IDs, content types
and bytes are retained; no path repair, re-encoding or replacement identity is
allowed. Fresh account and durable claim validation callbacks run before reads
and before return while locks are held. The execution caller must additionally
recheck its lease and claim after awaiting the private result and before I/O.
This prepared read does not itself admit, upload, fund or dispatch analysis.

### Durable execution claims and local completion

`ObservationReanalysisExecutionStore` owns durable claims separately from the
network execution coordinator. An explicitly admitted bound request, a due
retry, or recovery of an interrupted running request receives a persisted,
monotonically increasing attempt fence. Every read and transition validates the
exact immutable intent, qualified row/job linkage and mirrored execution fields
in a fresh context. Post-claim timestamps must match; initial independent
creation timestamps remain valid. Uppercase identity aliases, colliding scans
and child deletion markers fail closed. A canonical result already admitted by
owner history sync is allowed only when its complete immutable content matches.
Claims compare the complete saved execution snapshot, so a stale worker cannot
settle or append after a replacement claim. Interrupted recovery requires the
execution owner to drain its old tasks first; a local claim does not itself
authorize consent, upload, provider dispatch or a provider successor.

Retryable uncertainty retains the original request and a durable wake time.
Evidence, consent, terminal-provider and reconciliation holds retain the same
request and files for explicit remediation; they cannot automatically reenter
execution. A terminal failure consumes no additional local credit or refund.
Server funding remains authoritative. Runtime delivery must validate the owner
lease and this durable claim around every suspension and locked file read.

Completion verifies the exact source, request digest and complete ordered result
manifest, appends through the shared immutable history insertion boundary, then
removes only the matching queue/job and saves its minimal file-erasure receipt
in one transaction. Selection, observation revision and review authority remain
unchanged. Save failure or account invalidation rolls back all three changes.
Exact committed replay requires the retained result bytes and cleanup receipt,
no surviving transport pair, the same owner and a living parent without a
pending deletion. Cleanup can complete independently without deleting the
retained result. Successful completion never uses preparation discard.

`ObservationReanalysisExecutionTests` exercises retry/restart fences, immutable
request conflicts, remediation holds, deletion/account checks, completion
rollback and replay after cleanup. Ordinary UI activation remains pending; every
activation gate stays disabled.

Completed-child recovery uses the separately closed
`MerianNetworkClient.recoverObservationAnalysis` endpoint before current
inference consent or private-file access. It returns exact validated snapshot
bytes or verified target absence; it never invokes selected-state sync or
preview admission. The execution owner must retain the same claim and pass the
bytes into `ObservationReanalysisExecutionStore.complete`. See the
[transport contract](../../Network/README.md#exact-completed-child-recovery).

`ObservationReanalysisExecutor` now composes one claimed attempt. It owns an
account lease and validates that lease, caller generation and saved claim around
every suspension. Recovery comes first. Only a version-seven bound envelope with
unused dispatch evidence may proceed from exact target absence to
saved-processor consent, locked file verification, exact private upload and the
original analyze request. Immediately before analyze, an atomic full-snapshot
CAS consumes that permission and records the original local attempt. The
executor replaces its current claim only after save succeeds; the after-Auth
validator and settlement use that new exact snapshot. A save that commits and
then throws never permits the call.

Consumed envelopes and legacy version-one bound requests only read the original
outcome. They never authorize, access/upload files or call analyze again, even
after restart or continued target absence. Version one retains its original
bytes; admission cannot upgrade it to fresh permission. Unbound versions 2–6
remain unchanged. A local consumed marker is conservative evidence of possible
execution, not proof of server dispatch, failure or safe retirement. Upload
checks are repeated immediately before wire dispatch without adding inference
headers to binary evidence. A complete receipt triggers a second target read; it
never manufactures a result. Atomic completion returns the permanent erasure
receipt so the execution coordinator can wake cleanup.

Uncertain transport responses schedule the same request with bounded maintenance
backoff. The tenth unsuccessful automatic attempt holds the same child with
`reanalysis_retry_limit`. Proven unavailable evidence, withdrawn consent,
provenance conflict and terminal provider failure instead require explicit
remediation. Generic `analysis_history_unavailable` does not prove evidence
expiry. Cancellation, lost owner/generation or superseded claim cannot settle
another worker's state. Local completion/save failures remain outside transport
classification. Dedicated single-flight scheduling, account teardown/drain and
strict durable wakeups are connected for explicitly admitted bound children.
Ordinary UI submission remains disconnected and all activation gates remain
false.

### Explicit reanalysis execution admission

`ObservationReanalysisAdmission` synchronizes current consent before the
existing owner-bound recipient preflight. It validates the exact ready draft and
owner lease before and after network work. `bindAndAdmit` atomically freezes
that processor and sets the existing job to `pending`: attempt zero, finite due
date, no diagnostics/server/last-attempt state, and identical row/job
timestamps. Only this pending state permits an initial execution claim. Saving
or binding a draft alone leaves it held. A saved bound request uses its original
processor consent path; admission replay reports existing
pending/running/waiting/held state and never revives an attempted hold.
Recovery-only cannot bind an unbound draft. Failure to save rolls back both
processor binding and admission.

The dedicated queue owner retains one bounded pass until its task actually
exits. Offline/constrained networking cancels and immediately invalidates its
generation; Auth waits for task completion before draining account leases.
Foreground recovery runs before the inference consent gate, allowing completed
results to recover after withdrawal. The executor still requires current consent
when a target result is absent. Candidate discovery accepts only strict
owner-qualified pending, waiting or interrupted-running snapshots; it ignores
held/draft/malformed/deleted work. The generic raw-job exclusion stays in place.
Local persistence uncertainty gets a five-second fallback floor, and active
passes suppress wake loops. Each pass processes at most eight due children and
wakes receipt-bound local erasure only after committed completion.

### Submission intent before private writes

The producer's explicit `.submit` disposition persists closed version-4
`files_pending` metadata before private file writes. It includes
`requested_action: admit`, the original draft and frozen source SHA-256.
Existing version-3 preparations and bare version-2 drafts remain held-only; they
are never implicitly upgraded. The Capture session retains this action alongside
its one plan before awaiting the producer. A retry with another action
conflicts.

Verified file completion and complete-cohort recovery convert submitted work to
closed version-5 `admission_pending`, retaining the exact draft and original
source fingerprint. A save failure retains the preceding phase. A held retry
cannot overwrite either submitted phase. These envelopes remain unbound,
`needsAttention`, attempt zero, and absent from execution scheduler candidates.
They confer no provider, upload, funding or inference permission.

`ObservationReanalysisAdmission` revalidates the retained source fingerprint on
the preparation worker before recipient preflight. Its immutable source proof is
checked around suspended work and again inside the atomic binding transaction.
Submitted work cannot enter the older binding-only path or bind without this
proof. Recovery-only, consent denial or account loss leaves the same unbound
submission intent; it never invents a processor. Pristine submitted preparation
and ready phases remain explicitly discardable through the same permanent
receipt. Once bound pending admission commits, preparation discard is denied.

The protected editor now requests explicit submission through the retained
producer/session seam. It wakes bounded admission only after durable preparation
and fresh account checks; already-bound replay remains owned by execution.
Ordinary app access remains disabled. `ObservationReanalysisSubmissionTests`
covers disk restart across file preparation, legacy compatibility, closed
envelopes, source-proof admission, account/consent loss and discard races. No
SwiftData schema shape or frozen snapshot changes are required.

### Durable advisory admission claims

`ObservationReanalysisAdmissionWork` wraps only explicitly submitted version-4
or version-5 work in a closed version-6 envelope. It retains the original
preparation and source fingerprint, an independent files-pending or
admission-pending phase, and private claim-attempt, retry deadline or hold
state. Normal queue/job execution status, attempts and deadlines stay pristine.
`ObservationReanalysisAdmissionStore` compares the entire original metadata and
owner-qualified pair before each mutation. Returned claim dates use the exact
persisted representation so JSON timestamp rounding cannot reject a valid claim.
Interrupted claims advance their own attempt so a stale worker cannot settle or
bind newer work. Interrupted ownership may be reclaimed only after the preceding
in-process task has drained.

File failure never promotes the phase. Promotion is reserved for the complete
cohort verifier's locked commit callback with the original source proof. Ready
admission has no candidate deadline while current consent is unavailable; held
work has none under any consent state. The runtime also suppresses fallback
timers for consent-blocked ready work and requires an explicit grant event to
rearm a consent hold. Generic filesystem conflict is not proof of damaged
evidence and cannot authorize an evidence-unavailable hold.

Claim-bound recipient preflight revalidates the full wrapper around suspended
work. Binding consumes the exact ready claim and source proof in the same
transaction that admits bound execution. Failed saves retain the original
wrapper. Local preparation discard rejects a running advisory claim; nonrunning
unbound work remains discardable with a permanent erasure receipt. Parent
deletion and account fences still win over every claim.

These storage and admission seams now feed the dedicated automatic recovery
runtime. The single-phase executor shares preparation ownership with Capture and
claims files-pending metadata only inside the locked verifier callback. The
scheduler must skip active children and bound failures that occur before a
claim, so it cannot invalidate a producer or repeatedly rediscover due work. The
final Capture action and all activation gates remain disabled.
`ObservationReanalysisAdmissionWorkTests` covers strict decoding, consent
filtering, stale claims, retry/hold transitions, failed-save rollback, locked
promotion, account loss, binding and discard fences.

### Inert source-reservation storage

`ObservationSourceReservationWork` retains the unchanged version-9 photo V2
envelope and adds a version-10 audio V3 envelope through the tagged
`ObservationSourceReservationPreparation`. It preserves the submitted source
proof, original input and candidate bytes, local claim generation and exact raw
observation. Its 4 MiB metadata cap includes base64 expansion of the separately
bounded preparation, input, candidate and 2 KiB reply. The tagged proof shares
CAS/settlement rules; no SwiftData field or frozen schema changes.

`ObservationSourceReservationStore.stage` consumes only an exact running,
files-verified admission-pending claim. It saves the immutable candidate before
any future I/O. Exact stage replay returns existing work without resetting its
phase or generation, including a save that commits then throws. Every mutation
checks the owner/parent/source/child, retained immutable source proof, pristine
paired execution fields, exact metadata and current container. The existing
admission store shares its pristine-pair validator; it grants no authority.

All states keep the queue/job at needs-attention with zero execution attempts
and no deadline. An initial explicit claim changes staged to running. After the
preceding retained owner drains, explicit same-request recovery may replace a
running/unknown or held/unavailable observation with a new local generation.
Stale claims cannot settle. Reserved observations and definite conflicts cannot
be rearmed here, and neither permits admission. A known validated reply can be
saved after cancellation only under the unchanged claim and account/container
scope; cancellation without a known reply may retain running work for explicit
recovery. This store has no timer, scheduler, transport or presentation caller.

Old preparation/admission/execution decoders reject source-reservation envelopes
(versions 9 and 10). Source work cannot appear in their candidate sets, use
legacy execution binding, or use local preparation discard. Parent erasure still
uses independent parent linkage and records its child cleanup receipt regardless
of metadata. The same transaction retains the owner-bound parent-deletion task;
server parent deletion cascades through source bindings and occupancy. No source
state authorizes upload, funding, a new UUID, inference, refund or release. The
explicit retained delivery service and the narrow audio handoff below are the
only new consumers; a separate exact unfunded-retirement action remains required
before release.

### Explicit reserved-audio binding

`ObservationAudioExecutionIntent.init(reserved:)` decodes the original V3 input
bytes from an acknowledged reserved source; it never reconstructs the request.
`ObservationAudioExecutionStore.bindReserved` consumes only that exact stored
snapshot and immutable audio proof in one transaction, after fresh fixed-Gemini
consent outside the persistence lock. Account, parent, child, source, container,
result namespace and exact metadata are revalidated before replacing source
metadata with an idle audio execution binding. Save uncertainty returns no
binding; a later explicit call recovers the same saved request. Existing exact
execution replay precedes fresh consent and preserves its claim/consumed marker.
Held, unavailable, conflicted and uncertain source states cannot enter this
handoff. It creates no dispatch permit and invokes no network work. Server
upload admission and funded analysis admission remain independent requirements;
no installed source-to-execution composition is included.

### Explicit source reservation delivery

`ObservationSourceReservationService` performs one attempt under the queue's
`ObservationSourceReservationOwner`. It requires the owner's exact snapshot,
admission mode and container, durably claims before calling the injected
transport, and revalidates the claim after Auth before bytes. A claim save that
throws produces no send capability, even if the write committed. A known bounded
observation settles only under the unchanged account/source/claim scope;
dispatch cancellation does not erase it. Auth invalidation does deny settlement.
Errors remain held or leave the original interrupted running claim if
cancellation prevents a save. Only a later explicit action after actual owner
exit may claim the same candidate again. There is no timer, candidate discovery,
upload, funding, inference or automatic rearm. Exact conflicts never release
occupancy. The photo/audio store and service are not connected to ordinary
presentation; installed composition and source retirement remain separate
contracts.

### Shared preparation ownership

`ObservationReanalysisPreparationOwner` reserves each immutable child before a
producer or local recovery call can read or mutate its durable preparation. Both
owners require explicit injection of the same instance; different file-store
actors still share that metadata reservation. A duplicate call fails busy while
the original task remains retained. Filesystem locks remain independently
required for byte verification, promotion and cleanup.

Cancellation immediately invalidates the child token and cancels the retained
task. The slot remains occupied until the task actually exits, including a
callback that does not immediately cooperate with cancellation. Coalesced drain
callers block new work until their captured tasks finish. Cancelled work cannot
return its private result, clear a successor's token or silently retire durable
preparation. A committed result remains durable; explicit discard still needs
its separate erasure receipt.

`OfflineQueueManager` owns the shared instance and cancels/awaits it within
`awaitRetainedSyncQuiescenceForAuthTransition`, before the existing final Auth
account-work drain. Producer and recovery retain their account leases across the
coordinator await and revalidate account/deletion state before returning. The
prepared Capture access factory requires its assembler to inject this same
queue-owned instance. Ordinary access remains disabled.

This coordination is installed for the existing producer and targeted local
recovery. The automatic advisory admission runtime also uses this owner, skips
active children, and takes its durable recovery claim only from the file
verifier's locked callback. The protected editor's Reanalyze action sends the
explicit submission opportunity only after the producer releases ownership.
`ObservationReanalysisOwnershipTests` covers the saved-preparation race,
separate file-store instances, late cancellation, duplicate work and the queue
Auth barrier.

### Advisory phase execution

`ObservationReanalysisAdmissionExecutor` runs one submitted phase under the
queue's shared preparation owner and an account lease. Complete local file
verification can run without network or inference consent. It compares the
original source under the durable claim transaction before reading bytes, then
promotes only from the verifier's locked completion callback. A failure before
that callback returns unclaimed with the original metadata unchanged. The future
scheduler must apply a bounded process-local cooldown to that outcome; no new
durable attempt or evidence-unavailable fact is inferred from an open, lock,
digest or generic filesystem error. Claimed uncertainty waits under the same
phase, then holds after ten attempts without replacing evidence.

Ready admission separately requires current consent and network eligibility.
Both are checked through the recipient preflight and one-time binding boundary.
Lost connectivity uses a durable retry; revoked consent holds without a wake
deadline. A recovery-only recipient holds for reconciliation and cannot invent a
processor or request. Account loss, deletion and a superseding claim cannot
settle over newer state. A completed binding wins over a late failed response.
No phase executes upload, inference, funding, replacement or selection changes.

`ObservationReanalysisAdmissionStore.rearmConsent` is an explicit full-wrapper
CAS for an admission-phase consent hold after a grant event. It retains the
original proof and attempt count and rejects stale snapshots and other hold
reasons. A generic scheduler wake cannot perform this transition implicitly. The
executor and rearm seam now feed automatic advisory admission. The final Capture
action remains disconnected. `ObservationReanalysisAdvisoryTests` covers local
promotion without consent, unchanged pre-lock failure, claimed file uncertainty,
exact admission, consent versus connectivity, stale claims, account/deletion
fences and explicit rearm.

### Automatic advisory admission

`ObservationReanalysisAdmissionRuntime` owns a separate timer and retained pass
because the general network scheduler is unavailable offline. Each pass admits
at most eight due children, refetches exact persisted candidates and skips the
shared preparation owner's active children. Its account lease, runtime token,
owner and model-container fence remain current across every suspension. Auth
quiescence cancels and awaits the pass and every outstanding timer before the
final lease drain. Network changes cancel ready admission, while local file
verification can finish under its existing fences.

Pre-claim failures receive two delayed process-local retries, then no timer
until an external opportunity. Foreground, real network changes or an explicit
submitted-child wake can reset that budget; timer ticks and pass completion
cannot. Lease/discovery failures have the same finite budget. A matching
explicit consent grant or submitted-child event reopens discovery without
clearing other children's failure budgets. This bookkeeping never rewrites
unclaimed preparation and never authorizes missing-evidence remediation.
Unknown-phase discovery failure cannot create a ready-admission fallback while
consent or network permission is closed.

Repository configuration, foreground activation and general queue drains request
recovery. A completed foreground consent synchronization rechecks the original
account and current evidence before sending a grant event; onboarding sends the
same owner-qualified event only after durable consent and its lifecycle gate.
Only that event discovers and rearms consent holds. Other remediation holds are
inert. Ready deadlines disappear while permission is closed, including fallback
wakes. Durable binding wakes the existing execution owner, with no selection,
funding or provider fallback changes. `ReanalysisAdmissionRuntimeTests` covers
finite unchanged-file retries, offline promotion, consent-held rearm, busy
preparation, lease failures and awaited cancellation.

### Private operation status

`ObservationReanalysisOperationStatus` discovers at most 20 child linkages for
one enrolled parent and expected owner, with an opaque child-ID cursor. Explicit
lexical sorting matches the cursor predicate; numeric-aware localized ordering
must not skip UUIDs. It fetches only linkage columns before consulting the
existing strict admission or execution reader for each child. Corrupt or foreign
rows are omitted; the cursor advances over inspected corruption. This order is a
pagination key, not a claim about chronology. A short account lease and final
parent/deletion check withhold the entire page if its private scope changes.

Only explicitly submitted preparations or admitted execution appear. The
projection returns child/source IDs and a closed phase: preparing evidence,
waiting to start, processing, waiting to retry, consent required, evidence
unavailable, reconciliation required, retry limit or terminal failure.
Processing reflects a durable local execution phase, including interrupted work
awaiting recovery. It proves neither a current executor nor provider dispatch.
Completed immutable results belong to history; erasure receipts do not establish
success. Raw metadata, evidence, paths, provider identity, attempts and
diagnostics are not returned. Reads need no inference consent and never admit,
rearm, retry, discard or alter selection. Prepared status presentation consumes
this projection through the History area; explicit remediation remains separate.
Ordinary history, status and Capture gates stay disabled.

`ReanalysisOperationStatusTests` covers preparation/ready phases, distinct inert
holds, bounded pagination through damaged rows, owner/parent filtering,
account/deletion rejection and completed-result omission without mutation.

### Explicit cloud composition

`ObservationHistoryCloudClient.live(manager:)` binds lease management, history
RPCs and private-photo resolution to the supplied Supabase manager. Its existing
`live` convenience delegates to the shared manager. Prepared App composition
passes one explicit client throughout History, status, editor evidence loading
and original-photo preparation, including a verified photo loader with that
client's resolver. Injected clients without a resolver fail closed. No request
or response protocol changed, no inference consent is required for these reads,
and no ordinary entry or enrollment scheduling is enabled by constructing the
composition.

The prepared saved-result UI captures the same ticket from its displayed record.
For enrolled observations, `StateSyncService.displayBaseline` is a settled,
read-only local ticket; it requires idle selection and review work. Enrollment
may change owner/selection/revision metadata, but `retainsIdentification` checks
that the original review and display still agree before opening the returned
source. The final route action separately fences the acknowledged revision and
immutable source; none of these reads changes selection or authorizes inference.

## Prepared analysis-bound review persistence

`ObservationAnalysisReviewIntent` retains the exact immutable review request,
its versioned local SHA-256 fingerprint, owner and terminal server receipt. The
fingerprint uses the request's sorted-key JSON encoding without Unicode
normalization; it is a local drift check, not server authorization. An applied
Reject remains associated with its original operation for restart-safe Undo.
Other outcomes, other targets and inferred rejection state cannot authorize
Undo. A new Undo also needs a current target cache at exactly the acknowledged
Reject review revision; the observation revision may have advanced for another
analysis.

`ObservationAnalysisReviewPersistence` stages this envelope before I/O under the
shared review transaction lock. New decisions require matching parent and target
cache revisions plus a mandatory caller validation of the presented baseline.
Only one unfinished review is admitted per observation, through receipt
reconciliation; later new decisions wait. Exact restaging returns the stored
operation before that new-action validation; it never rebinds an operation or
replaces a receipt after authority changes. The client prohibits operation UUID
reuse across local observations, a stricter invariant than the server's
observation-qualified receipt key.

Claims bind the full envelope, attempt, start and expiry. An unchanged late
claim can persist its receipt; a newer claim defeats stale writers. Dispatch
requires an unexpired claim with no receipt. All receipt outcomes are terminal
for the mutation, but leave local reconciliation unfinished. The receipt is
saved before any authority projection, with no automatic selection or
parent-revision change.

`ObservationAnalysisReviewReconciliation` recovers an acknowledged receipt under
one injected account lease. It reads the exact target and the server-selected
analysis, requiring matching owner, observation, global revision and selected
ID. Applied receipts supply minimum observation and target-review revisions; the
selected analysis retains its independent review authority. Negative receipts
supply no authority. Each new read needs live claimed work; a late final reply
may settle only the unchanged claim.

One fresh locked transaction revalidates the presented baseline, idle selection,
settled legacy review, sibling jobs and receipt-phase claim. It applies the
selected state first while the outgoing selection cache still proves its
original authority, then admits a distinct target cache and marks the receipt
reconciled in the same save. Any failure rolls back all three changes. Missing
selected-result display provenance is a hold, never permission to borrow another
result's display. Account, deletion and claim replacement defeat late replies.
The prepared OfflineSync delivery service now submits one exact saved request or
recovers its receipt, then obtains the receipt-phase claim for this reconciler.
The dedicated retained runtime delivers at most eight due operations per pass
and awaits cancellation before Auth drains. Ordinary UI remains unconnected; no
standalone completion API can mark a receipt complete without its paired
projection.

The separate `observationAnalysisReviewSync` raw kind adds no stored schema
field. Generic scheduling excludes it; the dedicated scheduler restores exact
owner-qualified deadlines, including immediate receipt reconciliation after
acknowledgement. Discovery propagates database failures for bounded recovery but
leaves malformed or held envelopes inert. Both discovery and direct claiming
validate the original running start/expiry and waiting mutation deadline.
Attention holds cannot rearm through restaging or claiming. Direct and bulk
deletion remove the observation-qualified namespace even if kind, subject or
envelope metadata is damaged. Cloud-confirmed cleanup additionally requires the
decoded owner and exact primary key. Account purge removes the jobs with the
rest of the store. Late responses cannot recreate deleted work.

`ObservationAnalysisReviewPersistenceTests` covers disk reopening, immutable
replay, strict receipt binding, byte-exact names, saved Reject association,
revision checks, claim replacement, account loss, save rollback and deletion.
Scheduler regression coverage keeps this prepared kind inert while preserving
known library-details work. Ordinary access and all activation gates remain
disabled.

`ObservationAnalysisReviewReconciliationTests` covers selection changes,
separate review authority, stale or mismatched pairs, immutable evidence and
display provenance, late replies, account/deletion/claim changes and atomic
rollback.

### Prepared foreground review admission

`ObservationAnalysisReviewTicket` captures the preview's exact owner,
observation, analysis, selected child, observation revision, review revision and
immutable result/authority digests. Listing only supplies a review revision
together with authority at the current acknowledged observation revision.
Capability checks use explicit immutable biological and primary-identification
fields, never display labels or biological defaults. Biological imported V3
results can be rejected; missing primary evidence cannot authorize confirmation.
Species confirmation requires a valid species-level primary name; named
confirmation requires an explicit validated user name. Community authority
prevents both actions.

The synchronous tap creates one request from this ticket and retains its
operation UUID through uncertain saves. `ObservationAnalysisReviewAdmission`
checks that exact request, then stages under idle selection, settled legacy
review and a fresh locked comparison of the complete ticket. Exact saved-request
replay precedes the fresh comparison and cannot reopen held or completed work.
No optimistic authority, selection update, network call or implicit queue wake
occurs here.

`ObservationAnalysisReviewStatus` exposes only operation/target IDs and pending,
reconciling, attention or historical completion outcomes after owner and
deletion checks. Observation-wide pending discovery also blocks new decisions
when a different target owns unfinished work. Undo lookup additionally requires
the current ticket's rejection association and a reconciled, applied same-target
Reject receipt at the exact review revision. A rejected flag, unreconciled
receipt or an operation on another target cannot authorize Undo. These local
boundaries now back the explicitly injected history-preview controls. The ticket
also carries its immutable primary scientific name for accurate action labels.
Queue pass exit signals local status refresh only for its originating account
and active database context; it is not authority or a receipt. Ordinary UI
remains unconnected and holds no idle account lease.

### Retained foreground consent preparation

`ObservationPublicationPreparationOwner` retains at most four foreground reads,
coalescing only identical immutable tickets, Auth sessions, generations and
model-container identities. It receives the consent service explicitly and
creates no durable operation or retry. The owned task checks its token,
cancellation and common account/session/container environment around service
execution, including the exact leased session. Each waiter separately checks its
own cancellation and current environment before receiving the private snapshot.
A dismissed waiter cannot cancel another caller's shared read; explicit
lifecycle cancellation matches the full scope. Cancelled slots stay occupied
until actual service completion and lease release. Overlapping drains keep
admission closed until every captured task exits.

The queue retains this owner and cancels/awaits it in retained
account-transition quiescence before Auth drains its leases. Preparation does
not hold an idle lease after returning, mint an operation UUID, stage consent or
wake delivery. The inert App composition now supplies the owner and an explicit
fixed preflight fetch through the existing History session factory. Shared reads
use the common account environment; each waiter separately validates its
presentation after completion. Explicit consent presentation still needs
integration; ordinary access remains disabled.

### Explicit publication target recovery

`ObservationPublicationRecoveryOwner` retains at most four explicit target
reads, coalescing by owner, observation, Auth session, generation and container.
The scope intentionally excludes analysis: an existing server operation may
refer to another historical result. Each waiter checks its own cancellation and
presentation after shared work completes. Exact-scope cancellation, occupied
cancelled slots and overlapping drains preserve lease release before Auth
teardown. The queue owns this lifecycle; no polling or idle lease is introduced.

`ObservationPublicationRecoveryService` validates strict local target state
before and after the owner-bound remote read. Missing/deleted enrollment,
malformed or multiple local jobs and account changes fail closed. The History
access rereads local state after its own presentation check and returns local
and remote historical status separately. A held local losing UUID remains intact
when another device's operation won admission. Remote absence or failure after
uncertainty never authorizes a successor. Recovery has no save, acknowledgement,
consent-construction or delivery-wake capability. App injection is inert and all
activation gates remain false; explicit recovery and consent presentation remain
to be connected.

## Prepared immutable Field Chat intent

`ProtectedInsightChatTicket` freezes the displayed selected result, owner and
acknowledged global/review revisions, with local result/authority proof. It
rejects a nonselected historical preview. `ProtectedInsightChatRequest` is the
closed enrolled subset of the protected HTTP contract: explicit selected ticket,
original proposed conversation/client-message UUIDs and already normalized text.
UTF-16 bounds and ECMAScript trimming match the server; decoding never rewrites
saved text or normalizes Unicode.

`ProtectedInsightChatIntent` retains the exact request and canonical local
SHA-256 with a separately validated terminal assistant receipt. The digest is an
anti-drift check, not server authorization. A terminal receipt never reopens or
changes its first observation time. Private text remains owner-bound until
observation/account erasure; it is never logged or projected as a mutable
thread.

`ProtectedInsightChatPersistence` stages immutable work without I/O. Under the
existing transaction lock it validates owner, enrollment, deletion and exact
child linkage. Exact UUID replay precedes new-action checks. New work requires
unchanged displayed proof, idle selection, settled review and no unfinished chat
for that observation. Global message UUIDs cannot rebind across parents;
malformed kind/namespace records fail closed rather than appear vacant. Direct
and bulk deletion erase the indexed namespace despite damaged metadata;
malformed keys also use the explicit kind/subject index, while a canonical other
observation namespace remains authoritative. Cloud-confirmed deletion requires a
valid owner envelope. Queue states reject remote state and altered delivery
configuration. The raw job kind changes no SwiftData schema shape and
contributes no generic scheduler wake.

Prepared delivery and Auth teardown are owned by OfflineSync; the dedicated
Insights shell chat UI now consumes the inert access bundle.
`ProtectedInsightChatPersistence.stage` performs no I/O; explicitly injected
delivery may dispatch only an already persisted exact claim. Neither staging nor
delivery enrolls an observation, selects an identification or enables the
feature. The
[protected HTTP contract](../../../../../../docs/backend-and-data/05-api-contracts.md#protected-field-chat-send-http-protocol-version-one)
owns the wire boundary and rollout remains disabled.

### Native chat claims and receipts

`ProtectedInsightChatClaims` owns closed pending, running, held and complete
states under the same transaction lock. Initial admission claims only pristine
pending work. The 180-second local claim fences every dispatch check by owner,
parent, exact child, account/container generation, original request and attempt.
Expiry denies a new send but does not deny a matching late terminal receipt.
Receipt persistence is atomic, retains original request and attempt provenance,
and never projects parent authority, selection or a mutable conversation.

Interruption or unknown outcomes hold the unchanged attempt without a deadline.
An orphaned running attempt also stays unscheduled. Only an explicit replay API
can replace a held or expired claim, and it requires the exact previous attempt
so a stale tap cannot reopen newer work. Local attempt generations change;
request IDs, text, selected ticket and canonical SHA never do. Old responses
cannot acknowledge over a replacement attempt. Restart/status reads recover the
prior claim only and do not grant dispatch permission. Cancellation settlement
can save a hold while the task is cancelled, but still requires current account
scope; lost scope leaves durable work untouched.

There is no native read-only remote recovery endpoint. A nonterminal protected
send can perform the original first execution, so its local claim must precede
HTTP. The server's permanent execution fence still prevents provider successors.
The dedicated delivery service reads an exact local receipt before acquiring a
claim. Its `requireResponse` validator requires the same running claim and
current scope, without expiry or cancellation rejection of a known answer.
Generic scheduling and all activation gates remain disabled.

### Local chat restart discovery

`ProtectedInsightChatPersistence.status` reads owner/observation-scoped saved
requests without claiming, sending or changing them. It streams fixed batches of
64 job rows under the transaction lock, validates every matching envelope and
exact child linkage, and rejects multiple unfinished operations or damaged
records even beyond the requested receipt page. Canonical other-observation
namespaces remain authoritative over a damaged subject index. Completed results
are returned in canonical client-message UUID order, at most 20 per page, with a
strictly-after UUID cursor. The reader retains at most one unfinished operation
and one extra completed result to determine continuation; work is linear in the
stored job count, without a total-history cap. Main-actor scan time for large
local histories remains part of runtime qualification; paging never skips
integrity validation to infer vacancy.

Historical receipts and held requests retain their original selected ticket
regardless of today's selection or review revision. Pending, running and held
are explicit local states, not dispatch capabilities. A partial or empty page
never proves new-send eligibility; the existing full transactional staging
checks remain authoritative. Reads require current owner/container scope,
enrollment and no deletion fence, but neither inference consent nor a remote
recovery request.

`ProtectedInsightChatAccess` lives in the Insights shell and is assembled only
in the inert complete History bundle. It validates the visible engine's
`SelectedAnalysisReviewBaseline` against context, exact cached child and a
second identical context before freezing the chat ticket. It never substitutes a
newer selected result. The chat revision ceiling fails closed even when the
broader display baseline still accepts the integer. Closing releases the
presentation scope; it cannot mutate or cancel durable delivery. Dedicated send
UI uses this access; ordinary access remains nil.

### Exact native no-admission receipts

A protected chat reply is either the existing assistant completion or a closed
`not_admitted` proof bound to the original observation, client-message UUID and
proposed conversation. Only the fixed `displayed_identification_changed` reason
is accepted. Proofs never create an assistant, thread, provider successor or
refund. The existing running-claim CAS persists the exact terminal receipt and
marks the job complete in one save; rollback keeps the request occupied. Late
known proof may settle after expiry, but held/replaced claims, owner loss and
deletion still deny settlement.

Version-one intent reads preserve their serialized identity and accept only
assistant receipts. Every new terminal write uses version two with an explicit
`receipt_kind` for either an assistant completion or no-admission proof; mixed
or missing discriminator/receipt/time shapes are rejected. Version two is
terminal-only; a null receipt cannot become executable work. The original
request and SHA remain unchanged. No SwiftData schema or frozen snapshot changes
are involved.

New staging scans all scoped terminal intents and rejects a new UUID using the
same selection tuple already proved stale. Exact same-ID terminal replay still
precedes this gate. Status checks that bar across all pages, including off-page
receipts. The final tap rechecks status before minting IDs. Only a typed
pre-save stale-ticket denial releases an unsaved candidate; ambiguous saves
retain it. A local status refresh cannot clear the stale-ticket bar. A
different, actually synchronized authority tuple is needed before a new explicit
send. The explicit refresh action now loads acknowledged authority and closes
the stale chat; a later tap opens a fresh immutable session. All gates remain
false.

### Explicit identification refresh ownership

`ProtectedInsightChatRefreshOwner` retains at most four exact
owner/ticket/session/generation/container refreshes. Joined waiter cancellation
withholds that presentation without cancelling another caller. The owner
validates the frozen local ticket before `syncSelected`, rechecks account and
cancellation around the read, and returns a genuinely changed full ticket after
exact context/selected-entry/context validation and settled-review checks.
Unchanged or concurrently modified authority fails closed. The original Session
stays immutable. QueueManager cancels and awaits actual owner task exit before
Auth lease drain, including overlapping drains. No idle lease, inference
consent, provider execution or automatic retry is introduced.

Selected-state refresh checks native review jobs before the fetch and again in
the commit transaction. Pending or malformed analysis-review work blocks that
refresh. Completed reconciled reviews permit it. This is separate from the
legacy-review fence used inside native reconciliation, so a review does not
block its own paired-state completion.

### Staged execution retirement

Bound reanalysis metadata version eight retains the original request, dispatch
provenance and one explicit retirement operation UUID. Version-one unknown and
version-seven consumed execution can enter this state only from an exact
owner/request-qualified `admitted` status and a fresh full-snapshot transaction.
An absent status never permits retirement. Ready, unbound, deleted, completed or
changed local work fails closed. No SwiftData schema shape changes.

Staging persists before retirement I/O and invalidates previous execution
claims. Normal claim, settlement and completion exclude retirement work.
Dedicated retirement delivery consumes runnable waiting/running candidates. A
save that commits and then throws leaves the same operation recoverable from
persistence; reopening must not mint a replacement UUID. Original photos,
selection and child identity remain unchanged. Prepared status actions now use
the retained delivery, dedicated claims and proof settlement described below.
All activation gates remain disabled. Status alone cannot release local
occupancy or authorize erasure, refund or provider execution.

### Exact retirement claims and terminal proof

Retirement uses a distinct full-snapshot claim. Initial and interrupted recovery
retain the staged UUID; an uncertain reply holds without a deadline, and only
explicit same-operation recovery can replace that held claim. Replaced claims
cannot acknowledge a late reply. Normal execution never adopts a retirement
claim or calls analyze from it.

A validated `retired_before_dispatch` receipt is saved in closed erasure
metadata version two, retaining the owner and bounded original proof bytes.
Recording proof and deleting the queued child/job are one transaction. Exact
replay remains possible after cleanup. Known-answer settlement may ignore task
cancellation, but never current-account, deletion or claim checks. Ordinary
version-one result/discard receipts remain distinct and cannot accept or
overwrite retirement proof. Parent deletion alone can preserve a stronger
existing proof under the same cleanup scope.

The separate `completeRetirementOutcome` path recovers an original analysis when
dispatch won the race. It validates the complete immutable result against the
saved request, appends through existing history insertion without selecting it,
and atomically records closed version-three `recovered_original_result` cleanup
metadata. That metadata retains the owner and exact retirement request; the
immutable result remains in its normal child record. Replay requires both the
exact receipt and exact saved result bytes. Version three cannot be replayed as
version-one completion or version-two retirement. Cancellation before this
normal result save leaves version-eight work for another non-dispatching read.

The retained execution pass routes retirement candidates to a dedicated executor
with only exact-result recovery and retirement-RPC dependencies. It reads the
original result first, then sends the saved retirement request. A failed request
allows one more exact outcome read; unresolved work holds without a deadline.
The normal upload/analyze executor is never used. Prepared status actions reuse
the retained preparation owner for foreground exact-status reads and persist the
final-tap retirement UUID before mutation I/O. Only running/waiting consumed or
legacy-unknown work is offered initial stopping, subject to fresh remote
admitted state and full-snapshot CAS. Distinct stopping/checking phases do not
imply retirement success. Explicit held V8 reconciliation rearm preserves the
exact UUID, request, dispatch marker and attempt; every other hold stays inert.
Discovery wakes after staging/rearming attempts, including commit-then-throw,
without restaging or rearming anything on its own. Existing actual-pass-exit
scheduler discovery covers work staged while a pass is already active. No result
recovery fabricates a successful retirement receipt or authorizes a provider
call.

### Explicit held outcome recovery

`ObservationReanalysisOutcomeAction` has only an exact-result reader, the
injected preparation owner/account, and a completion notification. It accepts
held consumed or legacy-unknown requests with reconciliation/retry-limit holds;
ready, terminal-failure and retirement records remain outside this action. The
held snapshot stays unchanged throughout I/O: no new claim, attempt, timer,
processor permission, upload or inference invocation. Absent, malformed,
cancelled or failed lookup leaves it held. A returned exact result passes the
whole saved request/evidence validation and full-snapshot CAS in
`completeHeldOutcome`; insertion, queue retirement and the existing V1 cleanup
receipt commit together without selecting the child. Exact completion replay
requires the saved result bytes and receipt. Account/deletion and replacement
snapshot fences apply before and after the await and in the transaction.

The preparation owner retains the lease until the real lookup exits and drains
before Auth teardown. A completion-save attempt notifies cleanup/library readers
even if saving commits then throws; this notification cannot dispatch, restage
or rearm. Presentation reopening performs local discovery only. The same saved
request remains available after restart, and an explicit later check performs
only another exact result read.

There is no no-admission seal for existing V2 client-generated identities. Quota
and invocation rows can be pruned; absence and even a later-created photo cohort
cannot prove that an old identity never executed. Such uncertainty stays held. A
future stronger proof would require a separately versioned durable
identity-registration contract; this feature does not retrofit one or release
occupancy based on missing rows.

### Native audio preparation intent

`ObservationAudioPreparation` is an inert, separately versioned
`audio_preparation` envelope with exact owner/parent/source/child identity,
ordered manifest 3 and frozen source SHA-256. Version 1 remains held-only:
`files_pending` advances to `files_ready`. Its explicit submission primitive
constructs version 2 with `requested_action: submit` before any private write;
locked successful verification advances it to `admission_pending`. The
version/action/phase combinations are closed. Reopening or replay cannot convert
held work into submitted work or change the original child, source or evidence.
Neither version contains a chosen recipient, funding reservation or dispatch
authority.

`ObservationAudioPreparationStore` uses the unchanged V58 qualified child and
`observationReanalysisSync` job. The child keeps `inferenceImagePaths` nil and
stores the same child-relative WAV in both captured-media representations.
Strict photo admission/execution decoders ignore this envelope. The store saves
ownership before file writes and promotes with a fresh source/account/deletion
transaction while file locks remain held; it never recreates a deleted child.

Fresh audio preparation checks local source occupancy inside that same locked
transaction, after exact child replay and before insertion. Any queued row whose
raw source text matches the UUID blocks a new audio child, including photo work
and malformed owner, parent, kind or job metadata. The one-row query matches
source UUID text case-insensitively and also holds malformed text containing
that UUID. This is a conservative corruption fence, not exact identity
discovery. It does not inspect or reinterpret a sibling's execution status.
Other sources are unaffected; existing exact audio replay remains available.

This is a local safeguard, not complete fresh-entry authority. A job whose queue
row is missing or whose source link is missing cannot be attributed by this
query. An empty status page, empty local query, fresh composition or process
restart does not establish remote absence or authorize replacement of uncertain
execution. Ordinary audio entry remains disconnected until durable recovery and
fresh-entry authority cover those cases.

`ObservationAudioPreparationProducer` requires injected account, file store and
shared preparation owner. It retains the caller's original identity, reserves
ownership before proof work, and rechecks scope after awaits. Reopening ready
work also re-verifies the complete cohort without rewriting metadata. A missing,
changed, extra or symlinked file fails safely; recovery never repairs evidence.
The file store shares private root/child locks and receipt-bound erasure across
photo and WAV storage. WAV validation preserves exact bytes. Parent deletion
finds audio by the persisted parent link even when job metadata is damaged.

`ObservationAudioPreparationTests` covers disk reopen, exact bytes/order,
photo/legacy exclusion, pending and ready file damage, failed promotion,
malformed ownership, parent erasure and post-commit account loss. Once a
verified WAV enters the audio promotion callback, a thrown error retains its
bytes: the save may already have committed. Fresh recovery validates the stored
pending or completed phase; neither outcome destroys the only evidence. Earlier
write or verification failure still rolls back newly created files. Photo
callback and rollback behavior are unchanged. Both actions retain their original
identity across disk restart and promotion failure. Commit-then-throw admission
retains submitted `files_pending` before any WAV is written; a failure before
commit creates no work, and explicit retry uses the same preparation. Existing
photo file/recovery/producer tests remain the shared-storage regression gate.
Later prepared audio submission and execution owners retain this proof. The
explicit `captureForAudio` source entry accepts a strictly decoded V4 snapshot
and its audio reference, preserving exact source bytes through validation and
reopening. Default source capture and photo preparation/selection still deny V4.
New audio evidence must use a distinct media ID and explicit input bytes; there
is no historical WAV loader or implicit media/description reuse. All activation
gates stay false.

### Inert audio request binding and claims

`ObservationAudioExecutionIntent` retains the exact saved schema-3 request bytes
and frozen source SHA in a closed `audio_execution` envelope.
`ObservationAudioExecutionStore` binds only submitted-v2 `admission_pending`
work under current account/source/deletion checks and fixed-Gemini consent.
Authorization validates before the nonrecursive persistence lock: its callback
may itself read durable state. The entire transition is synchronous on MainActor
with no suspension between consent validation and the fresh transaction. Exact
already-bound replay is read before fresh consent gates and never resets state.

Private `idle`/`running`/`held` state and an attempt generation leave the
ordinary queue/job execution fields pristine. Fresh claims require
idle/unconsumed work. Explicit resumption of held/unconsumed work requires fresh
Gemini authorization. Held/consumed work permits only recovery claims. The
original consumed attempt is immutable; consuming it commits before a
potentially dispatching call and invalidates the preceding claim. A save that
throws yields no permission. Holds have no deadlines, scheduler wakes or
automatic retries. Running work cannot be superseded through these APIs;
interrupted-owner adoption awaits a retained owner/drain contract.

This is an inert persistence kernel, with no transport, scheduler or UI caller.
`ObservationAudioExecutionStoreTests` covers immutable binding, exact replay,
consumed-save ambiguity, stale claims, explicit resumption, denied scopes,
malformed metadata and disk reopen. Private audio erasure remains parent-indexed
and independent of the envelope. Saved photo request/claim behavior is
unchanged.

### Audio result settlement boundary

`ObservationReanalysisFileStore.readAudio` returns only the saved complete WAV
cohort under root/child locks, exact length/SHA/container checks and both caller
validation callbacks. Its caller must check account/claim again after awaiting
private bytes. The audio overload of `ObservationReanalysisResult.decode`
requires V4, exact parent/child/source/request digest and the entire ordered
manifest while retaining original snapshot bytes; photo matching remains V2.

`ObservationAudioExecutionStore.complete` accepts only a consumed running claim
or its outcome-recovery generation. Under the shared persistence lock it checks
source proof, namespace, owner/deletion and the complete saved claim, then
appends the immutable child, records the existing erasure receipt and deletes
only its queue/job in one save. It never projects or selects the result. Exact
committed replay checks result bytes and cleanup authority before returning.
This dedicated settlement transaction intentionally ignores task cancellation
for an already-known result; account loss and replaced claims still deny it.
Failures roll back, while save-commits-then-throws recovers the same result.
These primitives have no retained executor, scheduler or UI caller yet.

### Audio interruption settlement

The audio execution store has a narrow cancellation-safe read and
running-to-held transition. It requires a scope constructed only by the retained
audio owner, tied to the original intent, container and live account lease.
Scope permits at most one claim advancement from its starting snapshot and
cannot replace an existing consumed marker. The fresh locked transaction
validates the original source, parent/deletion authority, child namespace,
absence of erasure/completed child, and exact queue/job metadata before
comparing the complete snapshot.

Interruption changes only running to held. It preserves the request, attempt and
consumed marker and returns no Claim or DispatchPermit. Duplicate calls accept
only the exact corresponding held snapshot; other generations fail. A cancelled
task may recover a consumption save that committed before throwing, then hold
the consumed work without obtaining dispatch permission. Auth invalidation still
denies settlement. Generic dispatch transactions retain cancellation checks.
This store boundary remains unconnected to automatic scheduling or audio UI.

### Explicit audio executor

`ObservationAudioExecutionService` runs only inside an opaque retained audio
owner scope matching its exact entry snapshot and container. It has injected
file, upload, authorization, analysis and outcome boundaries.
`ObservationAudioExecutionDependencies.live` binds those boundaries to the
explicit file store and client, including their closed audio transports. The
queue supplies an awaited cleanup callback; no App/UI caller or scheduler is
installed yet. Running work is first held under the interruption CAS. Unconsumed
held work requires fresh fixed-Gemini authorization before resume; initial work
claims once. Verified WAV reads and exact upload receipts precede fresh
authorization and consumption. Only a successfully returned consumption permit
reaches analyze.

Consumed work claims recovery and reads its exact outcome without files, upload
or inference consent. A complete dispatch receipt still requires the original V4
result. Unknown, absent or malformed outcomes hold without timers or another
provider call. A received result may complete after ordinary cancellation, but
account, source, deletion and exact claim checks still apply. Cleanup is awaited
only after atomic completion returns its erasure receipt. The exact child erase
reuses `ObservationReanalysisErasureOwner` without joining its backlog pass.
Cancellation, suspension or failed cleanup leaves the durable receipt pending;
it cannot downgrade the committed result. A throwing consumption save triggers a
scope-bound read/hold and never creates a permit.

### Explicit audio submission binding

Before retrying audio preparation,
`ObservationAudioExecutionStore.admissionState` performs a read-only,
owner/source-qualified transaction. It distinguishes exact absence, an exact
preparation phase (`files_pending` or `admission_pending`) and the original
bound execution snapshot. A missing row/job partner, unknown or malformed
envelope, completed child, erasure receipt or changed scope throws; decode
failure never means new work. The same discriminator validates pre-consent
binding recovery and the final binding transaction.

`ObservationAudioSubmissionBinding` runs under the injected shared preparation
owner. It begins and finishes its account lease inside that retained task, so
existing Auth drains await authorization work. Exact bound replay returns before
fresh consent, retaining any consumed marker without producing a dispatch
permit. Only `admission_pending` may obtain fresh fixed-Gemini authorization and
bind; file preparation is a separate prerequisite. A save that commits then
throws still throws to this caller; a later explicit retry recovers the same
request. Post-await source/account/cancellation fences withhold stale results.

This boundary does not prepare files, start the queue, select a result or
install Capture/UI access. Capture must classify the same frozen preparation
before calling its producer; a bound request must never be rewritten as
preparation.

### Exact audio resume reader

`ObservationAudioResumeStore.read` accepts the complete
owner/observation/source/ child identity. It never enumerates jobs or infers the
latest child. Exact source capture uses its own transaction; the bounded child
metadata read uses a separate shared transaction, avoiding nested locks.
Decoding and source-hash verification run off-main. The final existing strict
`admissionState` transaction validates source, row/job linkage, namespace and
current preparation/binding before return. An intervening valid phase or claim
advancement returns the current matching state; changed immutable evidence or
disappearance fails closed.

Only submitted preparation is recoverable here. Held drafts, malformed/partial
pairs, unsupported sources and wrong identities cannot become new work. The
result contains source, verified preparation and phase or exact bound snapshot;
it contains no dispatch permit. Reading neither touches files nor obtains
consent, mutates jobs, claims work or starts execution. Therefore bound outcome
recovery can precede missing/expired-file handling. Preparation file recovery
must still use the locked producer with original bytes/digests, never assume
this read proves file availability. Retained resume orchestration is described
below; user selection of an exact saved child and ordinary App installation
remain uninstalled.

### Retained explicit audio resume submission

`ObservationAudioResumeSubmission` sequences exact-child proof recovery,
optional existing-file recovery, and binding through separate entries in the
same preparation owner. Each phase acquires its account lease inside its
retained task and releases it before the slot exits. It never nests that owner's
entries. Post-await source checks use the container-scoped lock-owning
validator; the context overload is reserved for callers inside the shared
transaction.

`ObservationAudioPreparationProducer.prepare(bytes: nil)` is existing-only: it
reads the exact saved phase and never calls `begin` to recreate a vanished
child. Submitted work uses the execution store's strict admission validator.
Locked file verification alone may promote pending evidence. Missing or changed
bytes cannot be repaired, substituted or bound. Non-nil first preparation still
uses the durable begin path.

Bound resume returns the exact current snapshot before files or fresh binding
consent, including any consumed marker. It returns no dispatch capability and
starts no queue. A binding race after the initial re-read may fail this attempt;
a later explicit same-identity retry recovers the binding without rewriting it.
Throwing saves withhold success even when committed; reopening uses the same
four IDs and durable request. No presentation predicate participates in these
common account phases. The inert Capture audio access now owns
current-presentation handoff with a fresh exact snapshot before queue start.
Saved-child selection and ordinary App installation remain separate.

### Read-only saved audio status

`ObservationAudioSavedStatus` is a local advisory reader, separate from resume
and execution. It scans at most 20 canonical owner/observation-qualified
reanalysis links plus one look-ahead under the shared persistence lock. Its
opaque lexical child cursor is scoped to that owner and observation. Every
inspected link advances paging, including omitted links; ordering is not time or
priority. The lock is released before sequential exact `ResumeStore.read`
awaits, and current scope and the enrolled parent are revalidated before return.

Only strict submitted audio proofs yield summaries: files pending, admission
pending, bound idle, and running/held distinguished by consumed state. Summaries
contain identity and state only, never requests, claims, capabilities or
actions. `omittedCount` covers inspected non-audio, held-only and classified
invalid work. It is not proof of absence; neither an empty nor a partial page
authorizes a new operation. Cancellation, account loss and unclassified
storage/parser errors fail the whole page. No broad error suppression is used.

The reader acquires no account lease and performs no file, network or mutation
work. Its caller must supply current common owner/generation/container scope.
Per-child facts can advance between reads; any later explicit action must use
the exact resume boundary and its fresh validation. No status access, UI route
or automatic dispatch consumer is installed by this foundation.

### Retained saved audio status reads

`ObservationAudioStatusOwner` is retained by `OfflineQueueManager` and accepts
an explicitly injected reader and account client. It coalesces exact
owner/observation/session/generation/container/cursor/limit scopes, with at most
four active reads. Its task acquires the account lease and releases it before
removing the entry. Scope and cancellation are checked around the reader await;
no lease survives as idle presentation state.

A joined waiter's cancellation withholds only that waiter's result. Callers must
check their own presentation after return and must not put presentation
currentness in the shared account predicate. Exact common-scope cancellation and
Auth invalidation cancel retained reads. An invalidation token prevents an older
drain from reopening a newer invalidation; a separate drain count blocks
admission throughout overlapping drains. Both queue Auth teardown seams await
actual reader exit and lease release. Pages remain advisory: this owner adds no
status access/UI, polling, scheduler, file access or execution authority.

### Inert audio status access

The prepared App bundle now injects the queue's status owner into
`CaptureAudioStatusAccess`. Its synchronous opening uses the reader's
`validateParentScope` shared-lock validator without enumerating work, and
releases its short account lease before returning. Actual pages still repeat
parent and proof validation. This early opening fence adds no admission or
execution authority. The access keeps presentation checks outside the retained
owner; ordinary routes and saved-child selection UI remain absent.

Audio staging consumes only exact submitted `admission_pending` preparation,
validated by the existing audio row/source proof, with no result collision. It
never consumes an audio execution binding. The shared v10 source metadata keeps
original V3 request bytes/evidence/profile through explicit recovery and uses
the same retained service/owner; no composition caller is installed. Existing
audio resume/execution decoders reject source work rather than silently
rebinding it.

### Retained reserved-audio submission

`ObservationAudioSourceSubmissionService` coordinates reservation and fresh
consent/binding inside the existing source owner's lease. It reads the exact
stored snapshot before work, classifies only validated audio states and skips
reservation HTTP for observed-reserved recovery. Other recoverable states use
one explicit same-candidate attempt; conflict is unavailable. Only an exact
observed-reserved reply can bind, and dispatch scope plus source CAS are checked
around every await. Known reservation settlement after cancellation does not
advance. A throwing binding save returns no handoff, even if it committed.

`OfflineQueueManager.requestAudioSourceSubmission` retains only a normally
returned binding and starts the existing audio owner after source lease and slot
exit. The execution owner rechecks account, container, network and Auth
admission. Its existing result settlement awaits receipt-bound erasure. Source
exit emits a context-qualified refresh; successful audio completion emits its
existing refresh after cleanup. Neither callback rereads durable work to grant
execution. Both existing Auth drains and connectivity cancellation apply; no new
owner, timer or automatic retry is added. The App-owned `audioSourceStart`
factory assembles live dependencies but remains uninstalled in Capture.

### Exact saved audio source reader

`ObservationAudioSourceResumeStore` reads one exact V10 source reservation and
reconstructs its proof against `captureForAudio`. It verifies the saved
preparation off-main, then rechecks source authority and the exact metadata
snapshot. It never reads files, claims work, binds execution or interprets a
source status as permission to dispatch. All valid source states remain opaque
saved evidence, including reserved, held, unknown and conflict states.
`ObservationSourceReservationStore.read` rejects any attempted save.

`ObservationAudioSourceResumeReader` retains the existing preparation slot and
account lease through the actual read task. Cancellation retains ownership until
exit; a final currentness/proof/snapshot check rejects changes during lease
release. No idle lease or polling is introduced. Legacy audio resume and saved
status readers remain closed to V10. Explicit prepared Capture source
resume/status access is available; ordinary installation remains disabled. This
reader alone does not resume execution.

### Explicit audio source preparation

`ObservationAudioSourcePreparation` classifies exact saved source and execution
records before any file preparation. V10 uses the strict source reader; an
existing execution snapshot retains its attempts and consumption markers.
Malformed or partial records throw without a legacy fallback. Only an unbound
preparation can prepare the original WAV and stage its exact source request.
Each preparation/staging phase retains the shared preparation owner and account
lease; source/proof and exact metadata are rechecked before handoff. A throwing
save never rereads or starts work, even when it committed. Explicit later
recovery uses the original child.

### Route-bound saved audio status pages

`ObservationAudioStatusIndex` owns the common bounded query, parent checks and
omission policy. Its opaque cursor includes the legacy/source route in addition
to owner, observation and child. `ObservationAudioSavedStatus` retains strict
legacy decoding; `ObservationAudioSourceSavedStatus` uses only the mutation-free
V10 source store. Malformed or unsupported rows may be omitted; account,
cancellation and storage failures propagate. An empty page is not authority to
replace durable work.

`ObservationAudioStatusOwner` retains both routes under one four-slot limit and
Auth drain. Route is part of coalescing identity, and a closed page enum
prevents returning a page from the other reader. Each actual read retains its
account lease until exit, including after cancellation. Source paging needs no
separate preparation slot, makes no admission call and never grants execution
authority.

## Private video metadata

`ObservationVideoManifest` strictly decodes the prepared manifest V4 and keeps
its original JSON bytes; `ObservationVideoProvenance` retains typed source,
parameters, frames and optional audio. These values confer no admission,
persistence, upload or execution authority. Existing audio/photo readers and
requests remain separate. Shared backend/native golden vectors qualify metadata
parity. Native retained-clip, frame and WAV producers are prepared below;
complete-cohort durability and queue integration remain pending.

## Prepared retained video clip

`ObservationRetainedVideoClipProducer` is an uninstalled native preparation
boundary for a dedicated retained MP4. It serializes work per instance and keeps
AVFoundation objects inside the owned worker. It encodes H.264 Main without
frame reordering and, when present, mono 44.1 kHz AAC; it never substitutes the
legacy playback export or deletes the input. The returned temporary lease
removes its operation directory, including writer scratch files, when
unaccepted. Acceptance transfers that directory with the file. The eventual
durable preparation owner must retain that lease through derivation and persist
the complete cohort before transfer. This producer alone does not stage, upload
or execute V4, or derive its five frames and companion WAV.

## Prepared retained-source video frames

`ObservationVideoFrameDeriver` accepts a retained-clip lease and creates all
five frames from that exact file. Its private decoder records actual sample
times, applies the track transform and 2,048-pixel decode cap, then uses the
shared square crop and an exact 768/1,024 square resize followed by one
WebP/JPEG encode. Frames have distinct IDs, ordered requested/actual ticks, byte
counts and SHA-256. Source size/hash are checked before and after sampling. The
temporary result retains the source lease and owns cleanup of its separate
operation directory. Cancellation joins the worker and cancels decoding;
incomplete generations never escape.

There is deliberately no ownership-transfer or durable-admission API for this
partial frame cohort. Complete-cohort durable staging and coordinated server
byte/profile/reader validation remain required. Ordinary access and legacy video
behavior are unchanged.

An exclusive source-use token blocks clip transfer during derivation and while
the frame result is retained. Dropping the result synchronously releases that
use; an already-transferred clip cannot begin derivation. No source identity
becomes authoritative for server admission through this temporary token.

## Prepared retained-source video audio

`ObservationVideoAudioDeriver` is an uninstalled, single-slot producer of the
optional companion WAV from an exclusively borrowed retained clip. Zero audio
tracks returns nil; an existing but failed, empty or malformed track throws.
Reader output must be contiguous, signed packed mono Int16 PCM at 44.1 kHz. The
producer copies bounded PCM bytes directly into a compact WAV, avoiding a second
conversion or writer-added padding. Actual first/last sample timestamps define
the interval; inspected final WAV bytes define its sample count.

The source digest is checked before reading and again after writing.
Cancellation and the processing deadline are observed between synchronous sample
reads; the SDK forbids concurrent reader cancellation during a read. An
in-flight read may delay cleanup and slot release. Cancellation always joins the
worker. The temporary result owns its directory and retains exclusive source
use; dropping it removes only that directory. The cohort preparer below shares
one source-use session. A durable owner must persist the whole cohort before
transfer. No partial audio transfer or live queue route exists.

## Temporary video cohort ownership

`ObservationVideoCohortPreparer` composes the retained MP4, five frames and
optional WAV under one temporary root. It acquires source use once and passes
that same token to the existing frame/audio workers sequentially. The source
snapshot is fixed before phase callbacks; `ObservationRetainedVideoUse.artifact`
is the shared bounded source reader. Every output is rechecked for size and
digest after the final callback, before handoff. One result retains all producer
leases and removes the entire root on drop. Errors and joined cancellation do
the same without deleting the caller's original input.

The cohort constructs a canonical V4 manifest through the existing closed
decoder and constructs/restores the exact request bytes. All artifact and scope
identities must remain distinct. File paths and child leases remain private;
phase callbacks expose no media paths. This is temporary composition only: it
exposes no partial transfer, persisted row, queue route, account capability or
admission. The later durable owner must verify files again and reject incomplete
cohorts.

## Closed video preparation metadata

`ObservationVideoPreparation` defines local envelope version 1 with kind
`video_preparation`. It retains the exact UTF-8 V4 request body, owner identity,
source-snapshot SHA-256 and an ordered complete inventory: retained MP4, five
frames, then optional WAV. Every path is reconstructed from child/media UUIDs
and the validated content type under `ReanalysisQueue/<child>/`; supplied paths
must match exactly. Unknown fields, malformed scope, changed inventory, missing
artifacts and reordered entries fail closed. The envelope is capped at 2 MiB;
the embedded request retains its existing stricter bound.

Only `files_pending` and `files_ready` are representable. These are held local
metadata states, not proof that bytes exist or authority to submit. This value
performs no filesystem or SwiftData writes. The next persistence owner must
validate the current source/account/deletion association in its transaction,
exclude video from legacy recovery/discard readers before staging any row, and
verify the whole file cohort before promotion. No durable transfer or restart
recovery is installed by the codec alone.
