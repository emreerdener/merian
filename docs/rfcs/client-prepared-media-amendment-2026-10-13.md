# CPM-1: client-prepared media amendment to IC-1

Status: October 13, 2026. **Draft for independent and IC-1 review.** The user
authorized evaluation and drafting, not implementation or contract adoption.
Proposed semantic revision: **CPM-1, revision 2**, a candidate IC-1 revision 4
amendment for fresh submissions. Executable protocol numbers and schemas are not
allocated by this document. Baseline:
`d97517928cab96811ba5d1c453feb67b77c34dc9`; source findings describe the shared
checkout, including unrelated native edits.

AWS remains unapproved. No infrastructure, provider call, installed run, schema
change or activation is authorized. History primary remains sole writer; IC-1
and independent reviewers remain read-only. The hardening automation stays
paused. Broader hardening, Field Trip and capture visual work stay separate.

## Evaluation and recommendation

Recommend evaluating **server-verified submitted bytes, prepared on iOS** as the
fresh-input contract before choosing a server decoder worker. The
[alpha acceptance matrix](identification-history-alpha-readiness-2026-10-11.md#capability-and-evidence-matrix)
requires immutable media/context, correct original operation and funding, exact
recovery, private retention and complete history. Those properties do not by
themselves require server reproduction of the client's transformation.

The later
[pre-admission preparation](initial-pre-admission-preparation-2026-10-11.md),
[structural attestation](initial-media-structure-attestation-2026-10-13.md) and
[S0 dispatch](initial-dispatch-fence-interface-2026-10-13.md) agreements do
require qualified server transform/derivation evidence. CPM-1 proposes replacing
that prerequisite **only for a distinctly versioned fresh branch**. It cannot be
implemented by weakening the checks on an existing receipt or profile.

The tradeoff is explicit: a modified client can submit frames unrelated to its
claimed video or audio inconsistent with its claimed preparation recipe. The
server verifies ownership and actual submitted bytes, not capture authenticity,
faithful extraction or safe full decoding. Client preparation metadata is a
claim. This is acceptable only if the product accepts that reduced assurance;
review concurrence alone does not constitute that product decision.

The current roadmap's phrases "media provenance", "exact media binding" and
"verified binding" would mean verified source identity, ordered submitted
package identity and exact provider-input binding for CPM-1. They would not mean
verified derivation. No matrix row is marked qualified by this proposal.

## Current implementation evidence

Read-only native and backend traces identify reusable mechanisms and concrete
gaps. The candidate evidence manifest binds exact source hashes separately from
the document; no current runtime qualification is claimed for CPM-1.

- `OfflineQueueManager+CaptureEnqueue.swift:enqueueCapture` and
  `OfflineCaptureFileStore` already copy inference/display files, audio and
  video into queue ownership before clearing a successful draft. This is useful
  durability, but there is no complete versioned package manifest joining every
  final AI-input digest to admission, upload and dispatch.
- `CaptureSubmissionPayload.init` separates sampled inference frames from the
  retained playback clip and optional companion WAV. `IdentifyVisualMediaItem`
  clip/frame indices express client lineage, not extraction proof.
- Current still retention is derivative-only. `StagedImage` holds compressed
  inference and display bytes; its `original` image is UI/crop lineage, not a
  durable original-byte file. The camera saves `captureData` to the photo
  library separately. `OfflineCaptureFileStore.makeCapturedMediaJSON` uses
  display filenames, and inference completion adopts that display snapshot.
  CPM-1 source export/reanalysis therefore needs a distinct durable original
  source copy; existing display or inference images cannot be relabelled as
  originals. Photo-library presence is not queue ownership or durable recovery.
- `MediaStagingContract.uploadItems` validates file size/type/count and performs
  WAV inspection. Signing binds length/type/key, not a complete immutable
  package digest. A changed same-length file is not excluded by those checks.
  `OfflineQueueManager+InferenceDispatch.swift:buildInferenceDownloadRequest`
  constructs references from persisted keys; those references do not establish
  exact provider consumption.
- `ObservationReanalysisFileStore.withVerifiedFiles` has stronger hash/set and
  container checks; video has separate preparation/retention owners. Reuse
  suitable mechanisms, but do not claim the initial queue already inherits those
  guarantees or alter saved reanalysis records in place.
- `_shared/initialAnalysis/preparationExecution.ts:runInitialPreparation` and
  `preparationExecutionContract.ts` bind source verification, a fresh transform
  grant, output/resolved manifests and outcome. Migration
  `20261012041337_prepare_initial_atomic_admission.sql` retains that chain in
  the original admitted proof. CPM-1 needs distinct consuming versions, not a
  caller-controlled switch that bypasses this chain.
- `_shared/initialAnalysis/mediaHandoffStorage.ts` already implements bounded
  exact copy and readback checks on length/type/digest, with redirects and
  substitution rejected. Its old proof and physical qualification limitations
  still apply; reusable byte-copy logic is not automatic new-protocol
  acceptance.
- Live `identify/index.ts` accepts inline image input as well as R2 references,
  and `identify/provider.ts:buildVisionAIRequest` consumes the selected list.
  The CPM-1 dispatch adapter must reject these alternate caller-selected media
  paths and construct provider evidence solely from the admitted package.
- `_shared/ai/identificationUsage.ts:prepareAccountedIdentification` owns the
  existing fresh accounted invocation boundary. CPM-1 must integrate with the
  reviewed original owners, not introduce another counter, token or retry loop.

Native photo crop/reencoding and video frame/audio preparation remain current
behavior, not proof of a new recipe. In particular, the current native 44.1 kHz
companion WAV and existing backend audio preprocessing cannot be assumed to
produce the same final bytes. The next functional agreement must establish
client output compatible with each retained provider profile or leave that
profile unsupported for CPM-1; it cannot silently remove required processing.

## Proposed invariant and version boundary

For initial identification the logical operation remains `(owner_id, scan_id)`,
`operation_id = scan_id`, with existing cross-route and permanent content-free
reuse fences. A reanalysis keeps its existing distinct durable analysis request
identity, source analysis/version and observation identity under the
[history identity contract](reversible-reanalysis-and-identification-history-2026-10-02.md);
it must not reuse the observation's scan ID as a new inference request. Package
binding extends each existing owner, not a second logical namespace. A new
contract discriminator, provisionally named `client_prepared_media_v1`, must be
explicit in fresh negotiation, private saved input, admission, media receipts,
dispatch/result/completion correlation and durable native recovery. Its exact
wire encoding, canonicalization domain and numeric versions require the next
reviewed schema agreement; this name is not an implemented API.

Selection is server-owned and fail-closed. A client declaration alone cannot
select an eligible profile, inference provider, transform bypass or funding
exception. An unsupported client/server combination rejects fresh submission
without routing through a historical codec. The new branch must never satisfy
old server-execution proof fields with nulls, invented digests or client claims.

Three asset roles have different meanings:

- **Retained sources:** the exact photo/audio/video assets selected for this
  operation, including owned original source-version references for reanalysis.
  Original bytes must be copied from the selected/captured source into explicit
  package ownership before destructive draft cleanup. This is a byte-retention
  claim, not a claim of sensor authenticity. Current inference/display
  derivatives or an external Photos reference are not a substitute.
- **AI input cohort:** the exact ordered binary objects and text that the
  provider adapter will submit. For frame-based video, the raw clip is retained
  as source while submitted frames and optional companion audio are the AI
  evidence. The record must say which assets the provider actually received.
- **Display derivatives:** previews or display/share assets retained for their
  own purpose. They are not silently exported as originals or used to make
  missing-source reanalysis eligible. Any derivative export must be explicitly
  identified as such under its separate supported action.

The immutable **native package content identity** binds logical asset
identity/role, byte length, SHA-256, declared content type, order, associations
and exact text/options. It is computable before server allocation and contains
no server object generations or assignment digest. The separate immutable
**server package binding** binds that content identity to approved content
types, allocated object IDs/generations, verified tuples and authoritative
assignment. Both have distinct canonicalization/digest domains and exact replay
comparison. Server allocation never mutates the native manifest or creates a
circular package digest. Before verification the allocation binding is a fixed
expected mapping, not a claim that bytes already exist or have been verified.
Input order, source association and multiplicity are explicit; equal hashes do
not authorize dropping or reordering repeated input. The same object may serve
as both source and AI input only under an explicit compatible role mapping. Text
is frozen in accepted order and exact canonical form, distinct from later
editable field notes. Package identity also binds contract/profile version,
client-reported preparation recipe/options, source-version fingerprint and
provenance assurance. The server recomputes identity; client digests are claims
until checked against all retained bytes.

The server separately freezes its complete authoritative inference assignment
before source upload: provider/model, prompt/schema/configuration, consent and
policy revisions, execution/fallback behavior and compatible input options.
Final admission compares that saved assignment before funding as today. The
client recipe does not replace it. Incompatible or revoked saved configuration
holds; current defaults cannot silently rewrite the package or assignment.

## Fresh submission and recovery

1. iOS prepares a package using a supported, bounded native recipe and writes
   complete source and AI-input files plus their manifest durably before network
   submission. An atomic package-commit marker distinguishes a complete package
   from an interrupted write. The committed package is immutable.
2. The server creates a versioned unfunded intent under the same operation
   fence, resolves/fixes the authoritative compatible assignment, binds the
   complete package declaration and allocates fixed owner-controlled upload
   destinations. Any uncertain create recovers this identity before proceeding.
3. Upload only the committed exact bytes. Lost acknowledgements reconcile the
   original destination; never replace its bytes or choose a new operation to
   escape uncertainty. Trusted backend verification reads bounded complete
   bytes, checks ownership, generation, length, digest, roles and the qualified
   input-admissibility policy. It produces a new **byte-verification receipt**,
   not a transform or derivation attestation.
4. Atomic admission binds that receipt, immutable package and original funding
   through the existing accounting owners. This branch issues no server media
   transform grant. No client preparation event is a scan-token charge or a
   provider authorization. Complete M1/M2 copy/retention and handoff equivalents
   must be versioned explicitly; current v2 proofs are not silently reusable.
5. The dispatch compositor resolves only the frozen AI-input cohort, checks the
   exact owned retained objects and assignment, and binds any provider-file
   receipt to the uploaded tuple. Prompt/request serialization consumes exactly
   that ordered package and its saved options. Then the original fresh provider
   grant, quota/invocation fence, durable result and atomic completion owners
   apply. Client request overrides or later native edits cannot affect dispatch.
6. History records source references, submitted AI evidence, immutable text,
   assurance/version and the original result/completion receipt. These remain
   private under existing erasure and projection rules.

Transport encoding and provider-internal decoding are distinct from Merian
changing the input. CPM-1 makes no claim about a provider's hidden transforms.
Any Merian resize, crop, resampling, audio boost, frame extraction, media
omission or reorder after package freeze violates this branch unless the final
bytes were separately frozen and verified before admission. It is not enough to
bind source hashes while allowing a live adapter to transform them.

Provider asset creation also needs an explicit bounded phase, original consent,
stable asset-to-byte receipt, cleanup and uncertainty policy. An uncertain file
upload must not cause blind reupload, another inference, a new funding identity
or an inferred refund. The next adapter agreement must prove its exact behavior;
this draft does not claim that existing provider-file helpers already do so.

On native restart, read the committed manifest and verify its files. If missing
or inconsistent, preserve the draft and perform original server status recovery
first whenever any server contact may have occurred. A server-retained complete
package can supply exact bytes through authorized delivery. Missing package
bytes cannot be recreated by silently rerunning preparation, even when the
source survives. Before any server intent exists, explicit user editing may
create a new local package only with positive proof that no create could still
commit: either no server contact occurred, or a durable server terminal/unused
transition serialized with every outstanding create. A missing acknowledgement
or one status-not-found response is insufficient. After an intent exists,
remediation must preserve the frozen operation and use a separately reviewed
positive terminal/unused transition before any explicit fresh operation. Unknown
never means absent.

Unsupported or unavailable media blocks submission with a bounded reason and
preserved draft. Locally queued historical text-only work requires explicit
media remediation. Historical text records and already-admitted operations keep
their original input, route, receipts and recovery meaning. No automatic
migration, recipe substitution or new invocation is permitted.

### Unfunded storage admission, expiry and erasure

Intent allocation requires an atomic server-owned capacity reservation under
owner and global abuse controls: finite simultaneous intents, object count,
per-role and total bytes, and rate limits. It is a storage reservation, not a
scan token, entitlement or provider grant. Reuse the preparation registry's
capacity and terminal owners where compatible, with an explicitly versioned
state transition and effective caller/lock inventory.

Freeze one nonrenewable deadline when allocating the intent and exact upload
destinations. Signing lifetimes never extend it. The concrete values and full
cohort budgets must be fixed in the next schema agreement before implementation;
no unbounded or auto-renewed lease is permitted. Allocation/readback/admission
must recheck live ownership, capacity, deadline and deletion/retirement fences.
Abandonment, account/scan deletion, explicit cancellation or expiry serializes
against allocation and admission, retires every allocated fixed ID before
private evidence erasure, and leaves the content-free operation fence.

Unknown PUTs reconcile original destinations only. A request accepted before URL
expiry may still complete after retirement. Keep tombstones and cleanup duties
for those IDs, deny admission/funding from late bytes, and repeatedly reconcile
authorized erasure until the original writes are terminal or a qualified backend
completion bound plus absence proves closure. URL expiry or one empty read alone
cannot release physical-storage accounting or erase cleanup obligations. Free
capacity only under that proven accounting transition; reserve headroom for
in-flight/late bytes. Cleanup has deterministic ownership, bounded work and no
decoder, funding or execution authority. Read-only status and required erasure
continue after the write/admission deadline; automatic reupload, reminting or
another provider invocation does not.

Required vectors include abandoned intent expiry, concurrent cap exhaustion,
late create after a not-found read and local edit, deletion during allocation
and upload, unknown partial PUT, late accepted PUT after retirement, both
admission/expiry orders, and capacity release only after proven terminal
cleanup.

## Bounded server handling remains mandatory

CPM-1 removes server transformation and independent derivation proof, not input
security. Before eligibility, fix and qualify a finite admissibility profile:
accepted formats, per-role and aggregate byte/count limits, bounded signature
and container-framing checks, stream/chunk/time/memory budgets, MIME
consistency, and opaque storage/delivery behavior. Current cohort and role
limits are the starting ceiling; no expanded media or reduced product limits are
approved. Retaining original still bytes adds a real source-size and storage
requirement beyond the current derivative-only queue. Qualify that envelope
explicitly; do not shrink originals, increase accepted limits or exclude
currently supported captures silently to make the proposal fit. Historical
records without original bytes retain their meaning and report source
unavailability rather than acquire fabricated originals.

The server must reject empty/text-only inputs and obvious content/type/framing
mismatches. Hash or MIME equality alone is not media validation. A bounded
inspector need not fully decode or prove every pixel/sample is valid; thus some
malformed media may pass intake and later be rejected by the provider. That is a
known trust limitation, with the existing original-operation failure and
accounting policy, not a basis for a fallback invocation or automatic refund.
Client dimensions, duration, codec claims and recipe labels cannot prove safe
expansion. Any component that actually decodes must have its own qualified
resource boundary. No unqualified thumbnailer, parser or metadata extractor may
be hidden in the ostensibly opaque copy path.

Direct bounded byte reads and verified hashes must refer to the same immutable
object generations subsequently consumed. Reject request-selected remote URLs,
mutable aliases and foreign assets. A provider URL fetch needs protected
delivery of the exact immutable object; an upload receipt must bind the actual
bytes sent. If an existing backend cannot prove these bounded paths, CPM-1 stays
blocked pending a narrower implementation or a justified worker decision.

## Source-bound reanalysis and follow-up actions

Reanalysis stays tied to the explicitly selected analysis version and its
retained original media, including video. Resolve live ownership, source
fingerprint and availability before freezing a new child package. A surviving
thumbnail, another version's derivative or an unrelated frame is not an
automatic replacement for missing original media. Explicit replacement follows
the reviewed source-change contract and cannot mutate an admitted child.

Reusing an original does not require a new capture. A supported client recipe
may prepare a new child's AI cohort from that retained source before the new
package is frozen. The linkage is verified as source identity and recorded as
client-claimed derivation, not falsely promoted to server-proven extraction.
Immutable submitted context belongs to that child; mutable field notes remain
separate. No video publication/review authority is added.

Individual-version deletion and media export remain later milestones. Retain
source and submitted-evidence relationships while live owners need them;
deletion cannot cascade into surviving versions or resurrect erased private
content. Export resolves the retained selected source, never labels a submitted
frame or thumbnail as the raw original. Qualification must include legacy
versions whose originals are missing, cross-version holds and unknown
operations.

## Acceptance matrix disposition

Every row below remains at its existing evidence status. "Preserve" means the
requirement survives, not that current tests establish CPM-1 acceptance.

| Row                                 | Disposition                   | CPM-1 pass condition or remaining gap                                                                                                                                                                           |
| ----------------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A0 foundation/parity                | Preserve                      | Existing checkpoints remain historical scoped evidence; changed consumers need new validation.                                                                                                                  |
| A1 IC-1 agreement                   | Amend explicitly              | Human product choice plus independent and IC-1 review of the new fresh version; old meanings unchanged.                                                                                                         |
| A2 initial evidence                 | Preserve, qualify eligibility | Actual media intake under the bounded admissibility profile; exact package/context/result and scan commit, conflict rejection and exact replay. Full decode is not promised.                                    |
| A3 evidence privacy                 | Preserve                      | Source, AI-input bytes, text, digests, client recipe and lineage claims erase under scan/account rules in both enrollment states; late upload/completion cannot resurrect them.                                 |
| A4 enrollment/original evidence     | Clarify provenance            | Existing V3 readers retain their meanings; new assurance/version projects explicitly. Client derivation claim never becomes server verification.                                                                |
| A5 source/context/transition        | Extend                        | New package, reservation, input fingerprint, DTO and native queue contract; positive old admission recovers exactly and uncertain admission holds.                                                              |
| A6 video child                      | Preserve, change proof kind   | Retained chosen raw clip plus exact submitted frames/audio/context; original source identity proven, extraction relationship asserted by client. Missing raw source still blocks or needs explicit replacement. |
| A7 photo child                      | Preserve                      | Exact source and final submitted photo inputs survive freeze, cancellation/deletion and recovery; no post-freeze reencoding.                                                                                    |
| A8 audio child                      | Preserve                      | Exact source/composition and final submitted audio persist; any required boost/resample occurs before freeze under a supported recipe; original cleanup receipts remain required.                               |
| A9 inactive installed configuration | Preserve                      | Isolated HistoryQualification DI/storage and nonproduction validation; ordinary access nil. No installed use authorized.                                                                                        |
| A10 installed video                 | Preserve                      | Real native preparation, persisted package, restart, original-operation recovery/history/deletion on exact authorized candidate.                                                                                |
| A11 installed photo                 | Preserve                      | Same installed lifecycle with exact frozen photo bytes and source handling.                                                                                                                                     |
| A12 installed audio                 | Preserve                      | Same installed lifecycle with audio interruptions/composition and awaited cleanup.                                                                                                                              |
| A13 actions/exclusions              | Preserve                      | Media-backed reanalysis and explicit action policy; no text-only fresh path or video publication/review expansion.                                                                                              |
| A14 contention                      | Extend                        | New package/receipt admission, C1, retirement/deletion and all funding races under actual roles and both lock orders; preserve stage93 evidence and recurrence rules.                                           |
| A15 initial hardening/S0            | Amend preparation only        | Replace server-transform witness for this new branch with qualified byte/admissibility and consumed-input proof. Dispatch/funding/result/completion and broader hardening remain required.                      |
| A16 hosted privacy/storage          | Preserve                      | Exact authorized nonproduction upload/copy/generation verification, late-write retirement/erasure and recovery; no repeat inference after unknown execution.                                                    |
| A17 device/resources                | Preserve                      | Bound native preparation, disk retention, interruptions and background/restart behavior for all three modalities; server copy/parser budgets separately measured.                                               |
| A18 Field Trip                      | Preserve, separate owner      | No ownership transfer or qualification inferred from CPM-1.                                                                                                                                                     |
| A19 local final review              | Preserve                      | Exact candidate, cross-surface docs/schema/consumer parity, meaningful focused and complete affected gates, independent corrections/re-review.                                                                  |
| A20 exact CI                        | Preserve                      | Unpublished candidate and exact-push approval remain blockers; no inherited green result.                                                                                                                       |
| A21 release handoff                 | Preserve                      | All required rows satisfied or explicitly amended by user decision; external evidence and disabled production gates remain.                                                                                     |

The additional worker-specific prerequisites would change as follows **only if
the new contract is adopted**:

| Existing prerequisite                                               | Proposed CPM-1 treatment                                                                                                                                                       |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Server executable bundle and transform grant                        | Not part of CPM-1; retain old execution barriers and receipts unchanged for old versions. Native recipe support and frozen final bytes take their place for fresh preparation. |
| Supervisor signing, launch journal, installation/failover           | Not needed to attest a transformation that CPM-1 does not perform. Existing backend authority, lifecycle fences and storage proof are still required.                          |
| Independently verified raw-video extraction                         | Explicitly not promised. Raw source and supplied inference evidence remain distinct, privately bound and honestly labelled.                                                    |
| Hard server decoder CPU/native-memory qualification                 | Removed only where no decode occurs; bounded copy/hash/parsing and every actual decoder still require qualification.                                                           |
| Original deadlines, immutable outputs, transfer, late-write erasure | Preserve; derive a new exact byte-receipt contract without fabricating an old transform outcome.                                                                               |

## Review and implementation boundary

This evaluation recommends CPM-1 as the next design candidate, not an assertion
that it is already supported or qualifies every provider/profile. Before code:

1. Obtain independent and IC-1 design review and record the human decision on
   the reduced derivation assurance. Keep AWS unapproved.
2. Specify one coherent closed fresh
   package/assignment/receipt/admission/handoff schema, canonical bytes/domains
   and exact caller/lock/erasure inventory. Reuse existing owners while changing
   versioned evidence, not accounting authority. Fix the finite role/format
   bounds and provider consumption path.
3. Agree the native functional recipe/package persistence changes with the
   existing ownership boundaries. No capture visual refactor is implied.
4. Only after explicit implementation authority, implement bounded reviewed
   increments. Generate DTOs from their executable owner; preserve every old
   stored/replayed version. Required gates follow affected surfaces, with no
   repeated unchanged suites presented as proof of this new contract.

The acceptance vectors must include identical replay, changed media/text/order,
foreign or substituted generations, a malicious unrelated frame claim, header
bombs and corrupt files, partial local package writes, lost uploads, package
loss before/after server intent, both funding/C1/deletion race orders, provider
file identity mismatch, post-freeze adapter transforms, lost dispatch replies,
late results and erasure, and source export/retention across versions. A
malicious lineage claim may be stored as a claim; it must never pass a
server-verified derivation predicate. A malformed-file outcome never authorizes
a second call.

Raw video sent directly to a provider is a different candidate with its own
capability, consent/privacy, cost, limits and recovery assessment. CPM-1 retains
the frame-based workflow for evaluation and does not switch provider policy. If
a required profile cannot consume the frozen package within qualified bounds,
record that concrete gap before choosing server processing or changing scope.
