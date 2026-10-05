# Reversible reanalysis and identification history

Date: 2 October 2026\
Status: Partial implementation; private backend foundation, legacy erasure
protections, native refusal holds, V57 authority/display storage, saved-baseline
enrollment, protocol-9 reads and atomic result/review decoding prepared locally;
all rollout gates disabled, same-selection admission, explicit preview and
provenance-labelled local saved display and server-selected projection admission
and native enrollment admission prepared; injected history/Restore/Undo UI
tested, ordinary access and remaining integrations incomplete; no deployment\
Scope: iOS, SwiftData, inference and funding, Supabase, media, identification
review, Field Trips, Explore, Field Chat, and deletion

Confirmation addendum (4 October 2026): Analysis-bound confirmation now has a
separate default-off endpoint, immutable intent/query admission before
dictionary verification, and completion guarded by both current revisions.
Completed, stale and definitively unverified outcomes replay without another
lookup. Explicit confirmation clears only the named child's rejection and never
changes selection. Community authority, imported legacy evidence without an
explicit primary, native review admission, reconciliation and ordinary
activation remain held. The
[canonical confirmation contract](../backend-and-data/05-api-contracts.md#prepared-analysis-bound-confirmation)
owns current semantics; the earlier validation records below remain historical.

Local confirmation validation: 2,441 backend tests (343 steps), 844 SQL
assertions across 86 fixtures, clean disposable migration replay, nine dedicated
confirmation concurrency scenarios, 108 Edge entrypoint type checks, database
lint, the complete Supabase tooling gate, DTO/migration checks and formatting
passed. Advisors retain 103 security and 79 performance warnings with no errors
or new confirmation findings. Independent read-only review found no remaining
substantive confirmation-boundary issue. No native source is changed by this
slice, and no hosted rollout or TestFlight evidence is claimed.

Implementation addendum (3 October 2026): The next authority slice prepares
analysis-bound Reject/Undo with immutable outcomes, dual revision checks, and
legacy review fencing. Its independent gate remains disabled; confirmation,
community authority, native review admission, and ordinary activation remain
open work. Current semantics live in the
[canonical API contract](../backend-and-data/05-api-contracts.md#prepared-analysis-bound-reject-and-undo).

Local validation for this addendum: 2,424 backend tests (343 steps), 812 SQL
assertions across 85 fixtures, clean disposable migration replay, nine explicit
concurrency cases, database lint, the complete Supabase tooling gate, Edge type
checks, DTO checks, and Markdown/TypeScript formatting passed. Security and
performance advisors retained the existing 103/79 warnings with no errors. This
slice changes no native source and does not supersede the separate native build
evidence or establish production rollout readiness.

## Purpose and decision

Represent one observation as one stable library scan with a permanent history of
immutable analysis results. Reanalysis appends a result. The owner can select
any retained result without rerunning AI, consuming another complimentary
credit, or losing subsequent analyses.

Selection is separate from identification authority. Choosing a result does not
confirm its species, undo a rejection, or restore withdrawn community authority.
Notes, collections, and original capture identity belong to the observation and
survive every selection change.

This RFC records the agreed product direction and the contracts required before
implementation. Proposed names below describe logical identities and operations;
Stage 0 freezes their executable schemas, bounds, route mapping, and database
signatures. Existing canonical documents continue to describe current behavior
until updated with the implementing changes. This plan does not authorize
deployment, data repair, TestFlight distribution, or production activation.

## Current behavior and source evidence

Ordinary reanalysis currently creates another scan, copies selected personal
metadata, and deletes the original. The source is also retired after the durable
rejection-carry receipt in the separate incorrect-identification flow. There is
no completed-reanalysis restoration operation.

| Boundary                           | Current source and implication                                                                                                                                                                                                                                                               |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ordinary replacement               | [`InferenceScanReplacement`](../../apps/ios/Merian/Core/AI/Inference/Result/InferenceScanReplacement.swift) and [live completion](../../apps/ios/Merian/Core/AI/Inference/Completion/InferenceLiveCompletionCoordinator+Live.swift) transfer metadata before calling original-scan deletion. |
| Rejected-source replacement        | [`IdentificationReviewSyncService`](../../apps/ios/Merian/Core/Data/OfflineSync/Services/IdentificationReviewSyncService.swift) retires the source after acknowledged carry. Both deletion paths must change.                                                                                |
| Local and cloud deletion           | [`ScanRepository`](../../apps/ios/Merian/Core/Data/Database/ScanRepository.swift) deletes the local row and queues cloud erasure; [Delete Scan](../../services/supabase/functions/delete-scan/README.md) fences recovery before external erasure.                                            |
| Mixed observation and result state | [`LocalScanRecord`](../../apps/ios/Merian/Models/ActiveSchema/LocalScanRecord.swift) contains capture metadata, AI evidence, and separate review state. Migration must preserve their distinctions.                                                                                          |
| Non-biological expiry              | [Native cleanup](../../apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+NonBiologicalRetention.swift) and [Auto Purge Non-Bio](../../services/supabase/functions/auto-purge-nonbio/README.md) can delete scans after 30 days.                                                      |
| Request replay                     | [`identify-multimodal`](../../services/supabase/functions/identify-multimodal/index.ts) looks up completed work before staging resolution or quota admission. A new analysis cannot reuse an observation ID as its inference idempotency identity.                                           |
| Funding                            | [Complimentary Pro scans](../backend-and-data/18-complimentary-pro-scans.md) separates provider dispatch accounting from durable-result credit consumption.                                                                                                                                  |
| Identification authority           | [Review Scan Identification](../../services/supabase/functions/review-scan-identification/README.md) separates rejection, Undo, acceptance, and community lineage from immutable AI evidence.                                                                                                |
| Publication                        | [Share Scan to Explore](../../services/supabase/functions/share-scan-to-explore/README.md) creates or reactivates an existing scan-based post. Publication and identification snapshots need explicit versioning.                                                                            |
| Chat context                       | [`insight-chat`](../../services/supabase/functions/insight-chat/index.ts) builds the prompt from scan content after message admission. Context must become immutable before dispatch.                                                                                                        |
| Account deletion                   | [Scientific observation retention](../backend-and-data/17-scientific-observation-retention.md) distinguishes individual erasure from restricted account-detached scientific retention.                                                                                                       |

Previously deleted identifications cannot be reconstructed by this feature. A
surviving scan may contain a correction and review state without retaining an
earlier analysis. Missing history must remain missing.

## Product scope and guarantees

1. One observation has one library identity, regardless of analysis count.
2. Every completed analysis enrolled in history remains recoverable while the
   account exists, until explicit observation deletion. Account deletion has the
   separate scientific-retention contract defined below.
3. Completion initializes selection exactly once for a new observation;
   subsequent completions only append history.
4. Selecting or restoring a result changes neither its immutable evidence nor
   another result's confirmation, rejection, or community state.
5. An acknowledged selection and its effective identification projection agree.
   Offline presentation may be pending; credits follow acknowledged authority.
6. Deletion prevents every child operation from resurrecting the observation.
7. Unpublished history and supplementary evidence remain owner-only.
8. Restoration performs no inference and consumes no additional complimentary
   credit. Provider accounting and credit settlement remain separate.
9. Full history does not imply loading every result or media asset into memory.
   History reads, local hydration, and media preparation remain bounded.

Out of scope: recovering erased historical data; allowing result selection to
rewrite AI evidence; automatically publishing private selection changes;
introducing duplicate public posts; changing model assignment or confidence
calibration; and treating this plan as release authorization.

## User experience

Add **Identification history** to the scan's actions menu. Each entry shows the
identification, analysis time, confidence where available, review status, and
whether it is current. Mark a result as original only when retained evidence
establishes that fact. Otherwise use neutral history ordering; do not label the
oldest surviving result as the original by assumption.

Opening an entry shows its identification, reasoning, alternatives, provenance
appropriate for the existing UI, and the evidence used. **Use this result**
requests selection without implying species confirmation. Selection retains all
other entries. A brief **Undo** action reverses the last acknowledged selection
only if its revision precondition still holds; the history screen remains
available after the toast disappears.

Reanalysis completion opens the new result with **Keep current** and **Use this
result**. Either choice preserves both results. Dismissal keeps the current
selection. A result completed after dismissal is available in history and does
not take over an unrelated presentation.

Cached-result selection works offline with an explicit pending indicator.
Uncached evidence is fetched when connectivity permits; missing local media must
not be presented as deleted cloud history. A conflict shows the acknowledged
current result and lets the owner make a fresh choice. It does not silently
rebase the stale operation.

Notes, tags, collection membership, original capture date, and observation
identity remain stable. Additional evidence belongs to the observation but its
use is recorded per analysis. Selecting an older result does not erase evidence
added for a newer result or incorporate that evidence into the older result.

## Identity and storage contract

### Identities

| Identity                         | Lifetime and use                                                                                                                                                       |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `observation_id`                 | Permanent identity of the observation, library entry, and associated content. Preserve existing `scans.id` for migrated observations and its relationships.            |
| `analysis_id`                    | Allocated durably for one explicit analysis request. Identifies at most one completed immutable result. Deliberately requesting another analysis allocates another ID. |
| Transport-attempt ID             | Identifies an individual request delivery without changing the analysis identity or funding linkage.                                                                   |
| Provider-attempt ID              | Issued by the server for an admitted provider execution. Distinct from transport retries and linked to the logical analysis and applicable quota reservation.          |
| Selection-operation ID           | Durable idempotency key for a selection or Undo request. Exact retries return its recorded outcome.                                                                    |
| `observation_state_revision`     | Monotonic server revision for selection and relevant authority changes. Never inferred from the selected analysis ID.                                                  |
| Analysis review revision         | Monotonic revision of one analysis's current confirmation, rejection, correction, or community authority.                                                              |
| Publication revision             | Identifies an explicit public snapshot update independently of private selection.                                                                                      |
| Chat turn ID and context version | Identify one idempotent admitted turn and its immutable stored context.                                                                                                |

Bind each analysis request to the authenticated owner, observation, source
analysis when applicable, canonical evidence manifest, request configuration,
and request digest. Reusing an analysis ID with different immutable request
input conflicts. Provider execution provenance records the actual admitted
configuration; it is not guessed from current settings during recovery.

An exact replay of a completed analysis returns that result before staging
resolution or quota admission. An in-progress retry resumes or reports that same
operation. It cannot become a new analysis merely because the HTTP response was
lost.

### Storage responsibilities

| Record                               | Responsibility                                                                                                                                                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Observation                          | Ownership, stable capture identity, personal metadata, selected analysis, initialization state, revision, retention enrollment, and deletion state.                                                                |
| Analysis intent and execution ledger | Immutable request binding, source analysis, durable evidence preparation, provider attempts, completion/recovery state, and funding linkage.                                                                       |
| Immutable analysis result            | Full bounded AI result: identity/taxonomy and resolution, confidence, reasoning, alternatives, biological classification, result-specific traits, primary evidence, provenance, and exact input-evidence manifest. |
| Analysis review authority            | Current revisioned review state and durable decision lineage, separate from the AI result.                                                                                                                         |
| Observation projection               | Effective identification derived from selected analysis and current valid authority. This is a read model, not another independent authority.                                                                      |
| Selection receipt and outbox         | Durable operation outcome and ordered reconciliation obligations.                                                                                                                                                  |
| Observation media assets             | Owner-bound durable assets referenced by result manifests and explicitly selected publication media.                                                                                                               |
| Public snapshot                      | Approved publication fields, chosen media, published analysis identity, and publication revision; excludes raw private history.                                                                                    |
| Chat context snapshot                | Bounded immutable prompt inputs admitted for one turn, including a fixed conversation prefix and configuration references.                                                                                         |

Use immutable child result records on the server and corresponding SwiftData
history storage. Keep parent identity and existing relationships stable. Do not
represent historical results as additional ordinary library scans.

Inventory all result-bearing fields, including server ingestion recovery copies,
before implementing storage. Existing immutable primary/provenance columns
cannot simply be overwritten as an active-result cache. Move result authority to
child storage through a forward migration and explicitly version affected read
projections and recovery paths. Any retained compatibility projection must be
derived transactionally and must not masquerade as immutable original evidence.

History uses bounded pagination and lazy media loading. Every payload has an
executable size/cardinality limit; full history does not authorize unbounded
arrays in an Identify response. Stage 0 fixes these limits using the existing
result and media contracts and names the behavior for malformed or unsupported
history. No automatic history pruning is introduced.

## Analysis completion and funding

### Durable completion

An analysis is complete only after the validated result, every required durable
evidence reference, canonical media finalization, and a replayable completion
receipt have committed under the observation's deletion fence. A provider
response, temporary staging URL, or background continuation is insufficient.

External media promotion must precede the final database completion and be
recoverable. The final transaction revalidates the observation generation,
ownership, result binding, and ready media manifest. Interrupted promotion or
finalization resumes through the existing durable recovery owners. Late promoted
assets after deletion become cleanup obligations, not live evidence.

### Selection on completion

For a newly created observation, the first durable result initializes selection
in the completion transaction only if selection has never been initialized.
Concurrent completions serialize on that condition; exactly one initializes
selection. Initialization derives authority using the same projection rules as
later selection.

After initialization, completion only appends history. It cannot replace the
current result, cancel a pending selection, or reinterpret missing local state
as permission to initialize again. Migrated observations begin initialized to
their preserved effective state. A failed or rejected completion changes no
selection and cannot delete earlier results.

### Independent settlement

Each analysis has at most one complimentary-credit consumption. Provider
executions are accounted for separately at dispatch. Complimentary holds settle
at durable completion or proven terminal failure under the existing
[funding contract](../backend-and-data/18-complimentary-pro-scans.md).

| Outcome                                                                  | Complimentary settlement                                                     | Provider accounting                     |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------- | --------------------------------------- |
| Durable biological or valid non-biological result with required evidence | Consume once, unless existing paid-before-completion rules release the hold. | Preserve admitted execution accounting. |
| Proven terminal failure                                                  | Release a still-held credit through the terminal orchestrator.               | Attempted calls remain accounted for.   |
| Retryable or ambiguous outcome                                           | Keep held until recovery proves completion or terminal failure.              | No inferred refund or blind redispatch. |
| Completed-result replay                                                  | Preserve the original settlement; do not acquire another hold.               | No new provider execution for replay.   |
| Select or restore a saved result                                         | No hold or consumption.                                                      | No inference dispatch.                  |

Preserve user-first settlement lock ordering and the existing completion and
terminal orchestrators. Integrate the new observation/analysis identities into
those boundaries rather than creating a second credit mechanism. Provider
attempt-specific reservations may exist under existing rules; they cannot
acquire a second complimentary hold for the same analysis.

## Selection and identification authority

### Authority table

The table applies after acknowledged selection. Every row also remains subject
to the existing observation eligibility, taxonomy validation, and Field Trip
rules. Selection never confers authority by itself.

| Selected result's current state                   | Visible identification                                                                    | Effective species and credit behavior                                                                 |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Unreviewed species result                         | Its AI suggestion and its own confidence.                                                 | Preserve existing unreviewed-species eligibility; add no confirmation or new entitlement.             |
| Confirmed result or verified correction           | That analysis's valid reviewed identification, with original AI evidence distinguishable. | Use its verified species under existing credit rules. A bare legacy correction is not newly verified. |
| Rejected                                          | Saved answer visibly marked incorrect.                                                    | No effective species or species credit.                                                               |
| Awaiting acceptance                               | Saved proposal visibly unresolved.                                                        | No effective species until explicit acceptance or valid community resolution.                         |
| Community-resolved                                | Current valid community identification.                                                   | Species-level resolution may qualify; broader resolution gives no species credit.                     |
| Community resolution withdrawn                    | Historical resolution marked withdrawn and current unresolved state visible.              | Do not revive withdrawn authority or species credit.                                                  |
| Broader-taxon result without valid species review | Its genus, family, or unresolved biological label.                                        | No species-level credit.                                                                              |
| Non-biological result                             | Its non-biological result.                                                                | No species credit; retained history is unaffected.                                                    |

Confirmation of A cannot authorize B. Returning to A reads A's current valid
review authority, not a historical snapshot of a decision later revoked.
Original confidence and reasoning never become confidence or prose attributed to
a correction or community answer.

Preserve the acceptance obligation when reanalyzing a rejected observation.
Creating or selecting a proposal does not resolve it. Replace today's source
retirement with durable lineage; both results remain retained. A non-biological
result does not clear an unresolved biological identification by implication.

### State transitions

| Event                                                           | Required transition                                                                                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| First completion on an uninitialized observation                | Initialize selection once, derive authority, advance observation revision, and commit receipt.                                                    |
| Subsequent completion                                           | Append immutable history only; no selection or authority mutation.                                                                                |
| Select a saved result                                           | Validate expected revision and target membership, derive current authority, atomically advance selection/projection/revision, and record receipt. |
| Confirm, correct, reject, accept, or change community authority | Advance affected analysis review revision and observation-state revision; recompute affected active and public projections.                       |
| Undo selection                                                  | Conditional selection back to the prior analysis using the acknowledged transition's expected current revision.                                   |
| Retry a committed selection operation                           | Return its original receipt without reapplying its historical projection. Reconcile current state separately if newer state exists.               |
| Stale selection or Undo                                         | Return conflict with authorized current state; do not silently rebase.                                                                            |
| Observation deletion                                            | Commit a terminal observation fence; reject every subsequent child mutation and resurrection path.                                                |

The observation revision advances for relevant authority changes, not only
selection. Authority changes on a non-selected but published analysis must still
invalidate that publication's authority. A non-selected analysis review change
also advances the observation revision so aggregate stale expectations are
detectable.

## Offline synchronization and reconciliation ordering

Selection operations include the observation ID, target analysis ID, operation
ID, expected observation-state revision, and expected relevant review revision.
Owner identity comes from authentication. The server locks the observation and
relevant authority records in the documented global lock order, verifies the
deletion fence, and updates selection, projection, revision, receipt, and
required outbox work as one transaction.

The local outbox commits intent and pending presentation durably. Its operations
remain account-bound and ordered; a successor cannot overtake an unresolved
predecessor. After a predecessor acknowledgement, a dependent local operation
uses that receipt's revision only while its causal expectation remains valid.
Conflicts reconcile authoritative state and require a fresh choice rather than
automatic rebasing. Account/session generation checks surround every suspended
read or write and prevent one account's completion from mutating another.

Local optimistic selection is explicitly pending. Statistics and species-level
credits follow acknowledged authority, not optimistic display. Switching back to
a prior analysis does not create another observation or discovery event.

Duplicate suppression is necessary but does not establish ordering. Field Trip
and species-count reconciliation must either run inside the authoritative
transaction or recompute from current acknowledged authority and apply through a
revision-guarded sink transaction. A read-time check followed by an unguarded
write is forbidden. Track the applied observation revision and ensure stale work
cannot restore removed credit.

For A at revision 10, B at revision 11, and A at revision 12, revision 12 is
distinct from revision 10 even though the selected analysis is the same. Any
delivery order must converge to revision 12. Preserve existing recompute and
withdrawal behavior for completed Field Trips; restoration cannot mint duplicate
awards. Current-state reconciliation also handles review changes without a
selection change.

## Retention, media, and deletion

### Retention enrollment

Every observation enrolled in versioned history, including a single-result
observation, is exempt from the 30-day non-biological expiry policy. Retention
is an observation property, never derived from its currently selected result.

Update both native cleanup and the backend retention selector, including their
transaction-time revalidation. Legacy unconverted observations retain the
existing policy until enrolled. Enrollment and expiry share the deletion lock:
enrollment winning makes the observation ineligible; expiry winning leaves a
terminal tombstone that enrollment cannot bypass. Do not revive queued or
completed erasure work.

### Media ownership and access

Original and supplementary assets remain observation-owned. Each result has an
immutable manifest of the exact evidence used. Shared references are retained
until no permitted live owner requires them; selecting an older result never
authorizes garbage collection. Local cache eviction may remove downloadable
copies but cannot erase authoritative history or the sole durable evidence.

Unpublished media must have an owner-authorized delivery path. Database RLS
alone is insufficient if a raw object URL remains publicly fetchable. Stage 0
must inventory current R2 delivery, publication copies, cache behavior, and
revocation before choosing protected delivery or distinct private/public asset
representations. Merely storing a public URL in a private history row does not
meet this contract.

### Individual deletion

Explicit observation deletion fences the parent and all child analyses before
external erasure. The fence is checked by result insertion, provider admission,
finalization, replay, recovery, selection, history hydration, review sync,
publication, chat admission, and media promotion. Late callbacks cannot recreate
the parent, insert a child, or make an asset live.

Deletion erases the observation's history and associated media through durable
cleanup. In-flight analyses terminalize and settle any held credit through the
existing funding orchestrator; deletion does not independently refund provider
counters. Failed external erasure remains retryable, and the generation fence
remains effective after completion.

Preserve the existing explicitly defined collision semantics between individual
deletion and account detachment in the scientific-retention contract. Do not
weaken them by treating every deletion type as the same cascade.

### Legacy-client activation gate

The feature stays disabled until all of these conditions are proved:

1. Server observation fences and retention exemptions protect enrolled rows.
2. New explicit observation-deletion requests carry a distinct durable intent
   and versioned contract; a header alone is not proof of user intent.
3. Legacy scan-deletion requests cannot erase enrolled observations or history.
4. Upgrades do not relabel old queued replacement deletions as new explicit
   observation-deletion intent. Ambiguous tasks are held for reconciliation.
5. Server boundaries refuse unsupported reanalysis, mutation, history reads, and
   deletion of enrolled observations through legacy paths. Unsupported readers
   receive the established update-required behavior. Legacy deletion receives a
   distinct machine-readable rejection, proposed as
   `legacy_observation_delete_requires_upgrade`, without creating a tombstone.
6. Enrollment rejects existing tombstones and verifies migration state.
7. An older device delivering a queued deletion after another device enrolls the
   observation is rejected without losing retained data.

Matching result and observation IDs is only a secondary safeguard. It cannot
invalidate old pending deletion tasks, and it is not an activation strategy.

This gate protects authoritative remote history. Already-installed legacy apps
can delete their local row and media before making the rejected cloud request;
the server cannot prevent that local action. Require a compatible build for
enrollment and use compatible-client hydration to recover retained cloud results
after an older device loses its local copy. Do not promise recovery of unsynced
local-only metadata or prevention of every action on an old device.

Before an upgraded client resumes deletion draining, migrate ambiguous legacy
tasks into a held reconciliation state. The explicit legacy-delete rejection
also enters that state: it is neither successful deletion nor a transient
failure for indefinite automatic retry. Preserve any surviving local record,
refetch the owned history on a compatible client, and show that the saved scan
was retained and requires review. A later user decision to delete must create a
fresh explicit observation-deletion intent. An unupgraded client may still retry
its old task; the server must reject every delivery idempotently without erasing
history.

## Explore publication and authority revocation

Keep one post per observation. Publication writes an immutable approved public
snapshot, published analysis ID, and publication revision. Public reads use that
snapshot rather than joining the private active-result projection. Keep private
input descriptions and unselected media out of the snapshot.

Changing private selection has no publication effect. **Update shared
identification** explicitly replaces the existing post's snapshot after current
eligibility and moderation checks. Preserve the post ID and discussion, record
that its identification changed, and retain publication revision lineage. An
unshared post may be reactivated through the same explicit publication boundary;
do not create another post merely because a new analysis is selected.

Automatic authority invalidation is separate from explicit publication update.
Evaluate the published analysis's current authority independently of private
selection. When that authority is withdrawn, keep the post and discussion where
otherwise eligible, display **Identification unresolved**, and remove
confirmation and species-dependent eligibility. A historical name may remain
only when labeled historical; it cannot act as current verified identity.

Privacy and moderation restrictions may still hide the post. Publication
snapshots do not override current restrictions. Public serving and indexing must
enforce current authority/invalidation state even if an asynchronous cleanup or
cache update is delayed. Explicit publication updates and automatic invalidation
both require revision checks to prevent stale jobs from restoring withdrawn
badges or eligibility.

## Field Chat context at admission

Atomically persist a bounded immutable context snapshot with idempotent turn
admission, before provider dispatch. It contains the analysis identity, review
revision, identification context, notes and community context actually supplied,
fixed conversation prefix, and prompt/context versions or immutable
configuration references required to reconstruct that turn's input.

Capture context from a consistent authorized state, or compare its expected
revision within admission. On exact turn replay, return the admitted context; do
not fetch today's scan and rebuild yesterday's prompt. Reusing the turn ID with
different input conflicts. Stored references are sufficient only when their
target content is immutable and retained for the turn's permitted lifetime.

Dispatch and interrupted-attempt recovery use that admitted snapshot even when
selection, notes, or community authority subsequently change. New turns may use
the new state. Earlier messages are not rewritten. Current authorization,
deletion, and safety checks can refuse further execution but cannot silently
substitute another context under the same turn identity.

Legacy interrupted turns lacking recoverable immutable context cannot claim
exact retry semantics. Preserve their visible state, return an explicit
non-replayable outcome, and require a deliberate new turn rather than silently
dispatching with changed context. Snapshots remain private and follow chat and
account deletion rules; they are never copied into logs or test artifacts.

## Account deletion and scientific classification

Continue using the existing restricted ownerless observation record; do not
create a parallel retention store. Before removing child history, materialize
the acknowledged active scientific projection under the account-deletion fence
using an explicit field allowlist. Exclude unclassified new fields by default.

| Data                                                                                                               | Planned account-deletion disposition                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Permitted active scientific facts                                                                                  | Materialize only the reviewed allowlist in the existing restricted observation record. Include approved taxonomy, observation measurements, confidence, review interpretation, time/location, and content-free provenance only as authorized by the canonical retention contract. |
| Full private analysis history and selection-operation history                                                      | Delete; do not retain complete result JSON as a scientific snapshot.                                                                                                                                                                                                              |
| Input descriptions, supplementary context, notes, media and evidence references                                    | Remove under the account-owned content and storage-cleanup contract.                                                                                                                                                                                                              |
| Public posts, community content, chat messages and context snapshots, personal collections and account attribution | Delete through their reviewed account-cleanup owners.                                                                                                                                                                                                                             |
| Required content-free deletion fences and operational receipts                                                     | Retain only the minimally permitted, account-detached form under their existing explicit retention rules. No history payloads or private context.                                                                                                                                 |

Stage 0 produces the exact column-by-column allowlist and clearing/deletion
classification. This is a prerequisite to schema implementation, not permission
to infer scientific retention from a column's name or JSON membership. Preserve
permitted scientific facts before cascading deletion; never spread a complete
child payload into the retained row.

Scientific projection, ownership detachment, and child cleanup are
transactionally coordinated so interruption cannot lose permitted facts or
retain private child history. Existing storage outbox and verified external
erasure ordering remain intact. Update the canonical retention contract,
disclosures, account-deletion tests, and required review artifacts with the
implementing change. Retained rows are ownerless, not assumed anonymous.

## Migration plan

### Server migration

Add forward migrations; never edit applied history. Inventory immutable scan and
ingestion-job recovery evidence, effective species projections, review lineage,
all scan-ID consumers, and current deletion/retention queues.

For each eligible surviving observation, seed history from evidence that really
exists while preserving the current selected identification, confirmation,
correction, rejection, and community state. Do not select the oldest entry as a
migration policy. A user correction remains review state, not fabricated AI
output. Preserve unknown provenance as unknown and missing history as missing.

Backfill and enrollment are bounded, resumable, and revision-checked. Concurrent
reviews, selections, ownership transitions, deletion, and old producer writes
must either serialize safely or cause a retry before enrollment. Do not
reconstruct tombstoned generations. Switch projections only after result and
authority preservation has been verified.

### SwiftData migration

Identify the outgoing schema from source at implementation time. Freeze and
compile its complete affected shape before editing active models. Add the next
schema and ordered migration stage, update all startup/recovery plans and
aliases, and preserve historical schema identities.

Use disk-backed fixtures with existing corrections, confirmations, rejections,
community state, pending reviews, collections, mixed media, and legacy deletion
tasks. Preserve ordered pending intent and account ownership. A store migration
or missing-history error must not trigger broad store deletion. Migration must
not replay an ambiguous legacy deletion as a new authorized observation delete.

### Cross-version compatibility

Update generated Identify contracts, hand-written status/history/review/chat
DTOs, request builders, offline jobs, recovery, account merging, and every
consumer that currently treats scan ID as analysis ID. Preserve stable
observation relationships. Capability checks must be server-enforced for reads
and mutations, not just UI feature flags.

Existing installations must continue to display their saved effective state
until safe migration is available. Do not hide malformed versioned history by
decoding it as a legacy result. Preserve recoverable local state and surface
explicit update, conflict, or retry outcomes.

## Implementation stages and exit criteria

All stages include their relevant migration, concurrency, deletion,
compatibility, and integration tests. UI-stage validation is not a substitute
for testing earlier contracts.

| Stage                                | Deliverables                                                                                                                                                                                                         | Required exit evidence                                                                                                                                                                                      |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0: Contract decisions                | Executable schema design; exact identities, fields, bounds, errors and route mapping; authority transitions; lock order; scientific allowlist; private media access design; capability and legacy-deletion protocol. | Producer/consumer inventory; independent contract review; mapped acceptance cases; no unresolved destructive or privacy classification.                                                                     |
| 1: Storage and sync                  | Server and SwiftData history storage; migration; owner-only reads; active projection; revisioned selection/outbox; retention, deletion and compatibility fences; public/chat schema foundations.                     | Disposable migration replay and role-denial tests; disk-store migration preserving corrections; account-switch/merge and concurrent review tests; expiry/deletion races; legacy-client rejection.           |
| 2: Reanalysis and restoration        | Analysis-bound request/replay/funding integration; durable completion; append-only reanalysis; conditional restoration/Undo; removal of both replacement-deletion paths; current-authority reconciliation.           | Lost-response and settlement tests; deletion during inference; first-completion races; A → B → A with reordered work; rejected/non-biological results; interrupted finalization and stale acknowledgements. |
| 3: History UI and connected features | Comparison/history UI; pending/conflict presentation; explicit publication update and automatic invalidation; immutable chat admission/context recovery; full deletion and retention flows.                          | End-to-end native/backend/public-consumer tests; accessibility; reinstall/hydration; post/discussion continuity; chat recovery; allowlist-only account retention; complete affected-surface gates.          |

Primary implementation owners are Core AI completion and capture submission,
Core Data repositories/history/offline sync, active schema and migration owners,
Insights identification review and Scans presentation, shared Identify
contracts/finalization/funding, database review/deletion/retention routines,
Explore publication/projections, Field Chat admission, and account-deletion
cleanup. Add read-only independent security/concurrency/contract review at stage
boundaries; repository edits remain with one writing owner.

## Acceptance matrix

These are required future tests, not claims of existing coverage or completed
validation.

| Case                                                                         | Required result                                                                                                                                           |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Multiple successful reanalyses                                               | One library observation; every completed result retained; current selection unchanged until explicit choice.                                              |
| Earliest/newest restoration, restart and reinstall                           | Selected result and its current authority survive; newer history, notes, collections, and evidence remain intact.                                         |
| Existing correction during migration                                         | Effective identification, confirmation/rejection/community state, and pending review ordering remain unchanged.                                           |
| Missing original history                                                     | Surviving evidence preserved without fabricated results or an unsupported Original label.                                                                 |
| Same analysis ID, lost completion response                                   | Recover one result and original settlement; no second complimentary consumption or replay inference.                                                      |
| Same analysis ID, changed payload                                            | Conflict; no mutation or second hold.                                                                                                                     |
| Proven failure versus ambiguous failure                                      | Terminal proof releases held credit; ambiguous/retryable state retains it; provider counters follow separate rules.                                       |
| Paid status becomes active before completion                                 | Existing paid-before-completion release behavior preserved.                                                                                               |
| Interrupted evidence promotion or completion                                 | No false completed result; bounded recovery finishes the same analysis without deleting earlier history.                                                  |
| Concurrent first completions                                                 | Exactly one initial selection; other completion appends; initialization cannot run again.                                                                 |
| Late reanalysis after another selection                                      | Append only; no selection or presentation takeover.                                                                                                       |
| Confirmation of A then selection of B                                        | B gains no authority from A.                                                                                                                              |
| Rejection, acceptance obligation, broader taxon and non-biological selection | Correct visible state and authority-table behavior; no unintended species credit or source retirement.                                                    |
| Confirmation/rejection/community withdrawal races selection                  | Revision conflict or one serialized valid outcome; no stale authority application.                                                                        |
| A → B → A, receipts delivered out of order                                   | Final projection and credits match the latest revision; no duplicate award or stale restoration.                                                          |
| Undo after another device changes state                                      | Conflict; newer choice remains intact.                                                                                                                    |
| Offline dependent selections and account switch                              | Durable ordering; pending UI; acknowledged-only credits; no cross-account mutation or silent rebase.                                                      |
| Owner/account merge during pending work                                      | Preserve exact ownership and funding linkage through established merge rules; retired-session callbacks fail closed.                                      |
| Delete during inference, selection, replay, chat or media promotion          | Terminal parent fence wins; no child resurrection; late assets cleaned; held credit settled through existing orchestrator.                                |
| Legacy queued replacement deletion after upgrade or remote enrollment        | Server rejects without a tombstone; upgraded client holds the task for reconciliation rather than indefinite retry or translation into explicit deletion. |
| Legacy app deletes its local copy before server rejection                    | Retained remote history survives and is restored through compatible hydration; no claim of restoring unsynced local-only metadata.                        |
| Non-biological selection and 30-day expiry                                   | Enrolled observation and biological/non-biological history remain retained.                                                                               |
| Expiry racing enrollment                                                     | One locked outcome; an existing tombstone is never reversed.                                                                                              |
| Explicit delete with shared evidence and publication                         | Entire observation history and associated content follow deletion contract; no dangling live asset or result.                                             |
| Private selection after publication                                          | Post snapshot and discussion unchanged.                                                                                                                   |
| Explicit Update shared identification                                        | Existing post updated atomically after checks; publication revision recorded; no duplicate post.                                                          |
| Authority withdrawal on published A while private B is selected              | Public post becomes unresolved and loses species-dependent authority; private B remains independent.                                                      |
| Delayed public invalidation or stale republish job                           | Public serving cannot retain withdrawn confirmation or restore obsolete eligibility.                                                                      |
| Interrupted chat followed by selection, notes or community changes           | Exact retry uses the admitted immutable context and fixed conversation prefix; new turns may use current context.                                         |
| Legacy incomplete chat without immutable context                             | Explicit non-replayable outcome; no silent dispatch with changed content.                                                                                 |
| Unauthorized history or media access                                         | Cross-owner, anonymous, direct-object and public-projection paths cannot expose unpublished evidence.                                                     |
| Account deletion with pending selection and history                          | Retain only allowlisted acknowledged scientific facts; remove private children and references; reject late callbacks.                                     |
| New unclassified result field                                                | Excluded from account-retained projection by default; never copied through generic JSON expansion.                                                        |
| Historical migration and startup failure                                     | Recoverable stores preserved; no broad destructive rescue.                                                                                                |
| Large history and accessibility sizes                                        | Bounded pagination/media decoding, stable selection, usable comparison/actions, and correct VoiceOver labels.                                             |

## Documentation and verification ownership

Update canonical contracts in the same changes as their implementations. This
RFC remains the dated plan and receives status/evidence links as stages finish.

| Contract                                 | Canonical documentation                                                                                                                                                                                                                |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identification UX and capture/reanalysis | [Insight Sheet](../features-and-hardware/05-insight-sheet.md), [Camera and Hardware](../features-and-hardware/01-camera-and-hardware.md), and affected iOS feature READMEs.                                                            |
| Storage, migration and recovery          | [Database schema](../backend-and-data/04-database-schema.md), [startup recovery](../backend-and-data/08-startup-store-recovery.md), [offline sync](../backend-and-data/01-offline-sync-pipeline.md), and Historical Sync README.       |
| Wire, authority and inference            | [API contracts](../backend-and-data/05-api-contracts.md), [AI engineering](../system-architecture/04-ai-engineering.md), [ingestion durability](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md), and route READMEs. |
| Settlement                               | [Complimentary Pro scans](../backend-and-data/18-complimentary-pro-scans.md).                                                                                                                                                          |
| Credits, public publication and chat     | [Field Trips](../features-and-hardware/25-field-trips.md), Explore publication/projection documentation, and [Field Chat](../../apps/ios/Merian/Features/FieldChat/README.md).                                                         |
| Privacy, deletion and retention          | [Scientific observation retention](../backend-and-data/17-scientific-observation-retention.md), deletion/retention route READMEs, affected disclosures and privacy artifacts.                                                          |
| Gates and release evidence               | [Testing strategy](../development-guides/08-testing-strategy.md), [Supabase runbook](../backend-and-data/06-supabase-deployment-runbook.md), and [iOS release runbook](../development-guides/14-ios-release-versioning.md).            |

For implementation, run focused checks while iterating, then complete every
affected repository gate. Required evidence includes forward migration replay on
a disposable database, actual-role privacy/catalog/concurrency tests, recursive
Deno checks and tests, generated DTO regeneration and diff review, SwiftData
migration guardrails and disk-backed migration/startup tests, native compilation
and focused tests through `make ios-local-build`, and affected web/admin tests,
type checks and builds. Regenerate the Xcode project from `project.yml` when
source/schema membership changes. Preserve the canonical toolchain, fixture,
storage, and exact-SHA requirements.

Format changed Markdown with `deno fmt`, run `make validate-markdown-format`,
and inspect `git diff --check`. Report unrun checks and environment limitations
explicitly. No production response bodies, personal data, credentials, or raw
coordinates belong in fixtures, logs, evidence, or this plan.

## Activation and rollback

1. Complete Stage 0 contracts and the exact consumer/retention inventory.
2. Validate additive server protections, migrations, and compatibility behavior
   with the feature disabled.
3. Prepare the matching native reader/writer migration and all public/chat
   consumers. Obtain exact-SHA evidence for the entire affected bundle.
4. Under separately authorized operations, deploy backend protections before
   distributing compatible native behavior. Enable enrollment/reanalysis only
   after the legacy-client gate and required runtime evidence are satisfied.
5. Observe aggregate invariant failures, reconciliation lag, legacy-request
   rejection, deletion backlog, and settlement outcomes without logging private
   content or identifiers.

Rollback disables new enrollment/reanalysis or selection mutations as necessary
while preserving existing history, acknowledged selection, recovery, and
explicit deletion. Keep the history-capable reader and server protections for
already-enrolled observations. Never roll those observations back onto
destructive replacement, classification-based expiry, or legacy deletion paths.
Prefer forward repair; do not drop history tables or revert schema versions to
hide a defect.

Implementation, candidate validation, deployment, activation, runtime evidence,
and recovery of historical data are separate statuses.

## Implementation progress

The initial inventory below records the October 2 foundation. Dated checkpoints
that follow extend it; the latest is the
[protected photo binding checkpoint](#2026-10-03-protected-photo-binding-checkpoint).

The current change implements backend preparation and native legacy-deletion
refusal handling; no stage is declared complete and the restoration feature is
not available in the app yet.

Implemented locally:

- Bounded identity, selection, pagination and admitted-context contracts, plus
  selection/authority decision tests. Authority projection reuses the existing
  identification policy and does not transfer confirmation between analyses.
- Private immutable result storage, per-analysis review storage, selected state,
  operation receipts, and durable reconciliation obligations. Enrollment and
  selection default closed. No existing scan is migrated or enrolled.
- A private database selection transaction with revision checks, exact retry
  receipts, and atomic selected projection/outbox updates. API roles cannot call
  it. Review transitions invalidate the aggregate revision, including inactive
  results. Credit and publication workers are not wired to this outbox yet.
- Server legacy-deletion rejection before tombstone/media erasure and backend
  non-biological retention exclusion at candidate discovery and locked recheck.
  Account detachment now uses owner-first locking and clears private children.
- Disposable-database fixtures and candidate CI coverage for the new contracts.
  The deletion handler has an execution test proving rejection stops before
  media discovery and deletion completion.

Still required before activation:

- Strict complete-result and evidence producers, safe enrollment/backfill, and
  analysis linkage in ingestion intents/jobs. Preserve request/credit identity
  and recovery through the existing funding owners; no new settlement mechanism
  was added by this preparation.
- Parent deletion fences for every child provider/replay/recovery/media path,
  versioned explicit observation deletion, and native quarantine/migration of
  ambiguous legacy deletion tasks. The follow-up native slice holds an exact
  server refusal durably; owner/origin provenance, reconciliation and release of
  held intent are still absent.
- SwiftData history migration, owner-only bounded reads and protected media
  delivery, account-bound ordered selection sync, and native retention
  exclusion.
- Per-analysis review/community integration, active scan read projection and
  revision-guarded Field Trip/species reconciliation. The original immutable
  `scans` result fields are not overwritten by the private selection function.
- Append-only reanalysis and initial-selection integration, removal of both
  replacement-deletion paths, comparison/history UI, and conditional Undo.
- Published-analysis snapshots and authority invalidation, immutable chat
  admission/recovery, and the explicit scientific-field allowlist materialized
  before account detachment clears private history.
- The remaining cross-surface migration, concurrency, privacy and end-to-end
  acceptance cases above. Unit predicates and private SQL tests do not
  constitute evidence that funding, public visibility or native recovery are
  integrated.

Backend implementation lives in
[`_shared/analysisHistory`](../../services/supabase/functions/_shared/analysisHistory/README.md)
and the three forward migrations beginning `20261002213257`, `20261002215330`,
and `20261002215809`. Do not enable their gates independently of the remaining
activation requirements.

Local verification recorded on October 2, 2026 for this preparation:

- Forward migration replay and all 72 database catalog files passed on an
  isolated disposable database: 503 assertions, including 30 history assertions.
- All 69 migration-contract files passed: 365 tests. Focused history and
  deletion tests passed: 26 tests. All 104 Edge Function entrypoints
  type-checked with their deploy-time configurations.
- The complete Supabase tooling gate passed, including generated DTO validation.
  A first sandboxed run stopped at a synthetic terminal-input fixture; the
  isolated fixture and complete rerun passed with local PTY access.
- Whole-tree Supabase formatting and lint, changed Markdown formatting, and
  `git diff --check` passed. Independent read-only review found no remaining
  material defect in this prepared slice.
- No iOS schema/UI, web or admin implementation was changed or validated as a
  working history feature. No deployment, enrollment, or feature activation was
  performed. The task's disposable database was stopped after verification.

### Documentation and verification clarification — October 2, 2026

The follow-up review reran the 26 focused tests, 365 migration-contract tests,
Supabase formatting, scoped lint, Markdown formatting and diff checks. It
reviewed the earlier full catalog/tooling evidence; it did not repeat the
database run or prove simultaneous multi-session behavior. A → B → A receipt
replay is covered sequentially, while out-of-order credit-worker delivery and
concurrent provider/deletion execution remain acceptance work.

Current implementation ownership lives in the
[schema contract](../backend-and-data/04-database-schema.md#prepared-observation-analysis-history)
and history README. The
[verification matrix](../development-guides/08-testing-strategy.md#observation-analysis-history-preparation)
and
[activation hold](../backend-and-data/06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold)
are the canonical test and operational boundaries. The
[native compatibility status](../backend-and-data/01-offline-sync-pipeline.md#reanalysis-history-compatibility-status--october-2-2026)
records the still-active replacement flow and remaining compatibility work;
subsequent native progress is recorded below.

The
[retention correction](../backend-and-data/17-scientific-observation-retention.md#account-tombstone-data-boundary)
also records pre-existing review triggers that clear confirmation/rejection
authority on account detachment. The future scientific allowlist must
materialize permitted acknowledged facts before those resets and private-child
cleanup; it cannot rely on the old claim that every review field survives
unchanged.

### Native legacy-deletion hold — October 2, 2026

The deletion queue now interprets only HTTP 409 plus
`legacy_observation_delete_requires_upgrade` as refusal of legacy authority. It
preserves `PendingCloudDeletionTask`, records a durable `needsAttention` hold
and no retry deadline, and excludes that hold from generic status repair and
duplicate enqueue. Ordinary failures retain unlimited capped-backoff retry until
explicit success. Existing SwiftData fields hold this state; the schema version
and model shape are unchanged.

Discovery examines at most two 200-row keyset pages per drain and dispatches at
most 200 tasks. A versioned cursor in a dedicated `OfflineJobRecord` and its
scheduler deadline continue a held backlog without unbounded foreground scans.
End-of-sweep clears the cursor. If prior persisted pages offered runnable work,
a saved marker schedules one head sweep to recover a batch interrupted before
dispatch or acknowledgement. An all-held sweep has no recurring wake.

This implements the server-refusal handling portion of compatibility, not full
legacy migration. Old task rows have no owner or deletion-origin proof. No new
observation-delete authority, held-task reconciliation, history hydration,
append-only native reanalysis or restoration UI is supplied by this slice. Those
remain activation prerequisites along with the other stages above.

Local verification for this native slice:

- The complete `merianTests` target passed through `make ios-local-build` on the
  iPhone 18 Pro simulator running iOS 27.0: 1,427 XCTest tests and 3,175 Swift
  Testing tests across 483 Swift Testing suites. This final-source run includes
  the disk reopen, bounded backlog, interrupted offered-batch, transport refusal
  and claim-before-dispatch regressions. Its result bundle is
  `.artifacts/local-ios/630bf5ce501f4350b6733745c836e12e.xcresult`.
- An earlier broad run exposed a source assertion expecting the old dispatcher
  signature. The assertion was updated without changing its persistence-order
  requirement. That superseded run was interrupted; only the complete final run
  above is passing evidence for this slice.
- Project, migration guardrail, privacy manifest, transport security and
  versioning validators passed, as did the complete `test-ios-ci-tooling` target
  and generated Edge DTO contract validation.
- The 26 focused Deno history/deletion tests were rerun and passed. Changed
  Markdown formatting, whole-tree Supabase formatting, local documentation links
  and `git diff --check` passed. The earlier database catalog and full
  migration-contract evidence was not rerun for this native-only code change.
- No install-over migration, device UI, enrollment or hosted activation was
  performed. Full native history, account-bound synchronization and the
  remaining integration cases are still unimplemented and unverified.

The next implementation slice must establish owner/origin-bound deletion intent
and safe native history storage/migration, preserving the currently selected
identification and its review state. Coordinate that with strict server result
producers and observation/analysis/retry linkage before enabling enrollment.
After storage and recovery are connected, replace both native source-deletion
paths with append-only completion, add explicit selection/Undo and history UI,
and complete publication/chat/credit and scientific-retention integrations.

### Native scheduler and cursor review corrections — October 2, 2026

Independent follow-up review found that the discovery deadline could re-enter
the entire scheduler every second while a slow deletion batch held the
single-flight latch. The scheduler now excludes only that discovery deadline
while the latch is held. The persisted cursor and deadline survive restart;
unrelated retries stay visible. The drain releases its latch and rearms
persisted deadlines on every exit, including preparation or result-save failure.

`discoveryWakeWaitsForActiveDeletionBatch` checks the durable continuation
during dispatch, preservation of an unrelated retry deadline, and rearming after
the batch. This correction does not enable history or change deletion authority.

The focused rerun passed that new scheduling regression but exposed a paging
failure in the 801-task backlog. Foundation's default string sort uses localized
numeric ordering, which can disagree with the cursor predicate's lexical `>`
comparison. The scan-ID tie-breaker now explicitly uses `.lexical`. The backlog
fixture uses fixed hexadecimal IDs with identical timestamps to exercise this
boundary reproducibly. The failed run is diagnostic evidence, not a passing
verification result.

Final verification after both corrections: a clean simulator build and the
complete `merianTests` target passed through `make ios-local-build`: 1,427
XCTest tests and 3,176 Swift Testing tests across 483 Swift Testing suites. The
result bundle is
`.artifacts/local-ios/ab3027a1ea9142bf98836d8ecbceeb64.xcresult`. Both the fixed
801-task cursor regression and the active-batch scheduling regression passed.
Project, migration guardrail, privacy, transport-security, versioning, changed
Markdown and whole-tree Supabase formatting checks passed, along with
`git diff --check`. No deployment or feature activation was performed.

### Native deletion provenance and account safety — October 2, 2026

This follow-up implements the next compatibility slice. New pending cloud
requests retain a versioned requesting-account and origin envelope in existing
`OfflineJobRecord.metadataJSON`, atomically with local erasure. Explicit user
removal, reanalysis replacement, and automatic non-biological retention have
separate origins. Provenance records the requester; it never proves scan
ownership or grants whole-history deletion authority.

Existing pending tasks cannot be retagged by duplicate enqueue. Bounded
discovery quarantines missing/invalid provenance without dispatch, using
`cloud_deletion_intent_requires_review`. This is a lazy semantic migration with
no V54 model-shape change. There is no automatic hold release. Known foreign
requests remain unchanged; their deadlines do not wake the current account. The
drain retains an account lease, binds transport to that account, and fences
acknowledgement against a stale lease or replaced context. Bound 401 responses
return to durable retry rather than waiting for their own lease through Auth
recovery. A settled authentication lifecycle resumes deletion-only work when the
original account returns, even without foreground/reconnect.

The
[offline deletion contract](../backend-and-data/01-offline-sync-pipeline.md#2-cloud-deletion-tasking-pendingclouddeletiontask)
owns current details. The prior sections record their earlier slice state; they
do not mean new requests still lack provenance. Legacy reconciliation, explicit
versioned observation deletion, native retained-history storage, and append-only
completion remain unimplemented. Both server enrollment and selection gates stay
disabled. No deployment, historical recovery, or history UI is included.

Next: native immutable-history storage and migration preserving the selected
identification and review state, coordinated with strict result/evidence
producers and observation/analysis/retry identities. Then replace
source-retirement paths with append-only completion and connect selection/Undo
and history presentation.

The account-switch review also found that a shared discovery cursor could skip
an earlier prefix belonging to the returning account. Cursor version 2 now
records its discovery account and restarts at the head for a different account,
legacy unbound cursor, or invalid metadata. A 401-task regression switches back
through the Auth lifecycle and verifies that the first 200 owner requests run,
rather than skipping directly to the final request. Task intent remains the
admission boundary; cursor ownership is only scheduling metadata.

Final local verification for this account/provenance slice:

- `make ios-local-build` completed the full `merianTests` target on the iPhone
  18 Pro / iOS 27.0 simulator: 1,427 XCTest tests plus 3,184 Swift Testing tests
  across 484 suites, all passing (4,611 total). The final-source result bundle
  is `.artifacts/local-ios/28dc2499605f4d0ebb91212941e83010.xcresult`.
- The focused cursor/deletion/architecture run passed 29 tests before the final
  full run. The full run also includes the actor-isolation and JSON-encoding
  cleanup; no new actor-isolation or optional-data-conversion warning remains.
- Project generation and diff review, project/resource validation, migration
  guardrails, event routing, privacy manifest, transport security, versioning,
  generated Edge DTO validation, changed-Markdown formatting, whole-tree
  Supabase formatting, documentation links, and `git diff --check` passed.
- Earlier runs exposed test assumptions and stale architecture budgets/check
  counts. Review also found the account-return wake and foreign-cursor gaps;
  both were corrected and covered before the final full pass. Superseded or
  interrupted runs are not final-source evidence.
- No hosted mutation, deployment, history enrollment, installation-over-upgrade
  exercise, or device UI validation was performed. The earlier backend database
  and migration-contract evidence was not rerun for this native-only slice.

### 2026-10-02 native storage checkpoint (V55)

The next preparation slice adds immutable private child-result storage and
freezes V54 before active-model changes. Migration deliberately leaves history
empty while preserving every existing projection/review field; it does not
create an analysis from a corrected legacy projection. Existing scans have an
explicit initialized-selection marker with no invented selected ID, owner, or
server revision. Verified surviving-evidence seeding remains part of enrollment.
See the
[current V55 contract](../backend-and-data/04-database-schema.md#native-analysis-history-storage-and-v55).

Parent cascade and explicit account purge cover the new private entity. No
production history writer, reader, enrollment, selection, restoration UI, or
retention-policy activation is introduced here. Next is the verified server
result/reader contract and account-bound native hydration/admission, followed by
append-only reanalysis and selection UI once all activation gates pass.

Verification for the V55 checkpoint:

- The outgoing V54 graph matched all eight active model declarations after
  namespace/indent normalization and compiled before active-model edits.
- The final iOS 27 focused run passed 109 tests. It covers all migration tests,
  storage, architecture, account purge and startup recovery. Result bundle:
  `.artifacts/local-ios/06d732e6798a4e3ca91e108869667170.xcresult`.
- The iOS 26.5 migration/storage/recovery run passed 89 tests. Result bundle:
  `.artifacts/local-ios/880f3f08996b486abb884e6c07ac1076.xcresult`.
- The complete iOS 27 native unit target passed 4,617 tests: 1,427 XCTest cases
  and 3,190 Swift Testing cases across 485 suites. Final result bundle:
  `.artifacts/local-ios/c5d0edc6864e4659b241f4cf3a251364.xcresult`.
- Project membership, migration guardrails and their adversarial fixtures,
  startup source-scope fixtures, complete iOS CI tooling, event routing,
  privacy, transport, versioning, generated Edge DTOs, Markdown formatting,
  Supabase recursive formatting (1,260 files), 534 local documentation links,
  and `git diff --check` passed.
- The initial focused run exposed a full-historical migration crash caused by
  the new child-to-active-scan backlink. The final graph uses the established
  one-way media cascade pattern. The failing historical path passed in both
  simulator runtimes and in the complete unit run. The interrupted broad
  simulator build and superseded failing run are not final-source evidence.
- No hosted mutation, deployment, enrollment, genuine released-binary physical
  install-over, or restoration UI validation was performed. Backend database
  contracts were unchanged and their earlier execution was not repeated for this
  native storage slice. Physical V54 install-over and second-launch acceptance
  remain required before distribution.

### 2026-10-02 owner reader and native admission checkpoint

The next preparation slice adds the owner-only bounded
`get_owned_observation_analysis_page` RPC and its separate default-false
`reader_enabled` gate. The new aggregate database constraint guarantees that
metadata, ordinal, result and evidence fit the V55 one-MiB snapshot together.
The same SQL serializer supplies both the constraint and stable read-back text.
The canonical Identify payload keeps the permanent observation `scan_id`; the
immutable outer envelope owns the independent analysis ID. Shared result/page
parsers reuse the existing Identify and captured-media contracts.

Native `Core/Data/AnalysisHistory` adds an account-lease RPC adapter, bounded
page decoder and all-or-nothing admission for already-enrolled local records. It
preserves exact snapshot bytes (including ordinal), rejects conflicting replays
before insertion, rechecks account generation before save, and never changes
selection or review authority. There is no normal sync or live completion call
site. Migration defaults cannot infer enrollment from login.

Background non-biological deletion now shares the synchronous persistence gate
and uses fresh contexts. Automatic expiry excludes enrolled history at both
discovery and locked recheck. MainActor explicit deletion cannot interleave the
non-suspending MainActor admission commit. Review caught and resolved the
observation/analysis identity distinction, durable ordinal preservation and the
aggregate-size mismatch before final verification.

Read-back preserves server projection metadata such as `species_id` in the
original snapshot bytes. The future completion producer must validate a separate
projection-ready object against canonical Identify data and taxonomy; the
normalized Identify validation view is not a server storage writer. A focused
reader regression covers preservation of this metadata.

The current
[wire contract](../backend-and-data/05-api-contracts.md#prepared-owner-analysis-history-reader)
and [native owner](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md)
define the implementation. Next is durable append-only completion and protected
evidence admission, then verified selection-preserving enrollment and normal
account-bound scheduling/authority hydration. Restoration UI follows those
boundaries. Provider charging, publication/chat integration, explicit versioned
deletion and account-deletion scientific materialization remain under the
existing activation hold. No deployment or gate activation was performed.

Verification for the owner-reader checkpoint:

- A fresh, private disposable database replayed every migration and passed all
  522 assertions across 73 SQL fixtures, including the 19 new reader assertions.
  The shared local database had pre-existing migration drift, so it was not
  reset. The private validation project was stopped after testing.
- The complete database-backed Edge suite passed 2,296 tests and 343 steps,
  including the concurrency cases that require a database. The subsequent
  server-metadata preservation regression passed with all five reader tests. All
  366 discovered migration-contract tests passed.
- Recursive Edge type checking, Deno lint, all 104 function dependency graphs,
  generated Identify/captured-media DTO checks, and the complete Supabase
  tooling phases passed. The tooling run passed 499 standard, 149 evaluation, 20
  Identify DTO and 21 captured-media tests. Its shell phase was rerun
  successfully with local PTY access after a sandboxed synthetic launcher failed
  at terminal input; no provider or hosted request was made.
- Database lint found no schema errors. Security/performance advisors returned
  no errors and no finding naming the new history objects; existing warnings
  remain outside this slice.
- Project generation and membership, migration guardrails, event routing,
  privacy manifest, transport security, versioning, changed-Markdown formatting,
  recursive Supabase formatting, 851 local documentation file links, and
  `git diff --check` passed.
- The complete native target executed 4,626 tests (1,427 XCTest and 3,199 Swift
  Testing). One architecture assertion still named the old retention context
  variable; all other tests passed. The assertion now checks the fresh context
  and shared persistence gate. That initial result bundle is
  `.artifacts/local-ios/af0ea424968f465da1cc33dd09fbcc13.xcresult`; it is not an
  all-green final-suite claim.
- The final rebuilt native run passed all 25 tests across history admission,
  model architecture, non-biological persistence and retention architecture. It
  includes the corrected assertion and the final no-production-call-site guard.
  Result bundle:
  `.artifacts/local-ios/eb052e805cdd45cba90dd74a94404ba2.xcresult`.
- No deployment, activation, real released-binary install-over, restoration UI
  validation or provider-completion integration was performed. Those remain
  explicit acceptance work before release.

### 2026-10-03 private append preparation checkpoint

The completion-path trace established two prerequisites that prevent directly
connecting the existing finalizer to child history: its job/media/funding
contracts share one public scan UUID, and current R2 scan promotion uses public
CDN delivery. Neither a canonical media URL nor an internal table is proof of
private evidence access. No live finalizer, credit ledger, provider invocation,
media promotion or release gate was changed in this slice.

The new private `internal.append_observation_analysis(uuid,jsonb)` transaction
provides the storage boundary for a future completion orchestrator. It has no
API-role execution grant and a separate default-false `append_enabled` gate.
`analysisHistory/append.ts` builds canonical results, discards supplied review
and funding authority, and restores only the separately resolved species link;
the database checks the dictionary binding before storing it. Current append
supports description evidence only. Every media variant is rejected pending
protected promotion, durable receipts, authorized owner reads and cleanup.

Under owner-first locks, append checks current ownership and deletion before
replay, compares the complete immutable input, assigns a server ordinal/time,
and inserts a result with fresh unreviewed authority. Replays return original
bytes without reinstalling old selection. Later results only append. First
selection additionally requires an empty revision-zero history and immutable
`initial_selection_permitted`, recorded on history insertion and false for all
existing rows. A future admission owner must prove new-observation creation
before granting it. Concurrent first results both persist; only the first
initializes selection. The backend and native reader now both reject reused
observation/analysis/source IDs.

This is **storage preparation**, not completed end-to-end reanalysis. The
[canonical append contract](../backend-and-data/05-api-contracts.md#prepared-private-analysis-append)
and
[activation hold](../backend-and-data/06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold)
are current. Next is a protected evidence lifecycle and an admitted
child-analysis intent/provider/recovery contract. A completion orchestrator must
append and settle the existing complimentary hold atomically under those
contracts before reporting success. Verified selection-preserving enrollment and
ordinary native sync follow; history/restoration UI remains downstream. No
deployment or activation was performed.

Verification for the private append checkpoint:

- A clean replay in a task-owned disposable database passed all 556 assertions
  across 74 SQL fixtures, including 34 append assertions. An intermediate
  catalog rerun after the full Edge suite encountered state committed by the
  existing Field Chat integration fixture; reconstructing the disposable
  database restored the expected fresh-migration baseline. No shared database
  was reset.
- The complete database-backed Edge suite passed 2,307 tests and 343 steps. Its
  four new multi-session tests observe actual PostgreSQL blocking for duplicate
  replay, concurrent first results, and both append/deletion orders. The focused
  history suite passed 30 tests; all 367 migration-contract tests passed.
- Recursive Edge type checks and lint passed, as did all 104 function configs
  and isolated dependency graphs. The generated DTO contract is unchanged;
  generated Identify/captured-media validation, Xcode project membership,
  migration guardrails, event routing, privacy, transport and versioning checks
  passed.
- The native focused run passed 14 tests covering history admission and model
  architecture, including matching rejection of reused
  observation/analysis/source IDs. Result bundle:
  `.artifacts/local-ios/9346e82331e04441b19fc7027344ed99.xcresult`.
- Database lint found no schema errors. Changed Markdown and recursive Supabase
  formatting passed; 834 local documentation file links resolved.
- The complete Supabase tooling gate passed: 499 standard tests, 149 evaluation
  tests, 20 Identify DTO tests, 21 captured-media tests and all 18 shell
  fixtures. These tests use synthetic local inputs; no paid/provider execution
  occurred.
- Database advisors reported no errors or findings naming the new history
  objects; pre-existing warnings remain outside this slice. The task-owned
  disposable database was stopped after validation.
- The final complete native unit run passed 4,626 tests: 1,427 XCTest cases and
  3,199 Swift Testing cases across 486 suites. Result bundle:
  `.artifacts/local-ios/45d22e1021cb439e8f2413f461c4f59b.xcresult`. This
  includes the corrected prior-slice retention assertion and current native
  identity validation. No restoration UI or physical install-over was tested.

### 2026-10-03 protected evidence preparation checkpoint

The next storage slice now prepares private evidence receipts, a separate R2
bucket owner, owner-authorized receipt resolution and durable erasure. The two
new media gates remain false; no bucket, credentials, endpoint, live database
adapter or worker schedule was provisioned. V1 result/native wire contracts are
unchanged and append still accepts descriptions only.

The writer copies and hashes bounded bytes, reserves identity before R2 work,
conditionally writes an opaque key, verifies the object, then repeats the
ownership/deletion fence before readiness. Description append and evidence
reservation serialize the same analysis identity, even across observations.
Review caught that race before the slice was finalized; it is now covered by
actual separate PostgreSQL sessions in both orders.

Receipt removal creates a cleanup obligation that survives parent/account
cascade. Cleanup replaces the object with a HEAD-verified empty marker; delayed
conditional writes cannot overwrite it. Marker permanence depends on exclusive
trusted writers and lifecycle protection, not platform Object Lock. Owner reads
issue 30-second no-store bearer URLs; new reads reject deleted observations,
while already-issued URLs expire or lose content at marker replacement. The
canonical
[API contract](../backend-and-data/05-api-contracts.md#prepared-protected-evidence-lifecycle),
[credential ownership](../backend-and-data/13-server-credentials-and-database-release-safety.md#prepared-history-evidence-credentials)
and activation hold describe these limits.

Next: admitted child-analysis intents, provider attempts/recovery, and a
versioned manifest that binds ready protected receipts to durable completion and
existing complimentary settlement in one transaction. That work must also
connect cancellation/expiry cleanup, owner delivery, and explicit deletion
orchestration. Verified enrollment/sync and restoration UI follow. This
checkpoint does not claim end-to-end reversible reanalysis or authorize
deployment.

Local verification for this checkpoint:

- The disposable migration replay and 75 SQL fixtures passed 593 assertions,
  including 37 evidence assertions. Those include a late completion attempting
  to authorize a replacement reservation after expiry; completion now requires
  the exact object generation, and the replacement stays unreadable.
- The database-backed Edge suite passed 2,325 tests and 343 steps, including all
  six evidence concurrency cases. Eleven pure storage tests use synthetic
  transport; they do not prove real R2 behavior. Independent read-only review
  found no remaining actionable issue after the fixes.
- All 368 migration contracts passed. Recursive Edge type checks and whole-tree
  lint passed, together with all 104 isolated entrypoint checks, 104 function
  configs and isolated dependency graphs. The signed transport inventory now
  includes the dedicated evidence owner and its existing deadline adapter.
- The complete tooling suite passed 499 standard tests, 149 evaluation tests, 20
  Identify DTO tests, 21 captured-media tests and 19 shell fixtures. No paid
  inference, real credentials or hosted storage was used.
- All 26 documentation contracts, changed-Markdown formatting, exact recursive
  Supabase formatting and `git diff --check` passed. An initial scoped docs run
  lacked filesystem permission for two referenced source files; rerunning with
  repository read access passed all contracts.
- The first database lint pass found a redundant integer-loop variable
  declaration; it was removed before final replay. Native code and wire DTOs
  were unchanged in this slice, so the previous full native run remains the
  latest evidence; native tests were not rerun.
- The final clean replay repeated all 593 SQL assertions and 2,325 Edge tests
  successfully. Database lint returned no findings; advisors returned no errors
  or new history findings (103 existing security warnings and 79 existing
  performance warnings). The task-owned disposable database was stopped after
  validation. No shared database was reset.

### 2026-10-03 funded child-analysis preparation checkpoint

Private description-only admission now stores immutable input and the original
client capability claims before dispatch. A separate analysis ID owns the
complimentary hold, reservation attempts and single admitted invocation.
Dispatch accounts provider execution; durable completion appends a result and
settles the credit in the same transaction, saving an exact replay receipt.
Reanalysis preserves the selected identification. A proven failure releases the
hold; ambiguous work remains recoverable and cannot trigger another provider
execution.

The existing public scan orchestrators and new private child orchestrators share
one credit settlement helper. Legacy ingestion, quota, provider reporting and
scan completion cannot bypass child admission. Parent deletion/account
detachment clear private intents and release unfinished holds, leaving a
completed ownerless deleted-generation marker for each retired child.
Separate-session tests cover those races, including a delayed legacy request
blocked behind admission or deletion. Description-only admission and protected
media cannot share an analysis until the future manifest contract binds ready
receipts.

Admission, dispatch and every earlier gate remain false. No live endpoint,
provider adapter, recovery schedule, native consumer or storage deployment was
added. This completes a transaction boundary, not end-to-end reversible
reanalysis. The current app still lacks history restoration.

Next: a versioned manifest that binds ready private media receipts to immutable
input/result completion; authenticated orchestration and bounded
recovery/delivery using these private primitives; analytics identity
discrimination; and explicit observation deletion delivery. Verified enrollment
and native history/selection sync precede the comparison/restore UI. Public
snapshots, immutable chat context and account-deletion scientific-field
materialization remain activation gates.

Local verification:

- The fresh disposable database passed all 76 SQL fixtures and 635 assertions,
  including 42 funding assertions. Database lint found no errors or warnings.
- The full Edge suite passed 2,336 tests and 343 steps, including seven new
  separate-session funding/deletion/legacy races. The focused builder tests use
  synthetic inputs and make no provider calls.
- All 369 migration contracts passed, along with both generated DTO validators,
  recursive Edge type checks, whole-tree lint, all 104 isolated entrypoint
  checks/configs and the 412-file dependency graph.
- All 26 documentation contracts passed. Security/performance advisors returned
  no errors or findings for the new objects; 103 existing security warnings and
  79 existing performance warnings remain.
- Native code and public wire DTOs were unchanged in this slice. Native tests
  were not rerun; prior native evidence does not establish an implemented undo
  UI.
- Tooling passed 499 standard tests, 157 evaluation tests, 20 Identify DTO tests
  and 21 captured-media tests. The full tooling command then stopped at the
  synthetic Gemini PTY hidden-key fixture under sandboxing; that fixture and all
  19 shell fixtures passed when rerun with local PTY access. No real credentials
  or paid/provider execution was used.
- Changed-Markdown formatting, exact recursive Supabase formatting and
  `git diff --check` passed. Independent read-only review found no remaining
  material issue. The task-owned disposable database was stopped; no shared
  database was reset or deployed.

### 2026-10-03 protected photo binding checkpoint

V2 now binds ready private still-photo receipts to admitted child analyses and
funded completion. The ordered immutable manifest stores only private media IDs,
verified content type, byte count and digest, plus descriptions. It excludes
object UUIDs/keys and delivery URLs. Admission checks the exact receipt set
before holding credit, pins it through ambiguous work and completion, and routes
via the existing photo assignment. Proven terminal failure queues unused photo
erasure; parent/account deletion supersedes pins. A generation-specific expiry
primitive also retires unbound ready uploads. Existing description paths and
credit rules remain intact.

A new `protected_analysis_enabled` gate remains false, as do all earlier gates.
V2 still-photo input requires future history capability 8. The serializer
preserves V1 bytes and explicitly marks V2 snapshots. Protocol-7 reads reject an
entire V2-containing history after owner/deletion checks; no partial page or
public URL fallback is supplied. Native storage/decoders remain V1-only. There
is no provider materializer, live endpoint, cleanup schedule or production
activation. Audio/video binding is deliberately unsupported because their
playback/transcript/frame relationships need a separate contract.

The
[current V2 contract](../backend-and-data/05-api-contracts.md#prepared-protected-photo-analyses)
owns compatibility, pinning, terminal cleanup and exact bounds. Next implement
coordinated protocol-8 owner reads, native V2 decoding/admission and private
photo resolution, then authenticated provider orchestration and bounded
recovery/delivery. Verified enrollment, selection sync, comparison/restore UI,
public/chat snapshots and scientific allowlist materialization still precede
feature activation.

Local verification:

- Fresh migration replay passed all 77 SQL fixtures and 665 assertions,
  including 30 protected-photo assertions. Database lint returned no findings.
  An initial lint warning for an untyped empty UUID array was fixed; the first
  photo fixture also correctly failed a stale Gemini preflight claim against the
  existing OpenAI photo binding, then passed with the fixture's claim corrected.
- Four separate-session protected-photo cases passed: duplicate completion,
  deletion before completion, completion before deletion, and account
  detachment. Six new canonical-builder tests cover privacy, bounds, capability
  and old-reader rejection. Tests use synthetic receipts and no hosted
  media/provider calls.
- The full tooling command passed 499 standard tests, 157 evaluation tests, 20
  Identify DTO tests, 21 captured-media tests and all 19 synthetic shell
  fixtures. Local PTY access was used for the hidden-key launcher fixtures.
- All 370 migration contracts and 26 documentation contracts passed. Security
  and performance advisors reported no errors or new-object findings; 103
  pre-existing security warnings and 79 performance warnings remain.
- Independent read-only review found no current blocker. The media-binding
  trigger documents that its earlier generation trigger owns the parent locks
  before the child lock. Native source/DTOs were unchanged and native tests were
  not rerun; this is not evidence of an implemented restoration UI.
- The complete database-backed Edge suite passed 2,347 tests and 343 steps.
  Recursive type checking and whole-tree lint passed, as did both generated DTO
  validators, all 104 isolated entrypoint checks/configs and the 412-file
  runtime dependency graph. Changed-Markdown and exact recursive Supabase
  formatting passed. No deployment or gate activation occurred.

### 2026-10-03 protocol-8 owner read checkpoint

The ninth migration, `20261003070545_prepare_protocol8_history_reads.sql`,
prepares mixed V1/V2 reads through the existing owner RPC. It preserves the page
schema, serializer bytes, pagination bounds, deletion ordering and protocol-7
whole-history refusal. Native history decoding/admission now supports both
versions and stores each exact snapshot version. V55 has no stored-shape change.

The new authenticated `resolve-history-photo` source and service-only receipt
RPC resolve only completed V2 photo references. Owner/deletion checks precede
signing and run again before response delivery. Native photo loading validates
the temporary ticket, uses ephemeral no-cache/no-cookie transport, rejects
redirects, bounds streamed bytes and checks content hashes. Account and pending
deletion checks surround suspension; no signed URL or image bytes are persisted.
The loader returns transient data; UI rendering is not connected.

All activation gates remain false. No deployment, bucket provisioning, hosted R2
smoke or paid inference occurred. The current contract is
[protocol-8 reads and private photo resolution](../backend-and-data/05-api-contracts.md#prepared-protocol-8-reads-and-private-photo-resolution).
Next implementation remains authenticated analysis orchestration and recovery,
verified enrollment/authority sync, explicit deletion delivery, and eventually
the history sheet with separate preview and selection actions. Public/chat
snapshots and scientific allowlisting remain activation requirements.

Verification for this checkpoint:

- Fresh full migration replay passed 78 SQL fixtures and 684 assertions,
  including 19 new owner/protocol/media-read assertions. Database lint found no
  errors. Three new separate-session read/deletion/account races passed.
- The complete database-backed Edge suite passed 2,355 tests and 343 steps.
  Recursive type checking, whole-tree lint, generated DTO validators, 105
  isolated entrypoints/configs, 371 migration contracts and 26 documentation
  contracts passed. The new route is in the maintained fleet inventory.
- Security/performance advisors reported the same 103/79 existing warnings and
  no errors or new findings. The disposable database was stopped after checks.
- Independent read-only review found no code blocker. Current documentation was
  reconciled; earlier checkpoint verification remains historical evidence.
- The complete tooling command passed: 499 standard tests, 157 evaluation tests,
  20 Identify DTO tests, 21 captured-media tests and all 19 synthetic shell
  fixtures. The runtime dependency graph contains 418 files across 105 isolated
  entrypoints. No generated Identify/captured-media DTO changed.
- Full native build/unit verification passed on the checkout-local iOS 26.4
  simulator: 1,427 XCTest cases plus 3,205 Swift Testing tests (4,632 total),
  including six new private-photo/V2 cases and the existing migration suite.
  Evidence: `.artifacts/local-ios/f3018a686d014edfb1344dd680bc7791.xcresult`.
  XcodeGen, project/migration guardrails, changed-Markdown formatting and the
  exact recursive Supabase formatting gate passed. Hosted storage behavior and
  visible photo rendering were not exercised.

### 2026-10-03 analysis orchestration and recovery checkpoint

Migration `20261003074429_prepare_observation_analysis_recovery.sql` and the
prepared `analyze-observation` / `recover-observation-analyses` endpoints now
connect immutable V1/V2 inputs to the existing qualified provider adapters. They
preserve separate observation, analysis, quota, invocation and work-claim
identities. New admission and dispatch require the applicable completion gates.
All gates remain false; no endpoint, schedule, bucket or paid inference was
activated.

Received canonical output is saved before taxonomy work. A later worker can
resolve the dictionary identity, save the exact matching draft and atomically
complete without another provider call. Taxonomy runs under the parent fence and
never overwrites curated facts or publishes private result prose. Private photo
materialization validates exact bytes, type, digest and erasure markers. The
executable photo boundary accepts five JPEG/PNG images, 5 MiB combined and
32,000 UTF-16 code units of description context; stored HEIC evidence remains
readable but requires separately prepared input for inference.

SQL dispatch is the external-processing authorization point. Deletion after it
cannot retract already-authorized network work, but wins every persistence and
replay operation. A live worker that has not entered provider invocation may
cancel after a dispatch-RPC failure using its still-current claim. A crash,
expired claim or uncertain provider outcome cannot manufacture that proof: the
hold stays pending and automatic recovery never redispatches. Qualified provider
retrieval/idempotency remains an activation limitation.

Verification recorded for this checkpoint:

- Eight history SQL fixtures passed 240 assertions, including the new recovery
  fixture; schema lint found no errors. All 28 separate-session history
  concurrency tests passed, including duplicate work claims and late
  output/deletion/account ordering.
- The final history/handler/documentation group passed 93 tests; the subsequent
  HEIC/text-boundary and service-auth inventory group passed 17 tests. Recursive
  Edge type checks, 107 isolated entrypoints/configs, the 428-file dependency
  graph, 372 migration contracts, generated DTO validation, whole-tree lint and
  26 documentation contracts passed. No native production or persisted schema
  changed in this slice; prior native evidence is not a new UI test result.
- Independent review found and resolved missing gate coupling, pre-invocation
  cancellation, canonical outcome-to-draft binding, and CI selection. The
  generator-owned Field Chat and identification bundle identities were
  regenerated after reusing the quota IP-HMAC helper, and their diffs reviewed.
- Full shared-workspace validation is not green. A concurrent guest-library
  transition edit invalidated its existing native source-contract test; the full
  Edge run passed 2,373 tests and 343 steps but initially failed that test and
  the new service-auth inventory assertion. The inventory was corrected and
  passed separately. A concurrent
  `20261003080444_persist_private_library_details.sql` then blocked full fresh
  replay at the privileged-routine public-signature constraint. Those unrelated
  edits were preserved. Full tooling also encountered an immutable-resume
  fingerprint mismatch while source was changing; that exact synthetic
  immutable-resume test passed when rerun on its own. A final privileged-routine
  ACL/recovery run passed 30 assertions with clean schema lint.
  Changed-Markdown, recursive Supabase formatting and `git diff --check` passed.
  These are not activation evidence; rerun the complete gates on a stable
  candidate.

#### Next enrollment contract

The server must baseline an existing observation without claiming to recover a
lost original execution. Legacy rows may lack original request bytes, a child
analysis UUID, an exact completion time or private evidence receipts. Enrollment
therefore needs an explicitly versioned imported-identification origin, with
unknown facts represented as unknown. An import timestamp or digest must never
be presented as an original provider completion or request digest. Older readers
must fail closed on a history containing an unsupported origin/version.

Copy the surviving canonical result and the complete current server review pair:
`ai_identification_review`, `confirmed_species_id`,
`user_identification_override`, `user_confirmed_identification`,
`user_review_state`, `confirmed_species_identity`, and
`confirmed_species_identity_revision`. Set that baseline selected atomically;
keep `initial_selection_permitted=false`. The existing effective identity,
confirmation/rejection/community authority and species eligibility must remain
unchanged. Native caches cannot authorize enrollment or reconstruct missing
provider evidence.

Description evidence may be copied only from actual surviving bounded input.
Legacy public URLs are not private receipt proofs; do not manufacture V2 photo
references or descriptions from AI reasoning. The UI calls an imported baseline
a saved identification and shows “Original” only with genuine provenance.
Subsequent review mutations must mirror the selected child authority and advance
the observation revision in the same transaction before enrollment is enabled.
Selection/Undo, deletion delivery, public/chat snapshots, scientific
allowlisting and the native history sheet remain subsequent implementation
slices.

### 2026-10-03 saved-identification enrollment and V56 checkpoint

The saved-baseline contract above is now implemented behind closed rollout
switches. Migration `20261003152940` adds owner-only idempotent enrollment and
an explicit V3 saved-identification origin. It copies the surviving result and
all seven review fields under the observation fence, leaves public scan state
unchanged, selects that baseline once, and never treats a retry as permission to
undo a newer selection. Imported execution digest/completion remain unknown;
legacy public media does not become private evidence. Protocols 7/8 refuse the
entire imported history; protocol 9 reads it without changing V1/V2 bytes.

Native V56 freezes the outgoing V55 graph and makes only child completion
optional. V3 requires nil and retains import time separately; V1/V2 still
require a finite completion. All migration/startup lanes advance through the new
lightweight stage, with source hashes, disk migration and reopen fixtures. The
owner history adapter now uses reader 9; photo resolution stays V2-only on its
existing protocol. No normal app enrollment, authority hydration or UI was
connected by this storage/reader work.

Current contracts are the
[saved import API](../backend-and-data/05-api-contracts.md#prepared-saved-identification-enrollment-and-protocol-9),
[V56 storage](../backend-and-data/04-database-schema.md#v56-unknown-completion-storage)
and
[startup acceptance](../backend-and-data/08-startup-store-recovery.md#v55v56-unknown-completion-acceptance).
The source-created simulator fixtures do not substitute for physical
released-binary install-over or hosted activation evidence.

#### Next authority integration boundary

The immutable result page intentionally carries no mutable authority. A separate
owner-only state read must bind selected result, selected authority and
observation revision under the existing owner/observation/history locks. It must
also support bounded authority reads for history previews. Native admission must
recheck account and deletion, refuse stale revisions, and preserve pending local
review intent. Existing selected-state fields can hold selected authority; a
durable per-analysis authority cache requires a separate forward model, never
mutable data inside immutable result bytes. Selection still needs an explicit
result-to-presentation mapping and ordered credit reconciliation. Review
writers, publicly pinned authority, chat snapshots, deletion delivery and UI
remain held.

### 2026-10-03 atomic state-read checkpoint

The next read boundary is prepared in migration `20261003162801`, with its own
false `state_reader_enabled` switch. One owner-only request returns either the
selected result or one explicitly requested preview, with that child's current
review and the observation revision under the shared locks. Immutable snapshot
bytes and mutable authority remain separate. Explicit preview never selects.
Deno and native decoders share `state-v1.json`; the native cloud adapter has no
normal app caller. Current contract:
[state read](../backend-and-data/05-api-contracts.md#prepared-owner-observation-state-read).

The next write boundary is native admission: preserve pending review intent,
reject stale/equal-revision conflicts, and atomically cache result, selected
projection and acknowledged owner/revision. Durable per-analysis review caching
still needs a forward model; review/public/chat/deletion/selection integrations
and the history sheet remain incomplete. All rollout flags stay false.

#### Combined enrollment and state-read verification

- Fresh disposable replay passed all 82 SQL fixtures / 753 assertions; the 36
  separate-session history races passed and schema lint reported no errors. A
  prior rerun against a database already changed by Edge test activation
  fixtures failed unrelated cutover assertions; the complete fresh replay
  resolved that test-environment contamination.
- The full Edge task passed 2,397 tests and 343 steps. Recursive type checks,
  lint, 107 isolated entrypoints/configs, dependency validation, 376 migration
  contracts and generated DTO validation passed. Independent decoder review
  identified nested AI-review byte/Unicode drift; five focused Deno state tests
  passed after adding the eight-KiB and UTF-16 regression checks.
- Native compilation and 95 focused migration/history/review/architecture tests
  passed on the iOS 26.4 simulator before the final nested-review bounds patch.
  The complete native run was also attempted: its XCTest phase ran 1,441 tests
  with six failures, and Swift Testing ran 3,244 tests with 26 issues.
  Full-suite migration and startup recovery passed. History-owned stale
  stage-count and frozen-owner assertions were fixed, and five review fixtures
  now explicitly admit their test library instead of inheriting the production
  account gate. Their focused rerun passed. Unrelated concurrent
  guest-library/auth and architecture-inventory failures remain; the full native
  gate is not green.
- Xcode generation/membership, project checks, migration guardrails and complete
  iOS tooling tests passed. Documentation and recursive Supabase formatting were
  checked. No deployment, feature activation, physical upgrade test or UI
  restore acceptance was performed.

The final nested-review patch compiled and passed all four native state tests
and 39 startup recovery/bootstrap/architecture tests on iOS 26.4. The earlier
95-test focused run and this final 43-test run both ended with `TEST SUCCEEDED`.
The shared-cache wait was resolved without interrupting the other task's build.
The disposable database was stopped with its local volume retained. The broader
native failures above remain unresolved; no rollout gate was opened.

### 2026-10-03 selected-authority admission checkpoint

The prepared native state service now atomically caches immutable evidence and
refreshes review authority/revision for the already selected result. It
preserves pending intent, rejects stale/equal conflicts, and repeats
account/deletion and cancellation fences around the transaction. Revisioned
identity clears keep their revision; legacy correction state without
acknowledgement is preserved. The existing page service supplies the shared
byte-exact insertion helper.

This checkpoint deliberately narrows the earlier planned native write slice. The
V3 saved baseline lacks full scientific/common-name and enrichment fields, so
changing selected ID while retaining the old visible projection is unsafe. A
changed selection is deferred without writes. No active schema changed: V56
selected-review fields suffice for this refresh, while a durable per-result
authority cache still needs a forward schema migration. Full projection,
enrollment, selection/Restore/Undo and history UI remain unfinished and all
rollout gates remain false. No ordinary sync caller or hosted operation was
activated.

Read-only review of the legacy reset workflow found an additional admission
hazard: its best-effort RPC can fail after a local Undo has persisted the
default review tuple, leaving no outbox or acknowledgement. The new boundary
therefore defers differing incoming review whenever both acknowledged authority
stores are absent, including the default tuple. It also defers nonzero legacy
identity revisions that existing V56 slots cannot preserve. These conservative
cases need explicit reconciliation and lossless authority storage before live
integration; neither is treated as evidence that the user left a scan untouched.

Focused simulator validation of the finalized source passed 38 tests in five
suites: selected-state admission, state decoding, immutable-page admission,
saved imports and private photos. Evidence:
`.artifacts/local-ios/47cea8161f344209923f45246807b345.xcresult`. The initial
test pass exposed nil/unreviewed comparison drift; the corrected comparison
matches the existing native defaults. Final read-only contract review found no
blocker. XcodeGen/project validation, migration guardrails, the complete iOS
CI-tooling gate, 26 documentation contracts, changed-Markdown formatting and the
recursive Supabase formatter also passed. Full native-suite results are recorded
below; focused checks alone do not prove feature activation readiness.

The subsequent full native run completed with 1,441 XCTest tests (two Settings
architecture failures) and 3,264 Swift Testing tests in 492 suites (30 issues).
All five history runtime suites passed within that run. Evidence:
`.artifacts/local-ios/de9b9348daa84fe2994aa19e84092108.xcresult`.

Two directly relevant test follow-ups were corrected: the models-ownership
assertion now permits only the prepared state service to advance observation
revision while still prohibiting selection/enrollment and live scheduling; the
legacy rejected-replacement completion fixture explicitly injects its synthetic
mutation permission rather than depending on live Auth/library state. The
broader failures also include existing Historical Sync/Auth ownership and size
checks, Field Notes mutation fixtures, and Keychain/UserDefaults inventory
expectations. Those separate workspace changes were preserved. The full native
gate is not green, and no deployment or activation is authorized by this run.

The final follow-up passed 34 tests across selected-state admission, models
integration architecture and reanalysis completion, including both corrected
fixtures/ownership expectations. Evidence:
`.artifacts/local-ios/53df1e349831474ba953437e1b0f022b.xcresult`. This does not
turn the prior full native run green; the separate workspace failures above
remain unresolved. No further native source changes followed this passing run.

### 2026-10-03 V57 authority/display cache checkpoint

The outgoing V56 graph was frozen before any active-model edits and passed both
build-for-testing and independent full-body parity review. V57 adds a separate
per-analysis state entity, with exact bounded authority bytes and its own
review/observation revision pair. A one-way result-to-state cascade extends
observation deletion; account purge includes orphan state rows. The additive
migration creates no history or cache rows and preserves the existing selected
identification, corrections and unknown completion dates. All startup routes
append the same stage and the immediate predecessor is isolated V56.

Same-selection admission now caches authority atomically with result and native
review projection, retaining all pending-intent and account/deletion fences.
Display preparation derives an explicit immutable allowlist from complete V1/V2
results and clears absent values during complete replacement. Private
observation details, review authority and another selection's species ID are
excluded. V3 imported results still lack a complete original display response;
no original provider data or completion time is fabricated. A versioned saved
baseline remains required for those results before Restore is enabled.

Normal scheduling, enrollment, explicit preview admission, changed-selection
projection and Restore/Undo remain disconnected. All rollout gates remain false.
No hosted mutation or deployment was performed.

Final focused V57 validation passed 140 tests: 39 XCTest startup/recovery tests
and 101 Swift Testing migration, history/cache, display, purge and architecture
tests. Evidence:
`.artifacts/local-ios/c019f03aabe845ea8fe977f86e117184.xcresult`. The new
projection fixture was corrected to use the canonical nested
`insight_data.ai_reasoning` field and verifies Wikipedia overview preservation.
Independent read-only review found no remaining actionable issue after explicit
null/exact-key snapshot validation and documentation/test-map corrections.
XcodeGen/project validation, migration source/adversarial guardrails, complete
iOS CI tooling, documentation contracts and formatting checks passed. These
checks do not replace the separately required physical install-over and
second-launch evidence or authorize activation.

The complete V57 unit run finished with 1,441 XCTest tests (the same two
Settings architecture failures) and 3,272 Swift Testing tests in 494 suites (25
issues). Evidence:
`.artifacts/local-ios/d09d8a1a76374af794f2c471439e3bd2.xcresult`. All migration,
analysis-record/state, history admission/decoding, saved-import and
private-photo suites passed within this full run. The eight failing Swift suites
are the previously recorded Core Data/Core-wide/Auth architecture, iOS hygiene,
Field Notes, Keychain, Species Preferences architecture and UserDefaults
inventories/fixtures. No new failing suite appeared compared with the earlier
full run; the full native gate remains red. Separate workspace changes were
preserved. No schema activation, deployment or physical-device upgrade
acceptance was performed.

### 2026-10-03 explicit preview and saved local display checkpoint

Prepared native explicit preview now admits one requested result and its own
review with all account/deletion/replay fences. It requires the response to
match the locally acknowledged observation revision and selected ID, and never
mutates parent selection, review, pending intent or revision. Newer remote state
requires selected-state refresh before preview admission.

V3 still cannot reconstruct original provider output. Selected-state admission
can now preserve a bounded, versioned `saved_local_projection` display envelope
when settled authority and all surviving V3 evidence match the unchanged local
display. This local provenance is exposed to eventual UI. The first capture
survives later enrichment; it is not synced to another device. Missing evidence
or an oversized optional envelope leaves display unavailable without inventing
history. No schema or wire version changes were needed. Independent review
identified and corrected the optional-envelope size case so it cannot block
result/authority admission.

Ordinary callers, enrollment, changed-selection projection, Restore/Undo and the
history sheet remain incomplete. All rollout gates remain false.

The final source compiled and all 47 tests across the seven focused preview,
saved-display, selected-state/cache, immutable-page, saved-import and model
ownership suites passed within the complete unit run. This includes 11 new
preview/baseline tests, both exact-limit and oversized-inner-display cases, and
preservation of pending review and private observation details. Independent
read-only review confirmed that the optional display encoding boundary cannot
roll back result/authority admission for either size case.

Full-run evidence:
`.artifacts/local-ios/e636eca00c17451ab20a14a529cef69c.xcresult`. The run
completed 1,441 XCTest tests with the same two Settings architecture failures,
plus 3,283 Swift Testing tests in 496 suites with the same 25 issues across the
eight suites recorded at the V57 checkpoint. No new failing suite appeared. The
finalized, readable result bundle reports 4,724 total tests: 4,705 passed, 12
failed and seven skipped. All tests had completed before the optional post-test
simulator diagnostic collection was stopped to let Xcode finalize the bundle.
The complete native gate remains red; separate workspace changes were preserved.
XcodeGen/project validation, complete iOS CI tooling, 26 documentation
contracts, changed-Markdown formatting and recursive Supabase formatting passed.
No deployment, activation or physical-device upgrade acceptance was performed.

Next integration work must cover acknowledged enrollment and lossless selected
projection/authority updates, durable revisioned selection and Undo, followed by
the bounded history listing and sheet. A missing device-local V3 display remains
unavailable; the implementation must not treat it as portable original evidence.

### 2026-10-03 server-selected projection admission checkpoint

Native selected-state synchronization now has a separate branch for an
acknowledged change in selected analysis. It requires a strictly newer
observation revision, complete target display and representable target review.
The previous result must retain valid evidence/display and a review cache at the
locally acknowledged revision, matching the current native authority. Missing
evidence or ambiguous legacy intent defers. Pending-review, account, deletion
and before/after display fences remain in force.

Display, target-owned review, selected ID and revision commit together with
target result/cache admission. Nested AI and identity revisions are checked
against the same analysis, so A's confirmation/rejection and higher review
revision never authorize or block B. V3 selection uses only a previously
captured baseline for that exact result. It cannot borrow the outgoing display;
all outgoing history remains intact. No schema, wire protocol, enrollment or
selection-mutation transport changed. Normal scheduling and rollout stay held.

Independent read-only review found that a structurally valid cached display with
the same analysis ID still needed evidence binding. The shared display restore
helper now rederives V1/V2 bytes or regenerates a V3 envelope against its
surviving evidence and requires canonical byte equality. Outgoing-retention
validation and imported-result cache admission both use this check. Corrupted V1
identity and V3 confidence tests exercise the boundary; closure review found no
remaining concrete issue.

Final focused simulator validation passed all 57 tests in eight suites,
including ten new selection tests. Evidence:
`.artifacts/local-ios/21d4e0b94ee94b4685ff00e9d764f745.xcresult`. The source
compiled and passed XcodeGen/project validation, 26 documentation contracts,
changed-Markdown formatting and recursive Supabase formatting. Selection
mutation, enrollment, reconciliation, normal scheduling and history UI remain
separate activation prerequisites.

The complete unit run against that same build finished with 1,441 XCTest tests
(the same two Settings architecture failures) and 3,293 Swift Testing tests in
497 suites (the same 25 issues in the eight previously failing suites). No new
failing suite appeared, and every focused history/selection suite passed again.
Full evidence: `.artifacts/local-ios/0898b08a282c49f4b6ea65c47783e730.xcresult`.
The finalized bundle reports 4,734 tests: 4,715 passed, 12 failed and seven
skipped. This run retained normal results while disabling optional verbose
simulator diagnostics with Xcode's `-collect-test-diagnostics never` option. The
full native gate remains red; no deployment or activation was performed.

Next work remains acknowledged enrollment and its missing-evidence/legacy-intent
reconciliation, durable selection/Undo requests with revision-bound receipts,
then the bounded history listing and sheet. Applying a server-selected state is
not an offline selection operation, a credit receipt, or user-facing Restore.

## Implementation checkpoint — native enrollment admission (3 October 2026)

Prepared `ObservationHistoryEnrollmentService` now uses an account-bound
protocol-9 import receipt followed by a current-state read. Only a
still-selected V3 baseline with exactly matching settled local authority and
surviving result fields can establish ownership and selection locally. Result
bytes, own review cache, saved-local display and acknowledged
owner/selection/revision commit atomically. The pre-existing identification,
confirmation/rejection and private details are preserved. Invalid receipts, lost
responses, changed selection, pending work, conflicting local edits, deletion or
account changes leave no partial local acknowledgment. Shared Swift/Deno receipt
fixture coverage was added; schema and server contracts did not change.

Independent review identified an activation blocker outside this isolated
admission path. Legacy replacement uses a different scan UUID and stores the
original only in process-local completion state. Same-ID queue checks cannot
exclude it. Enrollment therefore remains uncalled/default-off until a durable
enrollment-intent/replacement-deletion fence covers dispatch, remote success
with a lost response, restart and local acknowledgment. Protecting only an
already acknowledged local owner would leave the interrupted-request window
open. Reconciliation of divergent legacy intent/display remains separate. This
is source preparation, not completion of rollout or the user-facing Restore
flow.

Focused simulator validation passed all 40 tests in four suites, including nine
new enrollment tests. Evidence:
`.artifacts/local-ios/80db252772724b36b889804cf02567e5.xcresult`. The complete
Edge Function suite passed 2,350 tests (343 steps), with 48 database-dependent
tests ignored. Recursive function type checks, recursive function/script lint
and formatting, DTO validation, XcodeGen/project validation and 26 documentation
contracts passed. No SQL implementation changed in this slice. The full native
run initially stopped at the 20 GiB storage guard; approved managed cache
cleanup preserved dependency downloads and evidence before its rebuild.

The next protection slice should persist a bounded owner-bound enrollment intent
before the RPC, using the existing durable job store if its typed restoration
and scheduling boundaries can remain strict. The hold must survive interruption
and remain until atomic acknowledgment or explicit deletion. The central
`ScanRepository.eradicateScan` replacement-origin path must consult that hold,
covering ordinary and delayed rejection-carry completion even when the
replacement has another UUID. Automatic non-biological cleanup must
exclude/recheck held observations; historical hydration must preserve their
saved identification. Explicit deletion must remove the hold and observation
atomically while retaining normal cloud deletion intent, and account purge must
erase it. Acceptance must cover restart, owner mismatch, malformed intent, no
autonomous dispatch, delayed replacement, explicit deletion, expiry, hydration
and save rollback. These are remaining implementation requirements, not
guarantees of this checkpoint.

The complete Supabase tooling run passed its TypeScript/evaluation/DTO stages,
then stopped in the synthetic Gemini launcher's terminal-entry test under the
sandbox. Rerunning that test with terminal access passed all five synthetic PTY
scenarios; every remaining discovered shell test also passed. No live provider
calls or credentials were used. This was a staged recovery of the tooling gate,
not an uninterrupted green `make test-supabase-tooling` invocation.

The full native rebuild/run completed with 1,441 XCTest tests (the same two
Settings assertions) and 3,302 Swift Testing tests in 498 suites (the same 25
issues in eight suites). Comparing recorded issue signatures with the preceding
selection slice found zero additions or removals; all history/enrollment suites
passed. Final evidence:
`.artifacts/local-ios/7c6a6dfcdbc044f3a97517985c9f330f.xcresult`, with 4,743
tests: 4,724 passed, 12 failed and seven skipped. The complete native gate
therefore remains red for the pre-existing failures. No deployment, activation
or ordinary enrollment scheduling was performed.

## Implementation checkpoint — durable enrollment protection (3 October 2026)

Prepared enrollment now commits a bounded owner/observation/nonce intent before
the RPC using the existing `.future` job store. It survives ambiguous outcomes
and restart without automatic dispatch; exact receipt acknowledgment removes it
in the same save as history/selection. Failed staging cannot dispatch; failed
admission keeps the hold. No schema or server contract changed.

A shared transaction and fresh reads now fence central replacement deletion,
automatic expiry and historical/point hydration. Acknowledged history stays
protected after intent removal, including stale callbacks from a replacement
with a different UUID. Expiry pages past held records; active intents remain in
pending-library-mutation inventory and all namespace rows are excluded from
scheduler deadlines.

Review also identified a late historical-page resurrection path after explicit
deletion. For held or acknowledged observations, explicit erasure now retains a
terminal, metadata-free local identity fence after removing the scan/history and
enqueuing cloud deletion. This marker survives cloud receipt cleanup, cannot be
reopened for enrollment, and is erased by account purge. Historical pages also
skip every pending cloud deletion. This supersedes the previous checkpoint's
proposal to remove all enrollment intent on explicit erasure. Normal legacy
scans without history protection keep their existing deletion behavior.

Independent read-only review found no remaining stale-deletion or nested-lock
bypass in these boundaries. Ordinary enrollment scheduling, divergent-state
reconciliation, revision-bound selection/Undo, presentation and all backend
activation prerequisites remain outstanding; no deployment is authorized.

Validation includes 13 new native cases across durable-intent and protection
suites. They cover disk-backed restart/replay, failed staging and acknowledgment
saves, malformed/foreign/terminal intents, nonce replacement, scheduler
exclusion, stale replacement callbacks, explicit deletion during enrollment,
expiry paging, post-deletion historical replay and enrichment preservation. Both
new suites and all existing history suites passed in the complete native run.
XcodeGen and project validation, 26 documentation contracts, changed-Markdown
formatting and the recursive function/script formatting candidate gate passed.
No SQL, DTO or Deno runtime implementation changed in this slice.

The complete native run finished with 4,756 tests: 4,737 passed, 12 failed and
seven skipped. Evidence:
`.artifacts/local-ios/5b91ad19e2cf4190a45780458aee2f61.xcresult`. The 3,315
Swift Testing cases in 500 suites recorded the same 25 issues as the preceding
checkpoint; XCTest recorded the same two Settings assertions. Comparing both
sets of recorded failure signatures, including duplicate occurrences, found no
additions or removals. The complete native gate remains red for those existing
failures. The isolated build reused downloaded dependencies, retained this
result bundle and removed temporary build data on completion.

Next is durable revision-bound selection and Undo admission, followed by bounded
history listing and presentation. Live enrollment still requires explicit
reconciliation of divergent legacy state and the documented activation
prerequisites; this protection slice does not enable it.

## Implementation checkpoint — prepared native selection requests (3 October 2026)

The native selection owner now durably prepares exact operation/revision-bound
requests in the existing job store without changing visible identification.
Restore requires a current target preview and retained prior evidence/display;
Undo requires the latest receipt to match the still-current parent revision and
selection. Both use each result's own authority. Exact replay survives ambiguous
responses; receipt validation is followed by a current-state read, and the
receipt plus projection/authority commit atomically. A newer server state wins
over an older receipt and disables that receipt's Undo. Pending intent blocks
ordinary state sync, malformed rows fail closed, and explicit deletion erases
selection payloads under the existing terminal fence. No schema migration was
needed.

Independent read-only review found no blocking issue in the prepared native
path. The private server transaction is still not publicly exposed, and native
`cloud.select` defaults to unavailable. No ordinary worker or UI caller was
connected, and all activation holds remain. Definitive conflict reconciliation,
authenticated public mutation transport, public/credit integrations and the
history sheet are still required. This checkpoint prepares a native request and
receipt boundary; it is not a shipped Restore feature.

Initial focused native validation passed 49 tests in five suites, including the
first 11 new selection cases. Evidence:
`.artifacts/local-ios/f4dc947bc3184799a868e32cf92ebaf9.xcresult`. Four further
cases cover newer authority on the same target, deletion of a completed receipt,
invalid receipts/failed or stale state reads, and a foreign stored owner. The
complete native gate includes those additional cases. The Edge Function suite
passed 2,351 tests (343 steps), with 48 database-dependent tests ignored.
Recursive function type checks, function/script lint and formatting, DTO
validation, XcodeGen/project validation and 26 documentation contracts passed.

A subsequent local review tightened Undo admission to require the caller’s exact
receipt operation ID as well as current selection/revision. An old Undo control
cannot silently target a newer completed operation. The A → B → A acceptance
case also rejects that older operation ID after the newer receipt commits.

The tooling gate passed its TypeScript, evaluation and DTO stages, then stopped
at the synthetic Gemini terminal-entry test under the sandbox. That test passed
all five scenarios with terminal access, and all nine remaining shell test files
passed. No live provider calls were made. This is staged tooling recovery, not
an uninterrupted green `make test-supabase-tooling` invocation. The first full
native attempt compiled the earlier Undo signature before its final tightening;
test compilation detected the mismatch. Its result is not final validation. A
clean isolated full run validates the final signature and all 15 new cases.

Final native evidence:
`.artifacts/local-ios/018d3ba0fd7947aa9d11c8941643ab2f.xcresult`. The clean
complete run finished with 4,771 tests: 4,752 passed, 12 failed and seven
skipped. All 15 new selection cases and every history suite passed. The 3,330
Swift Testing cases in 501 suites recorded the same 25 issues as the preceding
checkpoint, and XCTest recorded the same two Settings assertions. Comparing
failure signatures and their multiplicities found zero additions or removals.
The complete native gate remains red for those existing failures. Isolated build
data was cleaned while this result bundle and dependency downloads were
retained.

Next is the authenticated public selection boundary and definitive-conflict
reconciliation for durable pending requests. After those boundaries are proven,
connect bounded history listing, preview and Restore/Undo presentation. Neither
source preparation nor these passing focused cases authorize feature activation
or deployment.

## Implementation checkpoint — owner selection and durable conflict recovery (3 October 2026)

Protocol 9 now prepares `select_owned_observation_analysis`, an authenticated
owner wrapper with a default-false `selection_api_enabled` gate. The wrapper
holds owner, observation advisory and owned-live-scan locks before entering the
private transaction. Only its explicit revision-conflict exception becomes a
terminal rejection in the existing immutable operation ledger. The outer locks
survive the nested rollback, so deletion and duplicate operations cannot race
the rejection commit. Success and rejection share one operation key and full
request identity. Rejection neither advances observation state nor creates
reconciliation work. Missing targets, closed gates and ambiguous failures remain
errors.

Independent review caught an initial ordering issue: the new API gate would have
prevented recovery after it closed. Exact saved outcomes now replay before all
admission gates, after owner and deletion checks. Changed input under the same
operation still fails. Gate closure stops fresh selections; current-state reader
gates still apply, so native acknowledgment waits if state reads are
unavailable.

The native live adapter invokes this RPC. Strict shared request/rejection
fixtures bind every field; the terminal proof is never treated as authority.
After success or rejection, native admission fetches current selected state and
commits it with the outcome in one save. Rejection uses a version-2 cancelled
intent envelope in the existing job store; version-1 pending/success rows remain
readable. Failed reads or saves preserve the exact pending operation for replay.
A rejected operation cannot enable Undo, and a fresh target preview is required
before another selection. No schema version, ordinary worker or UI caller was
added. All rollout gates remain closed; no deployment or activation occurred.

New regression coverage includes owner/protocol/grant checks, missing targets,
immutable exact outcome replay after authority changes and gate closure,
delete-before-replay and cascade, plus independent-session duplicate, competing
operation, review and deletion races. Native cases cover strict rejection
parsing, atomic rejection/current-state admission, interrupted admission/retry,
stale reads, malformed cancellation and fresh-preview replacement. The first
native attempt found two missing `try` annotations in those new tests; both were
corrected before the final complete run.

Remaining work is bounded history presentation with preview and explicit
Restore/Undo, ordinary sync integration, legacy divergence handling, and the
existing review/community, public/credit, privacy and activation prerequisites.
This checkpoint prepares recovery-safe owner selection; it is not a shipped
history menu.

Backend validation passed 2,407 tests (343 steps), including all configured
local database-dependent cases. The strengthened distinct-target race test then
passed all six scenarios. Two complete disposable database replays passed all
774 pgTAP assertions across 83 files, including privilege catalogs; schema lint
reported no errors. Security/performance advisors reported 103/79 warnings and
no errors under the repository's advisory policy. The disposable database was
stopped and removed after validation. Recursive function type checking,
function/script lint and candidate formatting, executable DTO validation,
project-resource validation, 26 documentation contracts and formatting of all 63
changed Markdown files passed. These results are local evidence only.

The complete tooling gate passed without staged recovery: 499 standard tests,
157 evaluation tests, 20/21 isolated DTO tests and all 19 shell test files.
These used synthetic provider executables; no live inference calls were made.

Final native evidence:
`.artifacts/local-ios/585795b5c9be4a3cae9c2d38a2284e84.xcresult`. The complete
run finished with 4,775 tests: 4,756 passed, 12 failed and seven skipped. All 19
selection-intent cases and all 12 history suites passed. The 3,334 Swift Testing
cases in 501 suites recorded the same 25 issues as the preceding checkpoint;
XCTest recorded the same two Settings assertions. Comparing failure signatures
and their multiplicities against the prior complete run found no additions or
removals. The full native gate therefore remains red for existing failures. The
isolated wrapper retained the result bundle and removed temporary build data.

### October 3, 2026 — prepared bounded native history interface

The next native slice adds `ObservationHistoryListingService` and
`Features/Insights/History`. The existing page decoder/receipt retains server
revision and ordered result IDs without changing the wire format. Availability
uses a two-child limit, and listing admits one server-ordered 20-result window
with exact local child reads. It never loads the cascade relationship, sorts by
unknown completion dates, or equates a partial cache with all history. A newer
page can retain immutable evidence but cannot claim current review authority.

Shell admits the sheet through its existing typed modal slot and scan
generation. Rows show their own identity, confidence and review, plus the
selected marker. Tap opens a read-only preview; Use this identification stages
and sends the existing conditional operation. Ambiguous outcomes retain pending
intent for explicit Retry; terminal conflicts refresh current state and require
a fresh preview. A matching current receipt permits Undo for 15 seconds.
Account, deletion, cancellation and receipt/revision fences remain in Core. Only
admitted selection or authority changes reload the parent Insight; paging and
preview do not reset it. Closing releases private rows/details/photo while
durable pending intent survives. The sheet retains only account/session values;
Core operations own their own short-lived work leases.

Private evidence uses the existing verified resolver and one downsampled image.
The view model rejects late or superseded image requests. Independent review
identified idle account/SwiftData polling and unnecessary parent reloads; the
revised implementation observes account/presentation invalidation, library
change events and foreground return, uses one Undo deadline, and reloads only
when acknowledged state changes. Follow-up review found that a sheet-lifetime
work lease could stall Auth draining while backgrounded. That lease was removed:
the UI retains identity and the read-only Auth generation, and operation-scoped
leases remain in Core. An injected runtime test checks zero idle leases, drain
completion, transition denial and same-account generation invalidation.

Normal `historyAccess` remains nil. The prepared service factory has no ordinary
call site. An explicit Debug UI-test fixture alone supplies synthetic domain
values to the real menu, sheet and state machine. The runtime audit manifest and
Release binary fixture-exclusion list include the new fixture. No schema, server
payload, gate, deployment or ordinary reanalysis behavior changed. Reopening or
paging needs the server index; cached fallback is limited to an already-loaded,
validated preview. A complete offline index is not implemented.

Canonical documentation now records product behavior, local ownership, protocol
consumer status, offline limits, modal routing, tests and the unchanged
activation hold. Ordinary enrollment/history scheduling, legacy divergence
handling, review/community writers, public/credit authority, privacy/deletion
integration and the remaining activation matrix still precede rollout. This
checkpoint does not recover identifications already erased by replacement
reanalysis.

The complete native run on the final production source retained evidence at
`.artifacts/local-ios/8980f2679e6a4b3e8555c92a2db2610b.xcresult`. All 14 history
suites passed. Swift Testing ran 3,347 cases in 503 suites and reported the same
25 issues as the preceding checkpoint; XCTest reported the same two Settings
assertions. Comparing unit failure signatures and their multiplicities found no
additions or removals. The complete native unit gate therefore remains red for
the same 12 existing failing tests.

That combined run also included the new history UI test and finished with 4,789
tests: 4,769 passed, 13 failed and seven skipped. Its additional failure
occurred before opening history: the test opened the scan's actions while
Insight still showed its scanning placeholder. A first test-only correction
assumed the seed's Scans route would always present, but a focused rerun
remained at the root screen
(`.artifacts/local-ios/625aba6f1bbb4e018096f7dadfe39c0c.xcresult`). The test now
accepts an already-presented Scans route or enters through the visible root tab,
then waits for the saved identification to bind before opening its menu.
Restore, Current-marker, Undo and retained-entry assertions remain intact. These
corrections change only the UI test, not production source.

Project generation/resource checks, event-routing checks and their regression
tests, the complete iOS CI tooling gate, executable DTO validation, all 26
documentation contracts, function/script candidate formatting, and formatting of
all 68 changed Markdown files passed. This native presentation slice does not
change SQL or backend implementation, so it does not repeat the preceding
checkpoint's disposable-database suite. Simulator fixtures do not establish live
backend, cross-device, physical-device or production-rollout evidence.

The final focused simulator rerun passed
`IdentificationHistoryUITests/testHistoryPreviewRestoreAndUndoKeepBothEntries`
with zero failures. Its retained result bundle is
`.artifacts/local-ios/839be106943647259999f5065fa56bde.xcresult`; the attached
"Identification history after Undo" screenshot was visually inspected. The flow
checks preview, restore to the second entry, Undo to the first, both Current
markers, retained entries and dismissal. Production source was unchanged after
the complete unit run above. The wrapper preserved test evidence and removed
each isolated run's temporary build data. Normal access remains disabled and no
deployment occurred.

### October 3, 2026 — accumulated implementation review

The review covered the prepared backend history, enrollment, funding, recovery,
selection and private-evidence boundaries; V54–V57 migration and native
persistence; and the new native menu, presentation, retry and account lifecycle.
Independent read-only reviews checked backend integrity, cross-surface contracts
and native presentation. The primary agent owned all edits and preserved the
other work already present in this checkout.

Four actionable defects were corrected:

- Acknowledged revision changes could leave prior community titles, confirmation
  labels and restore controls visible. The model now invalidates rows, preview,
  photo and pagination, and rejects a delayed page or preview whose context no
  longer matches. Restore/Undo reloads the newest bounded page after
  acknowledgment. Failure of that read preserves the acknowledged choice and
  eligible receipt; it cannot turn success back into pending work.
- A valid imported saved result could contain opaque legacy candidates such as
  `{}`. Decoding those optional alternatives as the current array schema threw
  and prevented the entire preview. Incompatible alternatives are now omitted
  without discarding the saved identification or disabling an otherwise valid
  restore.
- The preview's toolbar Back control could abandon a tracked selection task
  while the underlying request was still unwinding. Both the view and model now
  reject Back while busy. Done remains explicit dismissal, with durable intent
  preserved by Core.
- Immutable admission conflicts were being sanitized into a transient 503,
  inviting repeated submission of conflicting input. The worker adapter now
  preserves only admission's `analysis_history_operation_conflict`, and the HTTP
  handler returns 409 with recovery guidance. Later worker-claim conflicts
  remain recoverable 503 failures. A mocked RPC-to-HTTP regression covers both
  paths without provider execution.

Seven native regressions cover invalidation, delayed responses, busy Back,
post-acknowledgment read failure, opaque candidates and observation of an Auth
transition before the published user changes. Follow-up review accepted the
fixes. The suspected Auth visibility gap was not reproduced: `AuthRuntimeState`
is already observable, and its nested transition read is now covered explicitly.
No confirmed migration, stored-selection, owner-read, private-photo or deletion
fence defect emerged from this review. The existing feature/Core ownership split
was retained; no speculative file moves, new persistence schema or SQL migration
were introduced. The reviewed native history Core/feature inventory contains 25
Swift files and 2,571 lines; the largest owner is the 231-line explicit display
snapshot codec. The fixes add no production files or new ownership layers.

Readiness remains bounded by the documented activation matrix. Ordinary
enrollment/sync, legacy reconciliation, review/community writers, public/credit
authority, immutable chat admission and scientific allowlist materialization are
still integration work, not claims established by the Debug UI flow. An explicit
aggregate request-byte guard for the owner page/state RPCs is an additional
pre-activation hardening opportunity; current exact-shape and field validation
already constrain accepted requests. The review did not find a concrete account
operation affected merely by equality between an owner UUID and an analysis UUID
in their separate namespaces, so it did not change the identity contract on that
basis. Private history already cascades away on account detachment through
`clear_detached_observation_history`; allowlisted scientific projection before
that removal remains required.

Backend validation passed 2,354 tests (343 steps), with 54 database-dependent
cases ignored because no disposable database was configured for this review. SQL
was unchanged; the earlier disposable-database evidence is not presented as a
new run. All 107 deployable entry points type-checked using their local frozen
configs. Function dependency/config checks, lint, candidate formatting, DTO
validation, 26 documentation contracts and native project/resource checks
passed. The complete Supabase tooling gate passed 499 standard tests, 157
evaluation tests, 20/21 isolated DTO tests and all 19 shell test files. Its
first run stopped at a sandbox-restricted synthetic terminal-input case; that
case and then the whole gate passed with terminal access. These tests used
synthetic provider executables and made no live inference calls.

The complete native unit target plus history UI flow retained evidence at
`.artifacts/local-ios/7888926b359f46389731ced456c006a3.xcresult`: 4,796 tests,
4,777 passed, 12 failed and seven skipped. All 14 history suites and the
simulator preview/restore/Undo flow passed; the final screenshot was visually
inspected. Swift Testing ran 3,354 cases in 503 suites with the same 25 issues,
and XCTest retained the same two Settings assertions. Failure-signature multiset
comparison against the preceding complete run found no additions or removals.
The remaining failing tests concern existing architecture/inventory contracts,
field-note state and Settings dependency ownership. This review does not mark
those failures resolved: the complete native gate remains red. Temporary build
data was removed while the result bundle was retained. Normal feature access and
server gates remain closed; nothing was deployed.

### October 3, 2026 — accumulated test-candidate preparation

Candidate preparation addresses the previously red native checks while retaining
all history activation holds. Field-note tests now use the existing injected
repository boundary with explicit synthetic mutation authority. Production
account checks remain unchanged. Registry tests include the new library-owner,
sign-out journal and acknowledged-name keys. Settings pending-library views use
`LibraryTransitionPresentationDependencies` for routing, retries and observable
restoration reads instead of resolving those live services themselves.

Historical collection restoration now has a synchronous persistence helper under
its existing ModelActor; actor rollback and context isolation are preserved.
`ScanLibraryPurgeService` owns the existing ordered model/preference/runtime
cleanup beneath the repository's derived-state reset. The model-inventory test
follows that owner. Restoration tests are separate from media tests. The
600-line production ceilings and oversized-owner inventory are unchanged. The
reviewed Auth feature budget includes the new account-isolation and durable
sign-out work; the existing manager exception remains because its private
transition state and live dependency composition are coupled.

The next history integration must use analysis-bound review requests. Current
selection changes the internal active projection without changing the legacy
`public.scans` evidence. A generic trigger copying legacy scan review into the
selected child would therefore transfer result A's authority to B after A → B.
Do not use such a bridge. First reject unbound legacy review/community creation
for enrolled observations, then admit revisioned reviews against the named
child's immutable evidence, with exact replay and deletion/account fencing.
Ordinary enrollment and native review scheduling remain downstream of that
contract. This is a design finding, not an implemented review endpoint.

Follow-up (3 October 2026): The held Reject/Undo RPC and legacy review fencing
now implement the first portion of this finding. The
[prepared rejection contract](../backend-and-data/05-api-contracts.md#prepared-analysis-bound-reject-and-undo)
owns current behavior. Analysis-bound confirmation, community authority and
native review admission remain outstanding; the original candidate evidence
above predates this slice.

The accumulated work is prepared on a separate candidate branch. A push to
`main` would invoke the production deployment workflow; a draft pull request is
the validation destination. Local and CI evidence, deployment and TestFlight
availability remain separate states.

After merging the latest Gemini routing preparation, the protected-photo SQL
fixtures now assert the configured Gemini preflight. A stale OpenAI preflight is
rejected before a complimentary hold is reserved. The fresh disposable migration
replay and all database catalogs passed 777 assertions across 84 files. The
complete backend suite passed 2,409 tests, including the database concurrency
cases. Database lint passed; security and performance advisors reported 103 and
79 warnings respectively, with no errors under the existing warning policy. The
disposable database was removed afterward. All 107 function entry points,
dependency/config checks, lint, DTO checks, 26 documentation contracts and both
complete tooling gates passed.

The complete native unit target passed: the retained combined result at
`.artifacts/local-ios/832d3f026f084bc0b0fcb605f72e9926.xcresult` records 4,788
passing tests, seven skipped and one failed UI test. Swift Testing completed
3,354 tests in 503 suites without issues. The remaining UI failure occurs before
history opens: tapping the root Scans entry does not present the library. The
same failure reproduced in an isolated UI run at
`.artifacts/local-ios/a903bd493c5b40bcbc64e97a8afa58a8.xcresult`. This evidence
resolves the earlier 12 unit failures but does not establish a green history UI
gate for this candidate.

The first draft-PR checks caught whitespace-only drift in the V54–V56 frozen
scan snapshots introduced during candidate cleanup. Their original bytes were
restored and verified against the existing pinned SHA-256 values; the digest
checks were not changed. `make validate-ios-migration-guardrails` now passes.
Those frozen files intentionally retain their pinned whitespace.

UI diagnosis also found two sources of cross-test state: the SDK's persistent
Auth store and ownership markers in the app's shared Keychain test shim. Debug
test SDK clients now use per-client synchronized memory storage, and each UI
scenario receives its own test-Keychain namespace that survives relaunching the
same `XCUIApplication`. Normal app and Release Keychain behavior remains
unchanged. The new storage regression passed. The final complete native run
passed on the corrected candidate: 4,790 passed, zero failed and seven skipped
out of 4,797 tests. Swift Testing completed 3,355 tests in 503 suites without
issues. The history UI smoke exercised preview, Restore and Undo; its retained
screenshot confirms both entries remain and the first is Current again. Evidence
is retained at `.artifacts/local-ios/81a78db70f904f4bbc939c80bf7a019e.xcresult`.

The accumulated source is pushed in draft PR #115 on
`codex/accumulated-test-candidate`. At source revision `4a0d43d64`, CI's
Supabase Candidate Validation, iOS Project Guardrails, Markdown, Agent and Admin
quality workflows passed; compiled iOS and Startup Safety were still running
when this local evidence was recorded. The full local iOS tooling gate,
migration source guardrails, project validation and 26 documentation contracts
passed again. CI evidence must be checked against the final PR head before
release. History activation remains closed, and no deployment or TestFlight
upload was performed.

### October 4, 2026 — analysis-bound review and private community preparation

The held review implementation now includes durable confirmation admission and
exact completed retry recovery, in addition to Reject/Undo. Confirmation targets
one immutable result and rechecks both observation and child-review revisions
after verification. The
[current confirmation contract](../backend-and-data/05-api-contracts.md#prepared-analysis-bound-confirmation)
owns its default-off gate and native integration requirements. All seven PR
workflows, including compiled iOS and Startup Safety, passed for the preceding
confirmation candidate `0f02d01ed3a2cd7d2ba3b91bbacf1c7a1c8c98f0`.

The next database-only foundation binds a freshly inserted community request to
an explicit result, preserves that immutable binding, and queues revisioned
authority reconciliation. The worker reads current committed consensus, yields
on lock contention, and cannot override a subsequent owner review. Request
deletion retains revocation work; observation/account deletion erases the
private binding and queue. There is no public RPC, endpoint, publisher or
scheduler in this slice. The
[current community contract](../backend-and-data/05-api-contracts.md#private-analysis-bound-community-authority-preparation)
defines these boundaries. Legacy enrolled request creation remains fenced.

Focused verification passed 26 SQL assertions and eight concurrency tests. The
complete backend suite passed 2,450 tests with 343 steps. Clean disposable
migration replay and all database catalogs passed 870 assertions across 87
files. Database lint passed; advisors reported the existing 103 security and 79
performance warnings, no errors, and no findings on the new community objects.
All 108 function entry points type-checked. Migration, DTO, lint and formatting
checks passed. The complete Supabase tooling gate passed 499 standard tests, 157
evaluation tests, 20/21 isolated DTO tests and all 19 shell test files. Its
provider/terminal cases used local synthetic executables, with no live inference
calls. This backend slice changes no native source and does not replace the
earlier native evidence or establish CI results for its eventual commit.

The next integration must create an immutable approved public snapshot with
atomic analysis-bound admission. Public reads must immediately remove verified
identity and species eligibility when the published result loses authority,
independently of private selection and worker delivery order. A durable retry
owner, native review admission, remaining downstream consumers and final account
deletion integration still precede activation. No deployment, activation or
TestFlight upload was performed.

### October 4, 2026 — prepared immutable public publication reads

The next held slice adds private publication registration and immutable approved
media/original-label records for an explicitly bound result. A sanitized public
projection supplies Explore identity without exposing private history IDs or
payloads. Source/review changes invalidate it transactionally; only current
reconciliation can republish authority. Private A → B → A selection and replay
of an old publication receipt do not change the shared identification.

Cards, detail, species search/filtering, public web, community detail and
notification labels now use this boundary. Otherwise-visible posts and community
discussion remain unresolved after revocation. Private scan images, candidates,
reasoning and inference metadata do not become a publication fallback. Approved
media remains frozen while health checks and unsharing work. Registration
retires the post's derived reference cache and compatibility URLs; serialized
refresh cannot reintroduce that bound source. Account deletion prelocks bound
request/public rows without waiting before detachment.

The
[current publication contract](../backend-and-data/05-api-contracts.md#prepared-analysis-publication-snapshots-and-public-reads)
owns implemented behavior and limitations. Registration has no API grant, its
gate defaults false, and no endpoint/client or scheduler is activated. The
moderated atomic publisher, explicit shared-identification updates, native
admission and remaining downstream/account integration are still required.

Verification passed 51 focused SQL assertions and six publication concurrency
tests. Clean disposable migration replay and all catalogs passed 921 assertions
across 88 files. The complete backend suite passed 2,457 tests with 343 steps;
all 108 function entry points type-checked. Database lint passed, and advisors
retained 103 security and 79 performance warnings with no errors or new
publication-object findings. The complete Supabase tooling gate passed 499
standard tests, 157 evaluation tests, 20/21 isolated DTO tests and all 19 shell
test files. Migration, DTO, lint and formatting checks passed.

For the preceding community commit `ea6541de0`, hosted compilation, the complete
unit target, Release archive and Startup Safety passed. The critical scan UI
lane failed its queued-audio handoff case because Boost did not expose a
playable source before the assertion. That failure remains under investigation;
neither these backend checks nor earlier native evidence establish a green
candidate. This slice changes no native source and performs no deployment,
activation or TestFlight upload.

### October 4, 2026: private community admission transaction

The next preparation adds atomic fresh-request admission with immutable retry
intent, a consumed same-transaction insertion fence, and frozen approved public
evidence. It refuses reuse of existing discussions and suppresses private scan
fields in pending community detail. This remains an internal default-off
boundary without an API grant or moderated/native caller. See the
[current admission contract](../backend-and-data/05-api-contracts.md#prepared-atomic-community-request-admission)
for the authoritative implementation and remaining integration.

### October 4, 2026: protected publisher intent foundation

A private default-off preparation now freezes the operation, requested revisions
and exact V2 photo content/ownership facts before external work. Historical
retry and current revalidation are explicitly separate. This records no
moderation approval and creates no public media, provider reservation or post.
Completed analysis safety/funding is insufficient publication proof; durable
moderation attestations and deletion-safe public-copy ownership remain required.
The
[current intent contract](../backend-and-data/05-api-contracts.md#prepared-protected-photo-publication-intent)
owns the implemented boundary and activation limits.

### October 4, 2026: private photo moderation attempts

The prepared lifecycle now gives each exact V2 photo an immutable policy-bound
job and separate provider attempts. It records one-time dispatch permits,
explicit retry predecessors and terminal decisions while preserving uncertain
provider charges. No complimentary scan credit is consumed. Both the gate and
new quota policies are disabled; no classifier, public-copy owner or endpoint is
activated. The
[current attempt contract](../backend-and-data/05-api-contracts.md#prepared-photo-moderation-attempt-lifecycle)
defines the remaining byte/policy validation and publication boundaries.

### October 4, 2026: prepared private-photo classifier adapter

The concrete classifier now prepares an immutable, source-verified inline
request and strict bounded decision/usage output. Its single HTTP invocation
cannot retry implicitly or expose provider errors. Tests use synthetic bytes and
injected transports. It has no production caller: durable proof persistence, SQL
dispatch binding and output recovery remain required before the deletion-safe
public-copy and authenticated publisher slices. No live policy qualification or
rollout is claimed. See the
[classifier contract](../backend-and-data/05-api-contracts.md#prepared-source-bound-photo-classifier-adapter).

### October 4, 2026: durable private-photo execution binding

The prepared owner now records the exact adapter proof before dispatch and
commits bounded classifier facts/usage with the decision. SQL independently
validates approval semantics and exact replay; deletion and changed authority
roll back incomplete output. The owner never retries a provider invocation.
Dispatched-work recovery uses authoritative expiry retirement, but a claiming
worker/scheduler and live repository adapter are still required. Public copying,
authenticated publication and native delivery remain held. See the
[execution contract](../backend-and-data/05-api-contracts.md#prepared-durable-photo-execution-binding).

### October 4, 2026: prepared public-photo transport and metadata boundary

A dedicated unconnected transport now prepares exact-byte conditional public
copies and permanent origin erasure markers. Bounded JPEG/PNG filtering rejects
known out-of-band metadata; HEIC and unsupported containers remain held. A
future publisher must preflight before quota admission, and any derivative needs
its own immutable source and moderation. Durable copy allocation, cleanup,
publication invalidation and cache-bypass evidence remain required. No
activation is implied; see the
[storage contract](../backend-and-data/05-api-contracts.md#prepared-public-photo-storage-boundary).

### October 4, 2026: public-photo staging ledger

Private SQL staging now reserves a permanent opaque cleanup registry entry
before external I/O and one immutable source/lease receipt per approved attempt.
Fresh authority checks protect allocation and completion; abandonment, fixed
expiry and parent deletion preserve detached cleanup obligations. Ready copies
remain unbound and expire at their original deadline. No public availability,
worker or endpoint is activated; atomic publication binding and immediate
post-write failure cleanup remain next. See the
[staging contract](../backend-and-data/05-api-contracts.md#prepared-public-photo-staging-lifecycle).

### October 4, 2026: atomic approved-photo cohort binding

A forward preparation now binds every approved ready photo to fresh community
admission in one transaction, preserving ordering and immutable replay evidence.
Unshare/moderation/deletion revoke copies; ordinary health quarantine remains
reversible to preserve the existing recovery contract. No rollout or live writer
is enabled. Current behavior is defined in the
[API contract](../backend-and-data/05-api-contracts.md#prepared-atomic-public-photo-binding).

### October 4, 2026: public-photo erasure execution owner

A prepared service-authenticated worker now connects due registry claims to
verified permanent origin markers and fenced acknowledgement, independently of
surviving account/history rows. Targeted claims support the future failed-copy
owner without authorizing erasure of a valid publication. The separate external
cleanup gate defaults false, with no cron schedule. Main-branch deployment
planning still includes the configured route and requires separate
authorization; cache-bypass qualification remains open. See the
[worker contract](../backend-and-data/05-api-contracts.md#prepared-public-photo-erasure-worker).

### October 4, 2026: scoped public-photo copy execution

The prepared one-source executor now validates durable reservation identity,
verifies exact private bytes, writes conditionally and retries only the
identical completion. Failure uses the shared targeted erasure owner even if
deletion removed private receipts; SQL claims prevent erasing another worker's
valid publication. Operation admission, live repository integration, cohort-wide
failure recovery and native delivery remain held. See the
[copy execution contract](../backend-and-data/05-api-contracts.md#prepared-public-photo-copy-execution).

### October 4, 2026: authenticated durable publication intake

The prepared endpoint now freezes exact ordered photo consent and persists an
immutable owner-bound acceptance before external work. Replay retains the first
quota-address hash, bypasses closed intake gates/bounds, and still checks
deletion and exact request equality. Acceptance is distinct from publication.
Execution claims/status, preflight, moderation/copy repositories, cohort failure
cleanup, expired-attempt recovery and native delivery remain separate held
slices. See the
[intake contract](../backend-and-data/05-api-contracts.md#prepared-authenticated-publication-operation-intake).

### October 4, 2026: durable publication orchestration ownership

Separate private work records now preserve immutable intake while supplying
bounded discovery, exact expiring tokens and release backoff. Owner status
distinguishes awaiting recovery, active orchestration and historical cohort
admission without claiming public visibility or provider success. Deletion and
binding retire work transactionally; the independent execution gate stays false.
No worker endpoint or native consumer is connected. Review also confirmed that
optional notes need their own moderation boundary before live publication; photo
approval is insufficient. Remaining work includes scoped execution, preflight
before quota, note moderation, cohort failure cleanup, expired-attempt
retirement and native delivery. See the
[worker contract](../backend-and-data/05-api-contracts.md#prepared-publication-operation-worker-ownership).

### October 4, 2026: scoped moderation recovery and cohort preflight

Accepted operations now have an explicit service repository for ordered attempt
recovery, initial admission, proof, one-time dispatch, identical completion and
retirement. Existing attempts never become automatic successors. Late provider
completion retains its own lease after orchestration expires; terminal outcomes
are consumed without an execution token. A full-cohort preflight owner verifies
private bytes and the stricter JPEG/PNG metadata-container policy before a
future worker may reserve quota. Classifier signature checks alone are
insufficient. No execution route or scheduler is connected. Copy integration,
note moderation, cohort cleanup, retirement scheduling and native delivery
remain held. See the
[repository contract](../backend-and-data/05-api-contracts.md#prepared-scoped-publication-moderation-repository).

## October 4 addendum: durable photo moderation outcomes

The prepared SQL phase now persists historical `photos_approved` or bounded
`needs_action` outcomes, retires moderation work atomically and fences later
attempts. Partial refusal avoids unnecessary remaining provider spend; active
attempts must settle first. Selection, provider funding, public visibility and
notes remain separate. Worker/copy/native integration and activation are still
pending.

See the
[outcome contract](../backend-and-data/05-api-contracts.md#prepared-durable-photo-moderation-outcomes).

## October 4: prepared bounded photo moderation worker

`moderate-publication-photos` now connects service authentication, durable
claims, recovery, finalization and one verified provider execution. Gates stay
false and no scheduler is added. Shared request/provider deadlines preserve
completion time and never turn uncertainty into a retry or refund. Copy/binding,
exact-note moderation and native operations remain separate. Worker
handler/repository and classifier deadline tests cover recovery-first ordering,
preflight before quota, lost dispatch/completion, stalled response cancellation
and scoped denial.

## October 4, 2026: separate copy recovery stage

A prepared migration now creates durable copy work after settled photo approval,
with exact ordered causal-leaf context and a separate service-only lease.
Refused outcomes never enter the stage; binding or deletion retires it. This
completes recovery ownership, not storage execution. Atomic cohort reservation,
fixed shared expiry, copy/binding integration, targeted cleanup and public-note
approval remain next. All activation gates stay false.

## October 4, 2026: atomic copy cohort reservation

Prepared service RPCs now reserve the complete settled photo cohort atomically
under one immutable ten-minute expiry, with a separate closed activation gate.
Scoped completion repeats current authority; historical publication recovery
precedes cleanup and abandonment queues every unbound sibling. This path
explicitly refuses nonnull public notes until separate note moderation exists.
Storage execution and live binding remain unconnected; rollout stays disabled.

## October 4, 2026: scoped copy repository

The prepared TypeScript repository now supplies exact-operation reservation,
completion and cohort cleanup targets to a dedicated copy coordinator, with
frozen sources, strict receipts, shared deadlines and publication recovery
before cleanup. The generic single-photo executor can target only its own
object; the coordinator claims validated sibling targets. Recovery alone grants
no execution authority. No storage worker or live binder is connected; rollout
stays disabled.

## October 4, 2026: exact reserved-cohort binding

The prepared service binding facade now verifies the exact settled reservation
against both the transactional publication receipt and actual ordered post
bindings. Historical recovery precedes live work/gate checks and retains
deletion fencing. The explicit no-note subset and a new default-false gate
remain; the bounded storage worker and native delivery are still pending.

## October 4, 2026: bounded copy operation controller

A prepared controller now connects whole-cohort verification to sequential
copies and exact binding with shared work, completion and cleanup deadlines. It
recovers durable publication before targeted erasure and treats uncertain
transport results as reconciliation. The HTTP service owner, durable copy-phase
needs-action outcomes and runtime qualification remain required before rollout.

## October 4, 2026: durable copy needs-action outcomes

The prepared copy stage now records immutable note-moderation and staging-expiry
outcomes separately from provider approval, removing unfulfillable work while
retaining targeted cleanup. Publication and deletion win over settlement replay.
The existing owner status reports needs-action without private details. Upstream
unsupported-source attestation and the service execution owner remain pending;
all gates remain disabled.

## Implementation checkpoint: unsupported source types

The prepared moderation finalizer now retires zero-attempt operations whose
immutable source type cannot enter public-copy validation (currently HEIC),
behind an independent default-false gate. The private immutable needs-action
outcome survives lost replies and prevents repeated reclamation without charging
quota. Existing provider attempts retain their original recovery rules. Verified
container attestation, bounded copy service integration, owner/native delivery
and runtime/CDN qualification remain incomplete. This checkpoint authorizes no
activation or deployment.

## Implementation checkpoint: verified container remediation

A prepared service path now stores exact source-bound container-policy rejection
evidence and retires zero-attempt publication work atomically. It distinguishes
conservative public-publication rejection from private evidence validity, and
preserves generic read/parser/network/digest/cancellation recovery. Original
attempts and committed publications cannot be replaced. All gates remain off.
Bounded copy service ownership, owner/native remediation delivery and
CPU/memory/CDN qualification remain incomplete.

## Implementation checkpoint: bounded copy service owner

The prepared service-only copy endpoint now connects durable claim/finalization,
exact cohort preflight/binding, original expiry and targeted cleanup. It
preserves a full controller window and separate lease-release budget; slow setup
skips copying. The endpoint is not scheduled, deployed or activated. Verified
recurring independent erasure and backlog/CDN monitoring are hard activation
requirements because terminal expiry removes copy work. CPU/memory
qualification, owner status and native durable operations remain incomplete.

### Owner operation-status delivery checkpoint (October 4)

The prepared authenticated status route now reads one saved operation and emits
only the existing five-field owner projection, with strict decoding and private
no-store on every branch. Missing, foreign and deleted operations remain opaque.
Historical admission does not assert current publication eligibility or provide
a post link. No native consumer or activation is added; native delivery must
persist exact operation identity before I/O and remain account/deletion fenced.

### Native wire preparation checkpoint (October 4)

Strict native publication request/receipt models and account-bound endpoint
calls now cover durable intake and exact-operation polling. They preserve
immutable consent and reject private response fields or mismatched identities.
The existing raw-JSON bridge already supports expected-owner dispatch and
deferred 401 recovery, so no core transport extension was needed. No queue, UI
or activation is connected in this slice; future persistence must retain minimal
terminal status across restart and erase it with the scan.

### Native durable storage checkpoint (October 4)

Prepared publication persistence now saves exact owner-bound consent under an
observation-qualified operation key. Versioned canonical SHA-256 survives raw
consent removal after acknowledgement, preventing changed consent from reusing
an old operation ID. Minimal terminal status survives disk reopening, with
compare-and-save protecting newer acknowledgements and no same-ID resurrection.
Direct, bulk and cloud-confirmed deletion remove associated receipts/work;
scan-qualified keys retain erasure reachability when subject metadata is
damaged. Unknown job kinds cannot cause timer-only retry loops; known
library-details work is preserved. No persisted schema shape or frozen snapshot
changes.

This slice does not connect a network drain or UI. Exact account leases around
awaits, status-first lost-response recovery, durable retry/permanent-failure
classification and bounded polling remain the next execution slice. Activation
and production scheduling remain disabled.

### Native delivery checkpoint — October 4, 2026

The prepared native publication outbox now has an account-bound delivery owner
and scheduler integration. It durably claims the existing immutable operation,
recovers status first, and only replays original consent on the precise
owner-visible not-found response. Acknowledged operations cannot re-admit.
Monotonic attempt identity fences late acknowledgements and retries even when
the saved consent is unchanged. Interrupted work retains a fixed recovery
deadline; failed saves also request a bounded process wake. Terminal receipts
remain complete, while proven local delivery conflicts require attention without
inventing a server terminal result. Connectivity cancellation and awaited Auth
quiescence retain task/lease ownership. Ordinary UI enqueue and every activation
gate remain disabled. Validation evidence belongs to the candidate checkpoint;
this implementation note does not assert production qualification or deployment.

### October 4 update: dedicated consent preflight

Prepared owner-authenticated consent preflight now projects an explicit
analysis's current revisions, active taxonomy, fixed-null initial taxon and
ordered immutable V2 photo candidates under shared locked eligibility. It
creates no operation and promises no ready media or publication authority.
Existing exact consent admission retains its receipt and revision checks; closed
generic history/status readers are unchanged. Native consent production and UI
remain next, with all activation gates false. The current contract is
[documented here](../backend-and-data/05-api-contracts.md#owner-publication-consent-preflight).

### October 4 update: native consent wire boundary

Prepared native preflight now has a strict, separately bounded 32 KiB decoder
and expected-account transport, preserving the existing 4 KiB admission/status
contracts. It returns all ordered candidate metadata without selecting a cohort,
minting an operation or inferring ready media. Explicit foreground consent
production and UI remain next, with every activation gate closed. See the
[current API contract](../backend-and-data/05-api-contracts.md#native-consent-preflight-transport).

### October 4 update: completion integration priority

The remaining work is grouped into integrated milestones: append-only live and
queued reanalysis; ordinary enrollment/history/restore wiring; analysis-bound
review and explicit community photo consent; and final account-deletion,
legacy-compatibility and runtime qualification. The current production
reanalysis replacement path is the highest-priority integration gap. The
prepared native consent service now persists explicit ordered photo consent
before waking durable delivery, with historical retry and per-analysis revision
fences. Ordinary UI and rollout remain closed.

Focused checks accompany implementation. Full affected-surface validation runs
at integrated milestones and on the final candidate; intermediate GitHub Actions
runs do not block further implementation. This changes verification cadence, not
the final acceptance or release-authorization requirements.

### October 5: private reanalysis upload integration

The prepared owner-authenticated `upload-observation-evidence` route now accepts
bounded raw photo bytes and computes their digests before atomically reserving
the complete ordered cohort. Immutable cohort metadata survives abandoned
receipt cleanup, preserving the child analysis identity and fixed expiry. V2
admission preserves the image subsequence; cleaned photo identities cannot be
rebound to description-only work. Conditional private storage writes and
completion share a deadline and recheck deletion. The response contains only V2
content references. See the
[current API contract](../backend-and-data/05-api-contracts.md#private-reanalysis-photo-upload).

This closes the missing authenticated private write boundary. Native binary
transport, durable capture/queue identities and append-only completion still
need integration before the user-facing reanalysis path is complete. All
activation gates remain disabled, and private-bucket/erasure qualification is
still required. Implementation does not authorize deployment or scheduling.

### October 5: native private upload and immutable request values

The native upload transport now sends the exact binary cohort under an expected
account lease, suppresses automatic ambiguous retries and session refresh, and
validates receipt identities, order, byte counts and hashes against submitted
bytes. Prepared photo reanalysis values preserve explicit source identity,
processor expectation and complete request bytes with a checked fingerprint;
execution receipts carry no result or selection authority. These boundaries have
no ordinary capture producer yet. The next integration persists stable
child/media identities in the existing scan-ingestion metadata, dispatches
through the existing consent/funding owners, and recovers authoritative child
history before queue completion. Existing SwiftData model shapes and rollout
gates remain unchanged.

The queue integration review also requires a persisted discriminator and parent
observation linkage in a new SwiftData schema. Job JSON alone is insufficient:
missing metadata can otherwise enter ordinary identification, parent deletion
cannot find the child queue row, and the library can show a duplicate scan.
Immutable request/media payloads may still use the existing job envelope, but
routing and erasure must not depend solely on decoding that payload. Frozen
queue snapshots must remain unchanged; the discriminator needs explicit forward
migration and damaged-metadata, deletion and library-projection coverage.

### October 5: qualified queue storage boundary

V57 was frozen and compiled before adding the V58 queue discriminator and
nullable parent/source/owner fields. Existing queue IDs remain child analysis
identities; legacy rows migrate to ordinary work with nil linkage. All forward
plans and startup recovery routes advance through V58. The queue classifier and
legacy upload, replay, account, retry and finalization guards fail closed
independently of job JSON. An absent row cannot be recreated by a late offline
completion.

This is storage preparation, with no qualified capture producer enabled. The
next integration must connect parent-linked atomic erasure and
observation-attached progress before exact private upload/analysis delivery and
append-only recovery. The canonical current contract is the
[V58 storage section](../backend-and-data/04-database-schema.md#v58-qualified-queued-reanalysis-storage).

### October 5 implementation: atomic queued-child erasure

Direct and explicit non-biological parent deletion now erase exact parent-linked
queue rows, ingestion jobs and preferred-goal hints within the parent
transaction, including damaged kind/owner/source/job data. Post-commit
cancellation refetches child absence and retains the original model-container
boundary. File cleanup is restricted to the dedicated child namespace; shared
parent/library paths are never inferred to be owned. Rollback, damaged linkage,
unrelated-parent isolation, namespace traversal and both deletion entry points
have focused coverage. Qualified production admission remains disabled; detached
progress, recipient preflight, funding, durable execution and append-only
completion are still pending.

### Owner-bound reanalysis preflight — October 5, 2026

The dedicated authenticated photo preflight now binds parent, historical source
and proposed child before reading current recipient policy. Existing exact
intents return recovery-only across all lifecycle states; legacy identities
conflict. The native request/decoder and consent authorization path are prepared
without enabling UI or execution. Funding remains inside atomic server
admission; native must not create a legacy complimentary hold first. The
existing exact owner-state reader already supports targeted completed-child
recovery independently of pagination. Qualified durable production,
upload/recovery orchestration and append-only local completion remain the next
integration work. See the
[current API contract](../backend-and-data/05-api-contracts.md#prepared-child-analysis-orchestration-and-recovery).

### October 5: prepared atomic native reanalysis staging

The native persistence boundary now stores the exact owner-bound request and
qualified V58 child/job pair atomically, with immutable child-owned photo paths.
Restart and same-ID replay preserve bytes and terminal state; damaged metadata,
identity collisions, account changes and parent deletion fail closed. Ordinary
scheduler deadlines no longer wake unserviceable qualified or orphan ingestion
work. Dedicated execution and the ordinary UI producer remain pending; this
prepared stage stays held and changes no selection or funding. All activation
gates remain disabled.

The completion decoder now binds a structurally valid V2 result to the saved
child/source/request digest and complete ordered evidence, including private
descriptions. It retains exact result bytes and has no persistence side effects.
The dedicated execution owner must still supply account/deletion/claim fences
and perform append-only admission.

### October 5: exact native analysis transport

Prepared native admission/recovery now transmits immutable saved request bytes
through a closed account-bound route without automatic retry or 401 refresh.
Current dispatch authorization must match the saved processor; recovery-only
preflight cannot authorize admitted work that may still dispatch. The response
remains execution state only. Durable draft production, execution integration,
ordinary UI and activation remain separate work.

### October 5: offline draft and one-time request binding

Prepared native persistence now retains child identity and ordered evidence
before recipient preflight, with no invented processor. The versioned local
draft binds once to the exact request under the existing account/source/deletion
transaction. Replays preserve bound terminal work; changed evidence or recipient
conflicts, and recovery-only cannot reconstruct an unbound request.
Verified-file production, dedicated execution and ordinary UI remain
unconnected; all gates remain closed. No persisted model field or retired
snapshot changes.

### October 5: frozen source and staged photo provenance

Prepared native source capture now retains the exact owner, observation,
historical analysis and immutable snapshot, revalidating membership and deletion
without retargeting to a later selection. Imported V3 and legacy V1 analyses
remain eligible identification anchors but cannot automatically supply protected
photo references. Only V2 references authorize verified original-photo loading.
Staged crop provenance and admission snapshots distinguish original evidence
from edited or added photos, including chronological changes. Capture entry,
verified-file production and dedicated execution remain unconnected; this
checkpoint does not enable reanalysis or change the closed activation gates.

### October 5: prepared verified-file producer

The native producer now maps explicit ordered evidence into fresh child media
identities, verifies original private bytes, normalizes added/cropped photos to
bounded JPEG, and durably writes immutable child files before the held queue
save. Account, generation and frozen source checks guard the handoff. Exclusive
filesystem ownership spans the synchronous save; rollback cannot overwrite or
remove an earlier attempt's files. Capture entry, execution and ordinary UI are
still unconnected, and all activation gates remain false. Pre-save crash orphan
maintenance, full account namespace erasure, and durable individual-parent
attribution/cleanup before photo I/O remain mandatory activation prerequisites.
Maintenance must acquire filesystem ownership before a fresh database lookup;
deletion must commit its database fence before file cleanup, without holding the
shared database lock while waiting for a file lock.

### October 5: durable ownership before private file I/O

The prepared producer now persists an immutable `files_pending` envelope before
writing private photos. It binds the exact draft to the frozen source snapshot
SHA-256, separately from recipient binding. Locked pre-write validation and a
fresh pending-to-ready compare-and-save prevent deletion from reinserting child
work. Pending metadata is rejected by ordinary draft/request decoders.

Parent removal atomically retains a minimal canonical namespace erasure receipt,
even when child job metadata is damaged. All reanalysis staging rejects that
receipt; the local erasure kind cannot drive network scheduler wakes. This
closes the unindexed pre-save ownership gap in the October 5 producer
checkpoint, but does not yet execute namespace cleanup or restart recovery.
Those owners and full-account purge remain required before capture entry is
connected. All activation gates remain false.

### October 5: local durable reanalysis file cleanup

A local cleanup owner now runs after parent deletion and from startup/foreground
recovery without network or AI consent admission. It checks exact durable
receipts and child absence under the preparation filesystem lock, removes child
files without following symlinks, and acknowledges completion while retaining a
minimal identity tombstone. Failed acknowledgement after file erasure remains
recoverable; failed/malformed entries do not block later discovery pages.
Generic observation file deletion no longer receives child paths.

Writers and cleanup share a lock on the trusted Documents root to support the
future exclusive full-account namespace purge. That purge and verified
complete-cohort pending recovery still precede live capture integration. All
activation gates remain false.

### October 5: prepared complete-cohort recovery

Targeted native recovery now verifies a saved `files_pending` cohort before
advancing that same child to a ready draft. It opens only existing files, checks
the immutable source fingerprint and ordered photo evidence, and retains the
filesystem fence through fresh database validation. Incomplete or changed
cohorts remain held; terminal replay cannot revive work. This does not yet wire
restart delivery or provider execution. Full-account namespace purge was the
next local privacy boundary at this checkpoint; the following entry records its
implementation. The
[current producer contract](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md#verified-file-production)
owns the implementation details; all activation gates remain disabled.

### October 5: full-account private reanalysis purge

Account deletion and library-clearing sign-out now await private reanalysis
namespace erasure after row deletion and before preferences/runtime reset or
recovery-marker retirement. The purge drains local receipt work and holds the
exclusive Documents root lock against writers, recovery and child cleanup. It
includes orphaned preparation files, never follows symlinks, and leaves
unrelated Documents content alone. Failure keeps the existing cleanup barrier
for retry. The
[current data contract](../../apps/ios/Merian/Core/Data/README.md) owns this
boundary. Capture/execution integration and feature activation remain
outstanding.

### October 5: exact Capture evidence and retained preparation identity

Prepared native Capture owners now preserve the complete immutable V2 evidence
timeline, require explicit original-photo selection and load that selection
atomically with verified bytes and historical provenance. V1/V3 inherit no
mutable observation media or notes. A session retains one plan and child/media
identity across an ambiguous preparation response and rejects changed input. The
producer now fences private result delivery after durable file completion; late
account/generation loss cannot roll back that durable success. Ordinary Capture
entry, the chooser, submission wiring and dedicated execution remain
unconnected, with every activation gate disabled. Current ownership and tests
are documented in the
[Capture preparation contract](../../apps/ios/Merian/Features/Capture/Submission/README.md#protected-capture-preparation).
