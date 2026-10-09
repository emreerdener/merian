# Observation analysis history

Private backend preparation for the
[reversible reanalysis RFC](../../../../../docs/rfcs/reversible-reanalysis-and-identification-history-2026-10-02.md).
This is not a live reanalysis or restoration API. Enrollment and selection
remain closed, existing scans are unchanged, and no endpoint calls the private
history selection transaction.

## Owners and bounds

`sourceDiscovery.ts` owns the prepared, non-wired source-discovery request and
closed response decoder. Its 2 KiB byte boundary and exact owner/parent/source
checks grant no admission or execution permission. The gated service-only SQL
resolver classifies bounded existing records. Separate default-false
service-only reader-11 routines own source reservation and unfunded retirement;
HTTP/native integration and ordinary activation remain pending. The initial
resolver never returns advisory absence. See the
[canonical prepared contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-discovery-contract)
and `sourceDiscovery_test.ts`; do not use existing funded admission as a lookup.

`sourceFingerprint.ts` prepares a versioned UTF-8 framing and SHA-256 contract
for fresh photo/audio source reservations, preserving the original request
digest and saved bytes. It grants no authority; the gated SQL reservation
validates the same fingerprint. The fixed golden vectors are shared with the
pure ungranted SQL encoders and native `ObservationSourceFingerprint` tests.
HTTP/native reservation integration remains separate; see the
[fingerprint contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-reservation-fingerprint).

`sourceReservation.ts` owns the prepared reader-11 reservation and explicit
unfunded-retirement contracts. It recomputes the fingerprint, freezes input
before await, and decodes exact owner-scoped receipts within 2 KiB. Held states
never expose a competitor; `retired_unfunded` cannot be confused with funded
execution retirement. Default-false service-only SQL routines implement the
contract; no HTTP/native consumer is connected. See the
[mutation wire contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-reservation-and-unfunded-retirement-wire);
retained bindings continue enforcing writer fences after terminal release.

`contract.ts` owns exact request identities, errors and bounded primitive
parsers. `transitions.ts` models selection and revision decisions; `result.ts`
reuses the canonical Identify and captured-media validators; `page.ts` binds
bounded pages and immutable snapshot bytes to the requested
observation/account/cursor. `authority.ts` binds evidence and review to the same
analysis before using the existing effective-identification policy. Pure
decision functions do not replace locked persistence, provider admission,
entitlement settlement, or authorization.

| Value                                    | Bound                                                 |
| ---------------------------------------- | ----------------------------------------------------- |
| Snapshot schema versions                 | 1, 2, imported saved-identification 3 and audio 4     |
| Explicit history reader protocols        | 7 (V1), 8 (V1/V2), 9 (V1/V2/V3), backend 10 (also V4) |
| History page                             | 1–20 entries, descending ordinal cursor               |
| Observation/review revision              | 0–2,147,483,646; exhaustion fails closed              |
| Result or evidence storage envelope      | 1 MiB each                                            |
| Review or active projection              | 32 KiB each                                           |
| Selection operation identity / receipt   | 2 KiB / 4 KiB                                         |
| Chat system input / assembled user input | 64 KiB / 128 KiB UTF-8                                |
| Serialized chat admission context        | 256 KiB                                               |

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
`get_owned_observation_analysis_page` RPC checks explicit protocol 7, 8, 9 or
10, the reader gate, current owner, parent and deletion fence before returning a
bounded page. Native `Core/Data/AnalysisHistory` decodes and admits these pages
only for an already-enrolled matching local owner; ordinary app sync never calls
it. Verified enrollment, live completion, held-task reconciliation (new native
requests now carry local account/origin provenance), child ingestion fences,
protected media, publication and chat integrations remain part of activation
qualification. The prepared October 5 account-retention materializer now retains
an explicit original scientific allowlist plus separate acknowledged scalar
facts in the ownerless scan, before private-history cascade. It copies no result
JSON and creates no current identification authority. See the
[canonical classification](../../../../../docs/backend-and-data/17-scientific-observation-retention.md);
all history gates remain disabled.

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

The private-evidence SQL cleanup facades now independently gate new retirement
and claims with `private_evidence_erasure_enabled=false`. One locked retirement
removes a whole exact expired unbound cohort (retaining its immutable
descriptor) or one noncohort receipt. Claims expose only opaque
object/token/expiry, and finish accepts the original unexpired token even after
the gate closes. The prepared `erase-observation-evidence` endpoint connects
these RPCs and propagates a shared deadline into private marker PUT/HEAD and
original-token settlement. It does not use the old batch helper, renew a claim,
provision a schedule or enable its gate. See the
[cleanup RPC contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-private-evidence-cleanup-rpcs).

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

The candidate-provenance backend checkpoint adds schema-2 `confirm_name` with an
analysis-scoped raw ordinal and fixed representation. Both phases validate
membership in the immutable species-candidate array; receipts preserve the
reference, and confirmation Undo validates the same association. Schema-1
requests replay unchanged. Rankless legacy and opaque imported candidates stay
unsupported. The native producer and existing alternatives-control wiring are
separate checkpoints; this changes no card layout or activation gate.

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
provider request is made by tests. The prepared moderation worker now calls the
adapter behind closed gates. Durable proof persistence, dispatch binding and
atomic output are prepared below; see the
[classifier contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-bound-photo-classifier-adapter).

## Prepared durable photo execution

`photoExecution.ts` persists the same adapter proof before dispatch and invokes
its frozen closure once. Only identical completion writes may retry. SQL now
requires proof before dispatch and bounded result/usage before completing a
decision, atomically and under deletion/authority locks.
`photoExecution_test.ts` covers failure ordering and pins the actual policy
digest to its migration. The SQL catalog and separate-session tests cover
proof/result replay and completion versus review/deletion. The scoped repository
and prepared moderation endpoint are now connected behind closed gates; no
recovery scheduler is connected. See the
[execution contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-durable-photo-execution-binding).

## Prepared public-photo storage

`publicPhotoContainer.ts` bounds and filters JPEG/PNG containers before
`publicPhotoStorage.ts` writes exact source bytes conditionally. Erasure retains
an empty permanent marker, preventing delayed conditional writes from restoring
origin content. Tests use only synthetic images and in-memory storage. SQL
allocation/cleanup owners are prepared below; the prepared erasure worker uses
`erase`, and the prepared copy worker below connects the scoped writer behind
closed gates. Origin markers do not prove cache revocation. See the
[storage contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-storage-boundary).

## Prepared public-photo staging ownership

Private SQL now reserves a permanent opaque-key cleanup obligation plus an
immutable source/lease receipt before the prepared writer runs. Staging
completion revalidates approval and authority; readiness cannot extend its
ten-minute cleanup deadline. The prepared copy worker below consumes the scoped
staging contract; the separate prepared erasure worker uses
`publicPhotoStorage.ts` to retain verified markers. Both remain undeployed and
unscheduled. See the
[staging contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-staging-lifecycle).

## Prepared atomic photo publication

The private SQL binder now admits a fresh community request and its entire
ordered approved photo cohort atomically. Immutable receipts support replay;
unshare/moderation/delete queue erasure, while health quarantine remains
reversible. The authenticated intake and service copy owner below connect this
boundary behind closed gates. See the
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
The scoped copy repository and service worker now connect this owner beneath
authenticated durable intake; `reconcile` requires durable operation-state
recovery, never automatic successor allocation. Activation remains disabled. See
the
[copy execution contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-copy-execution).

## Prepared durable publication intake

`request-observation-publication` now authenticates and persists exact ordered
consent before external work, returning an immutable acceptance receipt.
`publicationOperation.ts` owns strict parsing; the default-off service RPC and
private records preserve replay, original hash and deletion fences. Acceptance
never authorizes copying or means publication completed. Prepared
moderation/copy workers, owner status and native durable delivery are connected
behind closed activation gates; ordinary UI admission remains separate. See the
[intake contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-authenticated-publication-operation-intake).

New intake now rejects another operation UUID for the same observation after
checking exact replay first. This applies to every retained intake state,
including terminal needs-action; no automatic successor is authorized. The
service-only target lookup returns no intake, one original sanitized status or a
legacy-duplicate conflict under the owner/deletion lock. It never selects a
latest operation. `publicationTarget.ts` supplies the strict null-or-status HTTP
contract for the separate owner-authenticated target endpoint, after strict
validation of a non-null database envelope. Empty SDK success cannot become
vacancy. Native persistence has its own strict local occupancy guard; local
absence is not remote vacancy.

## Prepared publication worker ownership

Separate private work records now provide bounded discovery, scoped expiring
claims and gate-independent release/status beneath immutable intake. Only a
durable cohort receipt establishes historical admission; orchestration leases
confer no provider or public-copy authority. The execution gate remains false,
and prepared moderation/copy workers, owner status and native durable delivery
are connected; ordinary UI admission remains separate. Optional public notes
still require their own moderation boundary. See the
[worker contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-publication-operation-worker-ownership).

## Scoped moderation recovery and preflight

`publicationModerationRepository.ts` now binds service calls to an accepted
operation, live work for fresh execution, and original provider tokens for late
completion. Ordered recovery never manufactures a successor. Terminal results
are consumed directly using `isActivePhotoWork` to distinguish execution
capabilities. `photoCohortPreflight.ts` prepares every verified
metadata-filtered JPEG/PNG before any future quota admission. Only a complete
cohort returns a handle; it retains bounded raw bytes and releases unselected
buffers before preparing one classifier per pass. The prepared moderation worker
now uses this path; gates stay false. See the
[repository contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-scoped-publication-moderation-repository).

## Prepared photo moderation settlement

The service finalizer derives immutable outcomes from source-ordered durable
attempts and removes moderation work atomically. Active attempts retain late
completion ownership; rejected, unknown or cancelled work cannot automatically
restart. `photos_approved` does not approve notes or containers and is not
public admission. A separate copy phase remains required.

See the
[outcome contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-durable-photo-moderation-outcomes).

## October 4: prepared bounded photo moderation worker

`moderate-publication-photos` now connects service authentication, durable
claims, recovery, finalization and one verified provider execution. Gates stay
false and no scheduler is added. Shared request/provider deadlines preserve
completion time and never turn uncertainty into a retry or refund. Copy/binding,
exact-note moderation and native operations remain separate. Worker
handler/repository and classifier deadline tests cover recovery-first ordering,
preflight before quota, lost dispatch/completion, stalled response cancellation
and scoped denial.

## Prepared separate copy recovery stage

Approved photo outcomes now seed private copy work with a distinct token and
exact ordered causal-leaf cohort. The four service-only recovery RPCs add no
storage, provider or binding authority. Gates remain false. The prepared copy
owner below consumes current-authority checks and fixed staging deadlines,
performs targeted cohort cleanup and settles nonnull notes as needs-action. See
the
[canonical copy recovery contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-publication-copy-recovery-ownership).

## Prepared atomic copy cohort reservation

A separate default-false reservation gate now protects atomic allocation of the
exact approved no-note cohort under one immutable expiry. Scoped completion
rechecks current authority; historical publication recovery precedes cleanup,
and abandonment queues all unbound siblings without itself granting erasure.
Private receipts cascade on deletion while registry cleanup survives. The
prepared copy worker and scoped binder below consume this reservation behind
closed gates. See the
[canonical reservation contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-atomic-publication-copy-reservation).

## Prepared scoped copy repository

`publicationCopyRepository.ts` now binds the SQL reservation, recovery,
completion and abandonment boundary to the existing copy executor through the
dedicated `publicationCopyExecution.ts` coordinator. It freezes the exact
cohort, validates common expiry and private lease identities, propagates shared
deadlines and checks historical publication before cleanup. The prepared copy
worker and scoped binder below consume this coordinator; activation remains
held. See the
[repository contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-scoped-publication-copy-repository).

## Prepared reserved-cohort binding

A new service facade fences publication to the exact approved ordered
reservation and revalidates current authority. Historical receipt recovery
precedes work/gate checks and still verifies the reservation. Mismatches roll
back every publication write. The independent binding gate stays false; no Edge
worker or activation is added. See the
[binding contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-exact-reserved-cohort-binding).

## Prepared bounded copy operation

The prepared operation controller connects whole-cohort private verification,
sequential scoped copies, exact binding and targeted cleanup under one shared
110-second deadline, reserving time for recovery. It spends no provider quota
and does not infer terminal failure from transport uncertainty. HTTP worker
admission, durable copy outcomes and activation remain pending. See the
[controller contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-bounded-copy-operation-controller).

## Prepared durable copy outcomes

A separate private immutable outcome now records unapproved notes or original
staging expiry, retires copy work and preserves provider approval. Historical
publication wins; private cleanup IDs still require registry claims. Owner
status exposes only the existing needs-action state. Settlement has its own
closed gate; no worker or activation is added. See the
[copy outcome contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-durable-copy-needs-action-outcomes).

## Unsupported source types

`publicationModerationRepository.finalize()` recognizes the strict
`unsupported_source_type` needs-action receipt. SQL can derive it from immutable
non-JPEG/PNG source metadata only before any provider attempt, under its
independent default-false gate. The worker consumes it before preflight. This
does not classify byte/container failures: those use the separate verified
source-bound attestation below. No provider or complimentary quota changes,
implicit retries, or copy-work creation occur.

## Verified-container rejection ownership

`PublicPhotoContainerRejected` marks only deliberate policy rejection.
`preparePublicationPhotoCohort` creates a frozen
`PublicationPhotoCohortContainerRejection` only after verified exact bytes and
live-signal checks; an error thrown by a transport cannot spoof that path.
`publicationModerationRepository.rejectContainer` checks the frozen original
source and uses the bounded service finalizer. Immutable source/policy
attestation and zero-attempt needs-action settlement never authorize provider
retries or copy work. Unknown errors remain recoverable. Policy changes require
a new attestation version; no raw bytes or diagnostics are persisted.

## Copy service integration

The prepared `copy-publication-photos` owner finalizes durable copy outcomes
before `executePublicationCopyOperation`, passes original expiry and a shared
deadline, and reserves the full controller and release windows. Targeted
registry claims remain mandatory; public marker erasure now accepts a parent
signal for PUT and HEAD. Historical publication avoids cleanup and optional
notes cannot reach the no-note binder. Activation requires recurring independent
erasure and backlog/CDN evidence; terminal expiry removes copy work and cannot
retry failed cleanup itself.

## Prepared owner publication status

`get-observation-publication-status` now exposes only the existing five-field
owner status for an exact saved operation. Auth-derived ownership, deletion
fences, strict decoding, bounded reads and private no-store apply. Historical
admission is not current visibility. No private reason, media or post ID is
returned. Native durable delivery recovers this status before exact admission
and remains status-only after acknowledgement. Ordinary UI admission and
activation remain separate. See the
[status contract](../../../../../docs/backend-and-data/05-api-contracts.md#owner-publication-operation-status).

### Consent preflight

`publicationConsent.ts` owns the closed dedicated preflight request/snapshot. It
reuses protected V2 metadata bounds, preserves candidate order and exposes no
operation or object identity. The endpoint and shared locked SQL eligibility are
described in the
[API contract](../../../../../docs/backend-and-data/05-api-contracts.md#owner-publication-consent-preflight).
These candidates are descriptive; exact selected receipt readiness remains an
admission check. Existing history and operation-status contracts stay closed.

### Authenticated private upload producer

[`upload-observation-evidence`](../../upload-observation-evidence/README.md) now
owns bounded raw-byte ingestion for 1–5 JPEG/PNG photos, up to 5 MiB total. It
reserves the complete ordered cohort before conditional writes, verifies all
returned receipts before I/O, and propagates one deadline through `writeOnce`
and database completion. Immutable private cohort metadata survives receipt
expiry so an old analysis cannot acquire new consent or a renewed deadline. The
legacy per-item helper alone is not an authenticated upload boundary. Native
capture/queue integration, bucket qualification and independent erasure remain
activation prerequisites; all flags stay false.

## Execution recovery and retirement contracts

`executionStatus.ts` strictly decodes the owner-bound seven-field status read.
`executionRetirement.ts` owns the exact original execution identity plus a
retained retirement operation UUID and the matching `retired_before_dispatch`
receipt. Neither decoder creates authority. Status `absent` or `failed_terminal`
cannot substitute for a retirement receipt.

The prepared service-only retirement routine requires the authenticated Edge
owner boundary, separately held until its HTTP owner is connected. It verifies
never-dispatched admitted state and exact reserved funding under canonical
locks, revokes live work and saves settlement, private erasure and receipt
atomically. Unknown dispatch is denied without refund or successor. Native
persistence/action integration and absent-operation seals are separate work; all
activation gates remain false.

The prepared `retire-observation-analysis` HTTP owner authenticates the user,
then invokes the service-only retirement routine with the strict contract above.
Its scoped five-second/4-KiB transport is separate from ordinary clients. No
HTTP failure supplies retirement proof or provider execution permission. Native
durable retirement and activation remain separate.

## Gated audio admission and result readers

`audioManifest.ts` validates manifest-3 metadata for one WAV reference plus
ordered descriptions. `audioContainer.ts` verifies the complete bounded PCM16
mono 44.1 kHz container without transforming bytes. The separate default-off
[`upload-observation-audio`](../../upload-observation-audio/README.md) route
owns binary ingress, digest computation and immutable cohort readiness. Photo
receipts and V2 request replay keep their existing contracts.

`audioAdmission.ts` owns closed input 3, history capability 9 and Gemini. The
executable parser and gated SQL admission now accept it with the server-selected
`multimodal_audio_v1` profile. `audioMaterialization.ts` binds the exact
receipt, rechecks owned bytes/container/digest, and preserves description/audio
ordering. Execution captures a durable outcome before taxonomy and append; saved
outcome recovery never invokes the provider again. The new
`audio_analysis_enabled` gate defaults false independently of upload readiness.

Audio manifest 3 has `items`; imported manifest 3 has the saved-identification
sentinel. Audio results use outer snapshot 4. TypeScript page/state reader 10
accepts both, while SQL refuses the entire audio-containing history to readers
7–9 even when a cursor or explicit target would otherwise hide the audio row.
The
[canonical API contract](../../../../../docs/backend-and-data/05-api-contracts.md#gated-audio-execution-and-reader-10)
owns compatibility and expiry semantics. Native reader-10 types, mutation RPC
compatibility and durable audio production/delivery remain subsequent work;
current native readers remain 9. No ordinary route or rollout is enabled.

## Prepared source binding storage

Private SQL binding/occupancy tables now prepare durable source coordination. No
callable reservation or release routine, HTTP transport or native consumer is
connected. Their metadata does not grant upload, funding or execution authority.
The
[storage boundary](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-binding-storage-boundary)
distinguishes this groundwork from required all-writer reservation, terminal
release and legacy replay coordination.

Legacy scan/job/intent child-identity writes now reject bound UUID reuse under
owner-before-child locks, including UUID aliases and cross-owner attempts. This
storage-integrity prerequisite requires Read Committed visibility (including
PostgreSQL's equivalent Read Uncommitted); frozen transaction snapshots fail
explicitly. It does not open reservation, admission, funding or execution.

The deny-only funding prerequisite also fences bound original analysis IDs at
quota admission and fresh invocation commitment. Existing invocation replay is
non-dispatching; quota request IDs remain separate idempotency identities. See
[funding exclusion](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-bound-funding-exclusion).

## Prepared exact source validation

Private SQL helpers now share canonical source locking and validate complete
saved input, recomputed fingerprint and live occupancy. They grant no admission
or dispatch and are unavailable to API roles. Existing writers remain unchanged
until coordinated cohort/admission/funding/execution cutover; terminal replay
must precede live-binding validation. See the
[exact validation contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-exact-source-validation).

## Prepared immutable cohort source links

Private photo/audio cohorts can retain a same-child source-binding link and an
exact ordered media projection. Current RPCs still create legacy NULL links;
there is no new upload/admission authority or backfill. Existing cohort update
guards prohibit changing either form, and deletion cascades preserve the parent
lifecycle. See the
[source-link contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-immutable-cohort-source-links).

## Prepared source-bound intent fence

A private intent insert backstop now requires the exact binding/input/occupancy/
linked-cohort chain for source-bound children. It runs before existing evidence
checks, with child-ingestion before child-evidence locks and current statement
snapshots. Unbound legacy behavior remains; source-bound funding and dispatch
still deny unconditionally. See the
[intent fence contract](../../../../../docs/backend-and-data/05-api-contracts.md#prepared-source-bound-intent-fence).

### Source-aware evidence writers

Migration `20261008203348_bind_source_evidence_writers.sql` connects existing
photo/audio cohort reservation and raw receipt reservation/completion to the
private source entry helper. A bound child requires exact live binding and
occupancy under owner/parent → source → child ingestion → child evidence locks.
New cohorts preserve the binding link and exact ordered photo or single-audio
projection. Existing NULL-linked cohorts never upgrade. Receipt allocation and
completion also validate the linked chain; existing expiry, readiness and object
identity rules remain unchanged. No quota, intent or provider grant is created.

An apparently unbound caller takes child locks then rereads the binding table.
If a binding appeared while waiting, it fails instead of acquiring a source lock
late. Conversely, a committed legacy cohort makes a later binding fail its
existing no-retrofit namespace check. These writers require read committed/read
uncommitted isolation; repeatable-read and serializable snapshots fail closed,
including for unbound requests. Legacy saved photo/audio replay retains its
original receipt, object and deadline under supported isolation.

This is closed bound-branch preparation, not all-writer cutover. Atomic source
reservation, exact retirement and coordinated admission/funding/execution remain
required before a new source API can open. No grant, rollout gate, wire field or
ordinary route is added; existing activation holds remain.

### Source-bound initial admission

Migration `20261008210355_prepare_source_bound_initial_admission.sql` connects
fresh bound V2/V3 admission to source-before-child/intent locking and narrows
the quota exclusion for exactly one initial funding transaction. The admission
context must match owner/child; operation, original child, request ID and
protocol constants must match. The private intent must be admitted with no saved
quota, work claim, outcome, invocation, draft, result, retirement or prior
accounting. Exact live binding, input fingerprint, occupancy and linked media
projection are mandatory. A context setting alone is insufficient.

The current eleven-argument identification quota wrapper also compares its
profile, processor permission and identification protocol with the immutable
input. Mismatch rolls back the transaction. Older identification quota overloads
and the eight-argument generic quota wrapper reject bound children before and
after their core call; unbound callers retain their existing behavior. No new
public signature or privilege is introduced.

A recorded bound intent is recovered under owner/parent authorization before
live occupancy, evidence expiry and fresh gates. Its original input and quota
identity must validate. Even an admitted replay returns that saved quota; it
never invokes generic quota reservation again. Expired, refunded or pruned quota
therefore cannot mint another lease or attempt. Missing/malformed saved quota
holds rather than funding. Deletion still wins. Recovery is not dispatch
permission and does not select or alter an analysis.

This is admission-only preparation. The source-bound invocation exclusion stays
unconditional; no provider may start through this checkpoint. Atomic source
reservation, terminal release/retirement and the coordinated execution cutover
remain required before source access opens. All activation gates remain false.

Admission, including saved receipt replay, requires read-committed or
read-uncommitted isolation before any source existence lookup. Repeatable-read
and serializable calls fail closed with
`analysis_history_current_snapshot_required`; a frozen snapshot cannot hide a
committed deletion. Saved quota replay does not assert that its original lease
is still live.

### Source execution lock preparation

Migration `20261008213302_prepare_source_execution_lock_order.sql` installs a
private entry helper before intent row locks in claim/recovery, dispatch, draft
recording, completion, failure and the public work-advance owner. V2/V3 append
uses the same ordering before its own result/child locks. Supported isolation is
read committed/read uncommitted. Owner/deletion authorization precedes binding
inspection; bound work takes source, child ingestion and child evidence locks,
then verifies immutable saved-intent input/fingerprint association.

This helper establishes identity and lock order without requiring live
occupancy, media rows or unexpired uploads. Existing operation-specific token,
payload and receipt checks still apply. Apparently unbound calls take child
locks and reread binding absence; a binding committed during the wait holds
instead of acquiring a source lock late. Unbound behavior is preserved under
supported isolation.

This is lock preparation, not execution authority. Source-bound invocation
remains denied. Original-quota dispatch proof and atomic retirement/release
remain separate coordinated checkpoints before source access opens. No public
signature, grant, gate or provider successor is introduced.

### Source-bound generic accounting holds

Migration `20261008220335_hold_source_bound_generic_quota_cleanup.sql` closes
inherited generic accounting paths before source execution opens. The public
quota finalizer rejects bound children even with a matching provider context;
generic expiry refund and terminal quota pruning skip bound children while
continuing unrelated cleanup. No schedule is created, changed or enabled.
Generic failure/cancellation and fresh funded retirement hold; exact existing
terminal/retirement receipt replay remains before the new holds. Unbound
finalization retains its existing isolation behavior.

Parent deletion retains a separate private refund path only for the exact unused
original reservation, owner, child, request, lease and attempt. A live-parent
intent deletion is not that proof. Known invocation/outcome/result evidence
prevents refund; deletion still erases the intent. The unused-work proof applies
to all admitted intent erasure because source bindings may be removed earlier in
the same deletion transaction. Other unbound accounting behavior remains
unchanged under supported isolation. Immutable binding and occupancy are not
released by generic accounting cleanup.

Atomic source retirement/release and original-grant dispatch remain required.
Until their reviewed durable proofs exist, bound quota records intentionally
stay held instead of being expired, pruned or treated as permission for another
provider call. Activation gates remain false and ordinary access remains nil.

### Source dispatch witness preparation

Migration `20261008222349_prepare_source_dispatch_witness.sql` adds
default-false `source_dispatch_enabled`. Fresh bound dispatch requires the
existing modality, admission, append and dispatch gates, current consent, exact
live source/input/ occupancy/media chain and the original reserved quota,
request, child, lease and attempt. The assigned input profile must match the
immutable input and saved quota. Canonical owner/parent/source/child/intent
locks precede quota locking.

A private immutable intent-owned witness records original reservation, lease
digest, attempt, source fingerprint, provenance and creating transaction. The
invocation writer accepts it only in that transaction; finalization and
invocation insertion are atomic with the witness and intent transition. A
retained witness is audit evidence, never reusable dispatch authority. Exact
invocation replay continues to return `may_dispatch=false` before fresh gates.
Generic quota finalization remains held. No new public signature or grant is
introduced.

Witnesses have no quota foreign key and cannot disappear through quota pruning.
They cascade with intent deletion; the unused-reservation erasure proof rejects
any witness before that cascade, including an interrupted/tampered partial
state. Binding deletion therefore cannot hide dispatch evidence and permit a
refund. Account merge remains held by the existing bound-source guard. Atomic
retirement and source release remain separate work before source access opens.
All activation gates remain disabled; uncertain execution permits recovery and
reconciliation only, never a successor provider invocation.

Fresh invocation also checks the permanent child deletion tombstone after its
child lock. Once deletion erases binding, intent and witness, a held reservation
cannot fall through to generic dispatch. Existing invocation replay remains
non-dispatching.

### Atomic source-bound funded retirement

Migration `20261008223804_prepare_atomic_source_execution_retirement.sql` adds
default-false `source_retirement_enabled` alongside the existing retirement API
gate. The existing request, receipt and reader9/10 compatibility are unchanged.
Read-committed/read-uncommitted isolation is required before ownership locks or
receipt replay; frozen snapshots fail closed. Owner/deletion and reader checks
still precede exact receipt recovery. That recovery needs neither live occupancy
nor the original quota row and does not create another operation.

Fresh retirement uses the live source-before-child lock helper before intent and
quota locks. Apparently unbound callers reread binding absence after child
locks. The bound input/source must match the saved intent, and a dispatch
witness blocks retirement even if accounting still appears reserved. Existing
exact unused-work, original reservation/lease/attempt and complimentary-credit
proofs remain. A live worker claim is revoked atomically; it is not itself
evidence of provider dispatch. Expired original leases may retire only when
those unused-work proofs hold.

Application atomically refunds through the private quota core, settles the held
complimentary allocation, writes terminal `retired_before_dispatch` state and
its permanent receipt, then deletes only the matching occupancy. The storage
trigger requires the complete binding/input/fingerprint, terminal intent, exact
receipt, refunded original quota and absence of witness/invocation/result before
permitting that live-parent occupancy deletion. Any failure rolls back all of
these changes. Immutable binding and dispatch-witness deletion rules remain
unchanged. Generic quota cleanup is still held and cannot release occupancy.

This is a closed funded-retirement capability, not source API activation. Source
reservation, unfunded retirement, native consumption and remaining media
acceptance remain separate. No new public signature, privilege, provider retry
or uncertain refund is introduced. All activation gates stay disabled.

### Source reservation terminal replay contract

The
[canonical terminal replay and successor contract](../../../../../docs/backend-and-data/05-api-contracts.md#source-reservation-terminal-replay-and-successor-admission)
requires binding plus live occupancy for `reserved`. An exact terminal child
with proven release conflicts; it never recreates occupancy. Errors cannot
substitute for durable terminal proof or authorize a new UUID. A new child needs
complete bounded predecessor/namespace verification. The first paired SQL
implementation supports only exact funded/unfunded retirement predecessors;
completion-based occupancy release remains an explicit separate implementation
requirement. Migration `20261009000303` implements the paired service-only
reader-11 reservation and unfunded-retirement routines behind independent
default-false gates. The immutable unfunded receipt is unique per child and
follows binding/parent deletion; terminal replay never recreates occupancy. No
HTTP/native consumer or activation is introduced.

Source-admission database concurrency fixtures derive a stable synthetic IP hash
from each synthetic owner. Duplicate calls for that owner retain the same
bucket; unrelated owners do not consume a shared suite-wide IP limit. This
isolation belongs only to test fixtures and does not change production quota
policy.
