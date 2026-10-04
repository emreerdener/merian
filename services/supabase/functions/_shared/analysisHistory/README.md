# Observation analysis history

Private backend preparation for the
[reversible reanalysis RFC](../../../../../docs/rfcs/reversible-reanalysis-and-identification-history-2026-10-02.md).
This is not a live reanalysis or restoration API. Enrollment and selection
remain closed, existing scans are unchanged, and no endpoint calls the private
history selection transaction.

## Owners and bounds

`contract.ts` owns exact request identities, errors and bounded primitive
parsers. `transitions.ts` models selection and revision decisions; `result.ts`
reuses the canonical Identify and captured-media validators; `page.ts` binds
bounded pages and immutable snapshot bytes to the requested
observation/account/cursor. `authority.ts` binds evidence and review to the same
analysis before using the existing effective-identification policy. Pure
decision functions do not replace locked persistence, provider admission,
entitlement settlement, or authorization.

| Value                                    | Bound                                    |
| ---------------------------------------- | ---------------------------------------- |
| Snapshot schema versions                 | 1, 2 and imported saved-identification 3 |
| Explicit history reader protocols        | 7 (V1), 8 (V1/V2), 9 (V1/V2/V3)          |
| History page                             | 1–20 entries, descending ordinal cursor  |
| Observation/review revision              | 0–2,147,483,646; exhaustion fails closed |
| Result or evidence storage envelope      | 1 MiB each                               |
| Review or active projection              | 32 KiB each                              |
| Selection operation identity / receipt   | 2 KiB / 4 KiB                            |
| Chat system input / assembled user input | 64 KiB / 128 KiB UTF-8                   |
| Serialized chat admission context        | 256 KiB                                  |

All versioned request keys are exact. An owner UUID supplied in a request body
is invalid; a future route must derive identity from its verified session.
Observation, analysis, source analysis and operation IDs are distinct. Retry
identity includes expected revisions, so a stale operation cannot be silently
rebased. The chat parser bounds the immutable payload but does not yet persist
it with live turn admission.

## Prepared persistence

The private tables belong to the stable scan through foreign keys. API roles
have no direct access, including `service_role`, and all tables enable RLS.
Enrollment, selection, reader and append switches all default false. Disabled or
missing configuration rejects new enrollment and new selection respectively;
exact selection receipt replay still checks ownership/deletion and returns the
original receipt without changing state. The switches are not a blanket
suspension of review or deletion guards. The reader migration bounds the
complete immutable snapshot (metadata, ordinal, result and evidence combined) to
1 MiB at the database boundary. Its private `observation_analysis_snapshot`
function supplies both that constraint and the read serialization. The Identify
result uses `scan_id = observation_id`; the outer analysis UUID remains
independent. Evidence uses the existing strict
`{schema_version:1,captured_media:[...]}` contract, with at least one entry.
These validators do not prove media ownership or durable availability. A future
completion producer must validate canonical result semantics and protected,
recoverable evidence before committing; none is connected in this slice.

The SQL projection also requires validated server-only fields such as
`species_id` in its stored `result_snapshot`. Completion must construct that
projection-ready object separately and cross-check it against canonical Identify
data and taxonomy. The Identify validation view drops these extra fields and
must never become the persisted server object. Read pages and native admission
retain the original snapshot bytes, including these fields.

The private `internal.select_observation_analysis(uuid,jsonb)` transaction uses
owner → observation generation lock → scan → history → authority lock order. It
verifies owner membership and the deletion fence before receipt replay. New
selection commits projection, pointer, monotonic revision, receipt and a
reconciliation obligation together. Exact replay returns the old receipt without
reapplying old state. Changed review authority advances the parent revision even
when its analysis is not selected. Future review entry points must acquire this
same lock order before updating authority rows.

The SQL projector constructs a temporary typed value from explicitly selected
evidence and authority keys and invokes the existing identity policy. It never
writes those values to the original scan row. The outbox is not yet consumed by
credits or public visibility workers; activation requires their transactional
revision guards. No second complimentary-credit settlement mechanism exists.

Backend expiry excludes enrolled history at discovery and locked revalidation.
Legacy deletion returns `legacy_observation_delete_requires_upgrade` without a
tombstone. These protections do not enable explicit history deletion or prevent
an old app from erasing its local cache. Native source now holds the exact
server-refused legacy task durably without retrying. The prepared owner-only
`get_owned_observation_analysis_page` RPC checks explicit protocol 7, 8 or 9,
the reader gate, current owner, parent and deletion fence before returning a
bounded page. Native `Core/Data/AnalysisHistory` decodes and admits these pages
only for an already-enrolled matching local owner; ordinary app sync never calls
it. Verified enrollment, live completion, held-task reconciliation (new native
requests now carry local account/origin provenance), child ingestion fences,
protected media, account-retention allowlist, publication and chat integrations
remain required.

## Prepared append boundary

`append.ts` canonicalizes Identify results and independently resolved species
links for `internal.append_observation_analysis(uuid,jsonb)`. This storage
primitive has no API execution grant or production caller and its own closed
`append_enabled` gate. It atomically assigns an ordinal, stores evidence and
fresh unreviewed authority, and returns an exact replayable snapshot. It never
changes an existing selection or copies a prior result's review authority. First
selection also requires an empty revision-zero history and immutable
`initial_selection_permitted`, false for existing rows. A future admission owner
must prove new-observation eligibility when inserting that permission.

Only description evidence is accepted. Existing public scan-media URLs do not
prove private access; every media variant fails closed until protected
promotion, receipts, authorized reads and deletion cleanup are implemented. This
is not a completion orchestrator: it does not validate a provider admission
ledger, mark a job complete or settle a complimentary hold. The separate private
funded-child lifecycle now performs those checks for description evidence and
commits append/settlement in one transaction. The
[canonical append contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-private-analysis-append)
separates the implemented storage boundary from those activation prerequisites.

## Verification

`history_test.ts`, `authority_test.ts`, `reader_test.ts` and `append_test.ts`
run in candidate CI. The reader tests and native decoder share the synthetic
`fixtures/page-v1.json` contract. `tests/observation_analysis_reader.sql` covers
owner/foreign access, closed reader/old protocol rejection, cursor order,
aggregate size, page byte budget and deletion fencing under actual database
roles. The discovered migration-contract suite covers release closure, deletion
ordering and private selection boundaries.
`tests/observation_analysis_history.sql` runs with the full database catalog
suite, using only synthetic, rollback-scoped fixtures. The database owner
enables gates only within that rolled-back fixture; no production or local
persisted enrollment is performed.

The deletion route's legacy-history rejection is tested in
`delete-scan/handler_test.ts`, including the absence of media lookup and
completion calls. Full feature acceptance remains tracked in the RFC; these
tests do not claim live provider, public-post or chat-recovery coverage. The
funding SQL fixture and separate-session concurrency suite below cover prepared
transaction semantics, not deployed recovery. The canonical
[verification matrix](../../../../../docs/development-guides/08-testing-strategy.md#observation-analysis-history-preparation)
distinguishes sequential transaction assertions from the concurrency and device
acceptance still required by the
[activation hold](../../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold).

## Prepared protected evidence storage

`evidence.ts` and `evidenceStorage.ts` prepare a separate private-bucket
lifecycle. Upload/cleanup have no live endpoint, database adapter, worker
schedule or API execution permission. The completed-photo read adapter is
prepared below. `media_enabled` and `media_reader_enabled` default false. V1
history snapshots and native DTOs are unchanged; description-only append still
rejects media. The separate V2 photo binder below now validates ready receipts
and completes funding atomically; live inference orchestration/native
presentation remain required for reanalysis support.

A trusted writer buffers at most 32 MiB, computes SHA-256, reserves an immutable
owner/observation/analysis/media tuple, conditionally writes an opaque random
object key, verifies size/type/hash metadata with HEAD, then repeats the
database ownership/deletion check before readiness. No client PUT capability is
issued. Reservation expires after five minutes without renewal; completed replay
reuses the receipt. MIME values are bounded metadata, not a content-safety
verdict. Future admission retains responsibility for media validation and
account budgets. At most 64 receipts belong to an analysis. Description append
and reservations share an analysis lock and reject collisions, including across
observations.

An owner read resolves a ready receipt before issuing a no-store S3 GET signed
for 30 seconds with separate read credentials. It is a short bearer capability;
an already-issued URL can remain usable until expiry or object erasure. URLs,
keys and full storage receipts must never enter public projections, logs or
immutable result snapshots. V2 stores only private media IDs and content tuples,
which cannot reveal an object key or authorize a read. There is no public read
route yet.

Deleting receipts (including parent/account cascades), inserting a scan
tombstone, or expiring an unfinished reservation creates an independent erasure
obligation. A bounded claim-token worker seam overwrites content with an empty
marker and HEAD-verifies the marker before acknowledging. It never deletes the
key: every late conditional upload then fails regardless of ordering. The
surviving ledger contains only an opaque object UUID and cleanup
timestamps/claim state.

Marker permanence is a trusted-writer contract, not R2 Object Lock. Credentials
must be exclusive to this owner, all content PUTs conditional, and every bucket
lifecycle/maintenance job must preserve markers. The bucket must have no public
endpoint or custom domain and must differ from the public scan bucket. See the
[activation hold](../../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold)
and
[credential ownership](../../../../../docs/backend-and-data/13-server-credentials-and-database-release-safety.md#prepared-history-evidence-credentials).
No bucket or credentials were provisioned or tested against hosted R2.

`evidence_test.ts` covers storage semantics using synthetic in-memory transport;
`tests/observation_evidence.sql` covers actual locked SQL/ACL/cascade behavior;
`_tests/observationEvidenceConcurrencyDb.test.ts` uses separate PostgreSQL
sessions for completion/deletion/account and cross-owner analysis collisions.

## Prepared funded description analyses

`intent.ts` freezes client capabilities and description evidence at admission
and builds a canonical result draft from those saved bytes. The private SQL
intent owner handles reservation, one-time provider accounting, draft
persistence, atomic append/credit settlement and exact receipt replay. Internal
API execution remains revoked. The default-off orchestration wrappers and
authenticated endpoint below now own provider work; all gates stay false. It
shares ledger transitions with existing scan completion rather than implementing
a second funding policy. See the
[canonical lifecycle](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-funded-child-analysis-lifecycle).

`intent_test.ts` verifies immutable admission and canonical drafts.
`tests/observation_analysis_funding.sql` covers closed access, lost responses,
legacy bypass rejection, paid-before-completion release, proven versus ambiguous
outcomes, atomic rollback, lease renewal and permanent child deletion markers.
`_tests/observationAnalysisFundingConcurrencyDb.test.ts` uses real separate
sessions for duplicate completion, deletion/account races and legacy admission
or terminalization blocked behind child state. The discovered migration suite
also checks the new closed gates and legacy source guards. V2 photo binding is
prepared below; gated orchestration/recovery is implemented, while enrollment
and normal native delivery remain future work.

## Prepared protected photo completion

`protectedManifest.ts` owns exact V2 identities, photo/description manifests,
receipt projection and canonical draft construction. It shares Identify/taxonomy
validation with `append.ts`. The new private SQL admission binds all ready
photos before quota; completion revalidates those pins before the shared atomic
append/settlement. A separate false gate and capability 8 keep it unavailable to
V1 clients. No provider or normal native presentation caller is connected;
protocol-8 decoding and private photo resolution are prepared. Audio/video
binding is not supported. See the
[canonical V2 contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-protected-photo-analyses).

`protectedManifest_test.ts` covers strict shapes, bounds, privacy, canonical
result fields and old-reader rejection.
`tests/observation_protected_analysis.sql` verifies actual ready receipt
binding, exact retry, pinning, terminal cleanup, expiry, credit settlement and
owner-before-version rejection.
`_tests/observationProtectedAnalysisConcurrencyDb.test.ts` uses separate
database sessions for duplicate completion, deletion in both orders and account
detachment. V1 fixtures remain the byte-compatibility baseline.

## Protocol-8 read boundary

`result.ts`/`page.ts` retain strict V1 defaults; explicit reader 8 accepts V2
protected manifests and mixed pages while preserving all original snapshot text.
`fixtures/page-v2.json` is shared with native decoding/persistence tests.
`resolve-history-photo` owns authenticated delivery and the service-only
database receipt adapter. The internal receipt never becomes the response; only
a bounded temporary content ticket is returned after a second fence check. See
the
[canonical read contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-protocol-8-reads-and-private-photo-resolution).

## Gated orchestration and completion recovery

`analysisInput.ts`, `execution.ts` and `production.ts` validate frozen requests,
materialize private photos, dispatch the qualified provider once, save canonical
output before taxonomy, and complete from that checkpoint. The SQL work claim is
separate from the provider invocation and complimentary hold. Only a live worker
that never entered provider invocation can prove cancellation after an uncertain
dispatch acknowledgement. Other uncertain executions remain held.

`analyze-observation` is the authenticated producer;
`recover-observation-analyses` is the bounded service-only completion consumer.
Both are prepared source with the orchestration gate false and no schedule. See
the
[canonical contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-child-analysis-orchestration-and-recovery).
`execution_test.ts` covers crash boundaries, immutable recovery, provider budget
rejection and deletion. SQL and separate-session tests verify claim contention,
late output, completion binding, billing and deletion/account ordering.

## Prepared saved-identification import

`savedIdentification.ts` validates V3 saved-result fields and the owner-bound
baseline acknowledgement. `enroll_owned_observation_history` derives the owner
from auth, preserves the current identification and all seven review fields, and
creates a selected baseline with no invented execution digest/date. Its new
`saved_import_enabled` gate remains false alongside enrollment/reader gates.
Retries recover the baseline UUID without undoing later selection. Imported
legacy candidate/pet values remain opaque saved data, not provider DTOs.

Protocol 9 reads explicit V3 imports; protocols 7/8 reject the whole imported
history. V1/V2 bytes and non-null execution metadata are unchanged. Legacy
public media is never promoted into private receipts by enrollment. The native
reader now uses protocol 9, and V56 stores V3 completion as nil. Current
selection/authority hydration is still required before enrollment can connect.
There is no live app enrollment call site. The
[canonical contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-saved-identification-enrollment-and-protocol-9)
and RFC retain authority/public/chat/deletion activation prerequisites.

## Prepared atomic state read

`state.ts` validates the owner state request and a single immutable snapshot
with its separate mutable authority. Null target reads selection; an explicit
target previews without selecting. `get_owned_observation_analysis_state`
requires both reader holds and serializes against review, selection and
deletion. Native `ObservationHistoryState` shares the fixture and keeps
authority out of immutable result bytes. Native state admission is prepared;
ordinary sync and Restore presentation remain disconnected. The
[canonical API](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-owner-observation-state-read)
defines response bounds and the remaining revision/account/pending-review gates.

## Prepared native selection consumer

`fixtures/selection-v1.json` is shared by native receipt tests and
`history_test.ts`, which verifies the canonical six-field selection request and
seven-field receipt produced by `selectAnalysis`. Receipt replay preserves newer
server state. Native preparation persists exact operation identity before
dispatch and admits a validated receipt atomically with a subsequent current
state read. Undo binds the caller's receipt operation, current
selection/revision and the prior analysis's own authority. Protocol 9 now
prepares an authenticated owner wrapper around the private selection transaction
and a native live adapter. `parseSelectionRejection` and the shared fixture bind
the seven-field durable rejection to the exact request. Both accepted and
rejected operations occupy the same immutable outcome ledger; replay never
re-applies selection. The
[native contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-native-selection-requests-and-undo-receipts)
defines owner locks, conflict recovery, closed gates and remaining presentation
work. No rollout gate was enabled.

## Prepared analysis-bound rejection

`review.ts` owns the protocol-9 Reject/Undo request and immutable outcome parser
for `review_owned_observation_analysis`. Both revisions and the exact analysis
are bound to an operation; Undo additionally names its accepted rejection.
Receipts cannot substitute for a current-state read. The default-false
`rejection_api_enabled` gate remains closed and native review admission is not
wired. Confirmation is separately prepared below; community authority still
requires a subsequent slice.

`observation_analysis_review.sql` and
`observationAnalysisReviewConcurrencyDb.test.ts` cover authority isolation,
receipt recovery, selection races, deletion, and enrollment racing legacy
review. Legacy Edge preflight is shared in `identify/legacyReview.ts`; database
commit checks remain authoritative. See the
[canonical contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-analysis-bound-reject-and-undo).

## Prepared analysis-bound confirmation

`confirmation.ts` owns strict protocol-9 confirmation requests, internal
prepare/complete envelopes and immutable outcomes. The
[`confirm-observation-analysis`](../../confirm-observation-analysis/README.md)
endpoint freezes query and intent before dictionary verification, then commits
only against both current revisions. Its independent confirmation gate defaults
false. Exact completed retries skip verification; explicit confirmation can
clear only the named result's rejection. Native admission, community authority
and ordinary activation remain held. See the
[canonical contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-analysis-bound-confirmation).

## Private community authority foundation

The community binding/reconciliation migration prepares database-only ownership
of a named result. No public or service RPC, endpoint, scheduler or native
caller is exposed. A fresh-request transaction fence prevents automatic
attachment of old scan-based requests. Bound consensus increments a durable
queue revision; the private reconciler reads current source state, respects
later owner review, and yields on lock contention. Request deletion retains
revocation work, while observation deletion erases it. The new-binding gate
defaults false. Public snapshot/admission and dispatcher integration remain
required; see the
[canonical contract](../../../../../docs/backend-and-data/05-api-contracts.md#private-analysis-bound-community-authority-preparation).

## Prepared public publication reads

Private registration now freezes an approved public media cohort and original
labels for a named, community-bound result. A sanitized public projection drives
Explore readers and invalidates immediately on authority/source changes. The
writer has no API grant and its gate defaults false; there is no moderated
publisher or native sharing caller yet. See the
[publication contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-analysis-publication-snapshots-and-public-reads)
for read coverage, reference retirement and remaining activation work.

## Prepared community request admission

The private atomic admission owner now creates one fresh analysis-bound request,
freezes approved public evidence, and records an immutable operation receipt.
Exact retries recover without replacing a discussion or reapplying authority. No
API writer, moderated endpoint or native caller is enabled. See the
[canonical contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-atomic-community-request-admission)
for the default-off gate, insertion proof, public-reader privacy and remaining
publisher integration.

## Protected publication intent foundation

The private SQL preparation records exact V2 ready-photo facts before external
work. Its historical receipt is not a current authorization: a separate
revalidation checks revisions, gates, ownership and content tuples. No Edge
adapter, public-copy writer or media approval is enabled. Provider completion
does not supply durable approval to publish private photos. See the
[intent contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-protected-photo-publication-intent)
for the remaining moderation, cleanup and publisher requirements.

## Prepared photo moderation attempts

The private SQL lifecycle owns per-photo source/policy binding, provider-only
quota, explicit predecessor retries, one-time dispatch permits and immutable
terminal decisions. Ambiguous executions retain their charge; deletion refunds
only reserved work. The classifier adapter is prepared below; durable execution
and public-copy ownership are prepared below. The quota operation is added to
the shared type; affected Identify/Field Chat bundle identities are regenerated.
See the
[attempt contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-photo-moderation-attempt-lifecycle).

## Prepared photo classifier adapter

`photoClassifier.ts` freezes a source-verified inline Gemini request and a
policy/transport/request proof before a single invocation. Its bounded strict
response parser returns only decision/category/confidence and accounting facts.
Transport or output uncertainty cannot approve, refund or retry.
`photoClassifier_test.ts` uses synthetic bytes and injected transports; no
provider request is made by tests. The adapter has no production caller. Durable
proof persistence, dispatch binding and atomic output are prepared below; see
the
[classifier contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-bound-photo-classifier-adapter).

## Prepared durable photo execution

`photoExecution.ts` persists the same adapter proof before dispatch and invokes
its frozen closure once. Only identical completion writes may retry. SQL now
requires proof before dispatch and bounded result/usage before completing a
decision, atomically and under deletion/authority locks.
`photoExecution_test.ts` covers failure ordering and pins the actual policy
digest to its migration. The SQL catalog and separate-session tests cover
proof/result replay and completion versus review/deletion. No live repository
adapter, endpoint or expired-attempt recovery scheduler is connected. See the
[execution contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-durable-photo-execution-binding).

## Prepared public-photo storage

`publicPhotoContainer.ts` bounds and filters JPEG/PNG containers before
`publicPhotoStorage.ts` writes exact source bytes conditionally. Erasure retains
an empty permanent marker, preventing delayed conditional writes from restoring
origin content. Tests use only synthetic images and in-memory storage. SQL
allocation/cleanup owners are prepared below; the prepared erasure worker uses
`erase`, while the public-copy writer remains unconnected. Origin markers do not
prove cache revocation. See the
[storage contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-storage-boundary).

## Prepared public-photo staging ownership

Private SQL now reserves a permanent opaque-key cleanup obligation plus an
immutable source/lease receipt before the future writer runs. Staging completion
revalidates approval and authority; readiness cannot extend its ten-minute
cleanup deadline. Public copying remains unconnected; the separate prepared
erasure worker uses `publicPhotoStorage.ts` only to retain verified markers. See
the
[staging contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-staging-lifecycle).

## Prepared atomic photo publication

The private SQL binder now admits a fresh community request and its entire
ordered approved photo cohort atomically. Immutable receipts support replay;
unshare/moderation/delete queue erasure, while health quarantine remains
reversible. No authenticated publisher or public-copy writer is connected. See
the
[binding contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-atomic-public-photo-binding).

`erase-publication-photos` now provides a prepared service-only registry/marker
cleanup owner, including targeted claims for future failed-copy recovery. It
uses no private account context and does not enable copying or publication. See
its [README](../../erase-publication-photos/README.md).

## Prepared copy execution owner

`photoCopyExecution.ts` freezes scope and exact source, validates the durable
reservation, verifies private bytes, conditionally copies and retries only the
identical completion. Failure attempts abandonment and targeted cleanup through
`photoErasure.ts`, the shared owner also used by the erasure endpoint. Registry
claims protect concurrent bound publications even after private deletion.
`photoCopyExecution_test.ts` covers these interruption and mutation boundaries.
No live copy repository or authenticated publisher is connected; `reconcile`
requires durable operation-state recovery, never automatic successor allocation.
See the
[copy execution contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-copy-execution).

## Prepared durable publication intake

`request-observation-publication` now authenticates and persists exact ordered
consent before external work, returning an immutable acceptance receipt.
`publicationOperation.ts` owns strict parsing; the default-off service RPC and
private records preserve replay, original hash and deletion fences. Acceptance
never authorizes copying or means publication completed. Live execution/status
workers and native delivery remain required. See the
[intake contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-authenticated-publication-operation-intake).

## Prepared publication worker ownership

Separate private work records now provide bounded discovery, scoped expiring
claims and gate-independent release/status beneath immutable intake. Only a
durable cohort receipt establishes historical admission; orchestration leases
confer no provider or public-copy authority. The execution gate remains false,
and worker/status endpoints and native delivery remain unconnected. Optional
public notes still require their own moderation boundary. See the
[worker contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-publication-operation-worker-ownership).

## Scoped moderation recovery and preflight

`publicationModerationRepository.ts` now binds service calls to an accepted
operation, live work for fresh execution, and original provider tokens for late
completion. Ordered recovery never manufactures a successor. Terminal results
are consumed directly using `isActivePhotoWork` to distinguish execution
capabilities. `photoCohortPreflight.ts` prepares every verified
metadata-filtered JPEG/PNG before any future quota admission. Only a complete
cohort returns a handle; it retains bounded raw bytes and releases unselected
buffers before preparing one classifier per pass. The worker route remains
unconnected and gates stay false. See the
[repository contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-scoped-publication-moderation-repository).
