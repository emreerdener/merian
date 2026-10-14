# CPM-1: client-prepared media amendment to IC-1

Status: October 13, 2026. **Draft for independent and IC-1 review.** The user
authorized evaluation and drafting, not implementation or contract adoption.
Proposed semantic revision: **CPM-1, revision 3**, a candidate IC-1 revision 4
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

## Mandatory acceptance gates and ownership

October 13 user direction makes the following gates explicit. This is an
acceptance specification, not CPM-1 adoption or implementation authority. Each
gate has two separately recorded states: **specification agreed** and **exact
candidate demonstrated**. Neither state is currently closed. A review of this
draft closes neither gate; existing software and research results retain their
original scope.

History primary owns the functional native package, backend integration,
contracts, migrations and evidence as sole writer. The IC-1 owner reviews
initial-operation identity, assignment, admission, accounting, dispatch,
recovery and retirement read-only; an independent reviewer checks the complete
contract and corrected candidate. The user owns product tradeoffs and device
execution. Any additional implementation owner requires an explicit recorded
handoff. Capture visual work and Field Trip are not prerequisites for this
functional agreement.

### G1 — Original-photo retention (A2, A4, A5, A7, A11, A17)

Before implementation, specify acquisition of selected original bytes for camera
and library imports, their exact format/size envelope, package location,
protection, atomic ownership transfer, durability barrier and restart behavior.
Preserve selected bytes even when crop/orientation/display preparation produces
new bytes. An unavailable cloud-library asset, unsupported representation, copy
failure or insufficient storage preserves the draft and blocks freeze; no
derivative or Photos identifier satisfies the original role.

Candidate pass requires byte-for-byte equality and matching length/digest
between selected originals and owned persisted originals through draft clear,
restart, upload, completion and authorized source delivery. Original, AI-input
and preview identities remain separately addressable, even when a compatible
role mapping shares one physical object. Inject interruption before/after each
file write, durable manifest commit, queue commit and draft clear. Every outcome
must recover either the intact draft or a complete committed package; there must
be zero successful draft clears leaving an unrecoverable original. Historical
versions without originals remain explicitly unavailable.

### G2 — Final audio and quality (A2, A5, A6, A8, A12, A17)

Before implementation, freeze a compatibility table for every supported
source-format, standalone/companion-audio, recipe version, client version and
server/provider profile combination. It must enumerate decode, channel mix,
resample kernel/rate, normalization or boost, clipping, silence windows and tail
handling, trim/padding, sample quantization and final encoding. Name the owner
of each stage and exact versioned constants. Required processing finishes before
package commit; no dispatch adapter may subsequently process the frozen bytes.
Unsupported, interrupted or incompatible preparation blocks submission and
preserves recovery state, without dropping required audio or changing the
recipe. Recipe names are client claims, not server derivation proofs.

Signal and identification-quality evidence are separate required gates:

- Freeze a deterministic signal corpus and oracle before porting: silence,
  near-silence, low-amplitude calls, clipping, opposite-phase stereo,
  transients, sample-rate boundaries, anti-aliasing tones, partial windows and
  short/maximum clips. The agreement specifies exact sample
  count/channel/rate/encoding, alignment, and numeric tolerances for waveform,
  spectral alias energy, amplitude/clipping and trim boundaries. A faithful port
  should target exact PCM/output equality; any tolerance or changed DSP needs a
  reviewed numeric justification before implementation. Every vector must meet
  every bound, with zero post-freeze transforms and zero dispatches on
  preparation failure.
- Define the paired quality protocol before implementing the audio change: exact
  baseline/candidate pipelines and provider configuration, supported audible
  caller or appropriate abstention endpoint, technical-failure denominator,
  unsupported-specificity/false-abstention guardrails and coverage by
  source-recording cluster. Predeclare a numeric noninferiority margin,
  interval/test, power/precision and sample-size justification, per-group
  minima, blinded adjudication and incomplete-run rules. A confidence score,
  successful decoding, moved code or non-significant difference is not
  equivalence. Pass requires the frozen primary rule and every guardrail;
  inconclusive evidence keeps the gate open.

Use the existing
[research qualification contract](../research/identification/benchmark-contract.md)
and evaluator owners. Historical six-clip DSP comparisons and visible-caller
studies have exposed inputs and unresolved reference limitations; they do not
qualify this pipeline. Before collection, verify actual private exposure and
reference manifests and obtain the separately required exact provider-run,
attempt and cost authorization. No study, corpus, sample count or paid run is
selected or authorized by this amendment. The future protocol must be registered
and reviewed under the research procedure; these requirements create no new
qualification record. Signal tests cannot waive the quality gate, nor vice
versa.

### G3 — Closed storage envelope (A3, A5, A14, A16, A17)

Before implementation, the next agreement must contain actual integer byte and
count limits, not only a promise of bounded processing. Its signed-off resource
table must include all of the following for every supported modality/cohort:

| Resource             | Required concrete specification                                                                                                                                    | Owner and measurable acceptance                                                                                                                                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Each asset           | Original, AI input and preview format, maximum bytes, dimensions/duration/sample count where applicable; asset and role counts                                     | History primary; native and server boundary tests accept the maximum and reject maximum plus one before unsafe allocation or funding.                                                                        |
| Whole package        | Sum of distinct physical objects, ordered logical role references, manifest/text overhead and object-generation count                                              | History primary with IC-1 review; every legal maximum cohort fits; no deduplication silently changes multiplicity.                                                                                           |
| Native peak disk     | Retained originals, AI inputs, previews, draft copies, encoding scratch, atomic-write copies, upload staging, restart leftovers and export copies that may coexist | History primary; instrument maximum live allocation and minimum free-space reserve on the user-run candidate. Bound concurrency and fail before exhausting reserve; never prune another live version to fit. |
| Native aggregate     | Concurrent preparing/queued packages, retained-history policy, unknown operations and cleanup backlog; reservation/low-storage behavior                            | History primary; concurrent boundary and crash tests cannot oversubscribe, silently evict required originals or clear drafts on failed reservation.                                                          |
| Backend aggregate    | Per-owner/global intent/object/byte/concurrency/rate caps; staging and retained copies plus in-flight/late-write headroom                                          | History primary with IC-1 review; atomic reservation races never oversubscribe; physical copies count until proven released.                                                                                 |
| Lifetime and cleanup | Intent deadline, signing bound, late-write completion proof, reconciliation batch/work limits and backlog ceiling                                                  | Same owner; finite write authority, content-free fences and late-write reconciliation survive process restart. Unknown storage liability stays reserved.                                                     |

A digest match alone does not establish that two files share storage. Count two
copies until their actual shared immutable storage identity is established;
count each simultaneous staged/retained generation. For reference sharing,
record logical ownership separately from physical byte accounting. Native hard
links/clones cannot be presumed to make peak disk free; measure allocation and
reserve worst-case copy-on-write growth. Existing retained libraries and new
package scratch must both enter free-space decisions. The workstation's 20 GiB
build floor is not an iOS-device or hosted-storage budget.

Any missing numeric cell, unnamed storage owner or unsupported maximum cohort
blocks **specification agreed**. Measure and record actual candidate high-water
marks, including interruptions and cleanup backlog, before **exact candidate
demonstrated**. Constants alone are not measured resource evidence. If fitting
requires narrowing current capture support, changing audio behavior, retaining
fewer originals or raising storage limits, record that product tradeoff for
explicit agreement; do not make it as an implementation convenience.

### G4 — Authoritative references, recovery and deletion (A3–A8, A14–A17)

Before implementation, define a private server-owned asset-reference ledger
keyed by owner, immutable storage identity/generation and explicit owning
operation or version plus role. A digest is not ownership. Acquire durable
references or holds atomically before a child may depend on a shared source;
transfer intent holds into admitted/history references without a zero-reference
interval. A client count or eventual sync projection cannot authorize physical
deletion. The closed schema agreement must enumerate effective callers,
constraints, transaction locks and both race orders. Native package/file leases
mirror the ownership requirements locally; they cannot release server
references.

Remove only the deleted owner's references after the authoritative,
revision-checked deletion/retirement transition. Surviving source, AI-input,
preview and pending-operation references continue to hold the exact required
assets; deleting an ancestor must not remove its children's source. Active
upload/copy/export/read leases and unresolved outcomes also hold resources under
explicit release conditions. Whole-account erasure revokes access and retires
all owners under its existing precedence, while preserving only permitted
content-free fences and cleanup duties. A version tombstone prevents
resurrection by late completion or sync.

Physical erasure is eligible only after zero surviving references/leases,
serialized retirement against new acquisition, and proof that no original
in-flight writer can recreate the object (or continued retired-ID reconciliation
until that proof exists). A late PUT never acquires a new reference or revives a
retired version. URL expiry, one absent read, local file unlink or a terminal
analysis result is not sufficient cleanup/capacity-release evidence. Persist the
cleanup obligation before attempting deletion; failures retain it and its
capacity liability. No timeout may turn unknown inference into fresh dispatch or
refund. Finite backlog exhaustion blocks new storage admission instead of
forgetting unresolved liabilities.

The exact candidate must pass end-to-end fault injection across native storage,
upload allocation, verification/admission, dispatch, completion/history and
retirement. Pure codec/unit tests alone cannot close this gate. Exercise initial
and child operations for all three modalities and the following boundaries:

| Fault/race                                                                                                                        | Required observable outcome                                                                                                                                  |
| --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Partial local write, app termination and restart at every package commit boundary                                                 | Intact draft or verified exact committed package; no invented/reprepared bytes after freeze.                                                                 |
| Interrupted upload, lost create/PUT/admission replies, delayed create after not-found, missing local files before/after admission | Recover only the original identity and destinations; preserved remediation state; no new operation from uncertain absence.                                   |
| Lost dispatch acknowledgement, restart after provider acceptance, late result/completion                                          | At most one original primary grant/invocation and one applicable charge/result commit; never a second invocation or inferred refund because of uncertainty.  |
| Child acquisition versus parent/version deletion, both orders; shared source/AI/preview roles                                     | A committed child retains its exact assets, or acquisition is rejected before dependence; no surviving reference points at erased bytes.                     |
| Deletion versus upload, admission, completion, sync and source export, both orders                                                | Authoritative deletion/capability behavior; no resurrection, unauthorized delivery or premature release. Existing selected/last-version action rules remain. |
| Intent expiry/cancellation with partial/unknown/late accepted PUT, cleaner crash, failed delete, cap exhaustion                   | Fixed destinations remain retired, funding denied, cleanup recoverable and bytes reserved until terminal erasure proof; no reminted upload authority.        |
| Missing historical original or unsupported media/recipe                                                                           | Explicit unavailable/replacement/blocked state with preserved evidence; no text-only or derivative fallback.                                                 |

Retain the exact source/configuration and permitted synthetic media identities,
fault schedule, operation transitions, reference/lease/capacity accounting,
provider-attempt and funding counts, final file state and test result for every
case. Real device and hosted integration evidence needs separately named
operational authorization; simulated success cannot be relabelled as that
evidence. Individual-version deletion/export UI remains the later approved
milestone, but its shared-reference and cleanup invariants must be designed now
and cannot be waived when that milestone is qualified.

### Specification closure and feasibility record

Resolve material feasibility questions before authorizing production-code
implementation: availability and maximum size of selected original bytes;
compatibility of each full legal cohort with device and backend budgets; audio
recipe portability and signal oracle; availability of eligible audible-reference
quality data; and storage guarantees for late-write termination and reference
release. Record source evidence, proposed numeric limits, conflicts, decision
owner and pass/fail decision for each. An unresolved question stays a named
blocker, not an ad hoc implementation choice. A bounded feasibility spike, if
needed, needs its own agreed scope and cannot mutate saved operations or imply
activation.

Read-only feasibility findings for revision 3 (current values, **not proposed
CPM-1 limits or qualification**):

- Native `ScanMediaPayloadPolicy` caps aggregate staged inference images at
  5,242,880 bytes, each audio at 2,700,000 bytes and video at 12,582,912 bytes.
  `MediaStagingContract` permits at most five image, two audio and one video
  upload members: 23,225,792 bytes at those maxima before display copies and
  retained original photos. The staging source policy permits two physical
  sources; its source count is not the upload-member count.
- `OfflineQueueStoragePolicy` uses a 26,214,400-byte (25 MiB) **soft estimate**
  and 104,857,600-byte (100 MiB) free-space reserve. It is not a hard physical
  package or temporary-storage bound. Originals have no current queue byte slot
  or original-size ceiling; display copies have no separate aggregate cap.
- Backend `initialAnalysis/mediaBinding.ts` bounds its existing contract at
  eight ordered items, ten unique objects, 28,625,792 distinct persisted bytes
  and 33,868,672 supplied bytes. The last quantity is input headroom, not
  physical-storage capacity. Generic backend `mediaBudgets.ts` permits up to
  five individually 5 MiB images, two 2,700,000-byte audio objects and one 12
  MiB video, totalling 44,197,312 bytes. These envelopes differ and must not be
  combined into a claimed accepted maximum CPM-1 cohort.
- Existing audio preparation targets mono 16 kHz PCM16 WAV after channel mixing,
  20 ms RMS silence windows at 0.008, two-window padding, short-video context
  preservation, and Blackman-windowed sinc resampling (radius 32, cutoff 0.9,
  128 phases). It rejects output shorter than 8,000 samples. Native companion
  WAV is currently 44.1 kHz. Exact processor/oracle binding and output/work
  ceilings still require the G2 compatibility agreement; final WAV container
  validation alone does not establish that recipe.
- Native video preparation overlaps frame extraction, optional audio and
  playback compression; originals, candidates and WAV intermediates may coexist.
  Current streamed file upload avoids one full Data copy, but is not a
  whole-lifecycle scratch reservation. Cross-version shared references are also
  not supplied by the existing per-scan object registry. G3 peak budgets and G4
  reference ownership therefore require actual functional design.

These findings expose material feasibility blockers before implementation. The
next closed resource table must explicitly reconcile native versus backend
cohorts, add original/display storage, bound simultaneous scratch and retained
copies, and define shared-reference ownership. A smaller one-source profile or
prohibition on source sharing is **not adopted** to make the arithmetic fit;
that would change supported behavior or require explicitly budgeted copies. No
honest numeric original-photo or peak-disk limit can be claimed from current
constants alone. Their absence remains a specification blocker. Resolve the
source envelope and copy/concurrency design first, then present concrete integer
budgets and compatibility decisions for review rather than inventing values and
calling them current-compatible.

The next agreement is not closed until those decisions, all numeric limits,
recipe compatibility, quality protocol and caller/lock/reference release rules
are complete and independently/IC-1 reviewed. After explicit implementation
authority, the actual candidate must prove G1–G4 through affected software gates
and the required authorized end-to-end runs. Re-review corrections and retain
failed evidence. No A-row closes merely because a specification or review
passes.

## Review and implementation boundary

This evaluation recommends CPM-1 as the next design candidate, not an assertion
that it is already supported or qualifies every provider/profile. Before code:

1. Obtain independent and IC-1 design review and record the human decision on
   the reduced derivation assurance. Keep AWS unapproved.
2. Specify one coherent closed fresh
   package/assignment/receipt/admission/handoff schema, canonical bytes/domains
   and exact caller/lock/erasure inventory. Reuse existing owners while changing
   versioned evidence, not accounting authority. Close G1–G4 specification
   requirements, including concrete role, package and peak-storage limits,
   recipe/quality criteria, shared references and release conditions, and the
   provider consumption path.
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
