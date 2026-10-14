# IC-1 durable preparation before initial admission

> October 13 evaluation update: the user authorized drafting and reviewing the
> [CPM-1 client-prepared media amendment](client-prepared-media-amendment-2026-10-13.md)
> before any AWS decision. It proposes a distinct fresh-submission version; it
> does not weaken or reinterpret this document’s existing server-prepared or
> historical contracts. Adoption and implementation remain pending. AWS is
> unapproved, activation disabled, and all external-operation restrictions
> remain.

October 11 follow-up: the inactive whole-cohort media allocator and permanent
source-retirement metadata now have a candidate implementation in migration
`20261011194522`, following the source-declaration prerequisite. The historical
status below describes the earlier boundary. Current behavior is specified by
[the database lifecycle contract](../backend-and-data/04-database-schema.md#inactive-media-preparation-allocation-and-retirement)
and
[media API contract](../backend-and-data/05-api-contracts.md#inactive-media-source-candidate-contract).
Candidate evidence lives in `.artifacts/initial-media-source-lifecycle/`;
runtime, physical storage, grants/outcomes, M1 handoff and full S0 remain
unqualified. No activation or live installation is implied.

Status: coordinated design agreement, October 11, 2026. Baseline
`9bcd7f0c96d7912003f9b96a118181c57c7b788f`. History primary is the sole
implementation writer. Exact interface acceptance is recorded in
`.artifacts/initial-pre-admission-agreement/`; executable schemas and runtime
behavior still require their own implementation review and evidence. This is a
missing S0 dependency, not a second analysis engine or an enabled route.

## Implementation addendum: bounded no-media v2 (October 11)

The saved-assignment increment implements only the explicit no-media case:
canonical v2 candidate and complete private assignment, immutable deadline,
positive unfunded ownership, comparison inside both shared quota cores before
funding, atomic versioned promotion/recovery, and C1/strong erasure integration.
Media source destinations, preparation grants/outcomes, byte-preserving M1
handoff and qualified dispatch remain unimplemented dependencies of this design.
The current
[database contract](../backend-and-data/04-database-schema.md#prepared-no-media-saved-assignment-and-funding-comparison)
and
[service contract](../backend-and-data/05-api-contracts.md#prepared-no-media-initial-assignment-v2-inactive)
own the exact bounded behavior. Candidate evidence is retained in
`.artifacts/initial-saved-assignment/`; implementation tests are not installed
or external qualification. Gates remain disabled and the original broader design
below is preserved.

## Implementation addendum: source-contract prerequisite (October 11)

Following the no-media checkpoint, the IC-1 owner accepted an independently
testable inactive source-contract prerequisite before allocator integration. The
closed `media_sources` candidate has dedicated source semantics and explicit
unresolved outputs; SQL and TypeScript share vectors. Installed creation still
rejects media without mutation. No media assignment branch, storage ownership,
allocator or runtime eligibility is added. This is not completion of the durable
source checkpoint described below. See the
[current contract](../backend-and-data/05-api-contracts.md#inactive-media-source-candidate-contract)
and `.artifacts/initial-media-source-contract/` for exact scope/evidence. The
next implementation joins this contract to a complete server-qualified
assignment and the agreed durable source/erasure owner; additional identity-only
helpers are not a substitute for that lifecycle.

## Amendment and scope

The
[preparation binding interface](initial-preparation-binding-interface-2026-10-11.md)
correctly separates profile identity from execution permission, but its proposed
process-local handoff cannot recover prepared output lost before admission. This
contract replaces that future ordering with durable sources and a write-once
preparation outcome **before funding and admission**. Existing reference bytes,
profile registrations, admission v1 records and M1/M2 v1 evidence keep their
original meanings. No data migration or older-scan compatibility is proposed.

The later retained-derivation receipt will attest the original preparation
outcome and exact byte-preserving M1 handoff. It will not run the transform a
second time after M2. This explicitly amends the earlier future retained-source
retransformation proposal. M2 remains byte identity/signature evidence and does
not itself become derivation evidence. Every executed item still requires the
qualified exact artifact, verified original bytes and frozen options.

This contract covers the media preparation dependency. Text-only admission has
no media preparation grant; it must use its explicitly reviewed v2 empty-media
case. Other media and mixed cohorts cannot borrow WAV qualification. The local
Darwin profile remains Edge-ineligible; the production runtime selector is
empty. Activation stays false, backend selection null and ordinary access nil.

## Assignment-freezing prerequisite (October 11 clarification)

The initial-engine reviewer confirmed that the exact concrete inference
assignment must be resolved before source retention, without reserving credits.
Provider/profile/protocol assertions alone are insufficient. The saved identity
includes route, exact provider/model, execution plan and fallback effect,
inference policy revision, input/output compatibility,
prompt/schema/configuration assets, preparation artifact/options and experiment
effects. Available balance, credit holds, reservation/lease identity and funding
eligibility remain final admission facts. Current consent and revocation remain
authoritative; the saved assignment grants no execution or entitlement.

The history primary received the bounded shared-owner implementation handoff:
extract the existing authoritative selector and use that single implementation
for preparation and final funding. The initial-engine thread remains read-only;
its broader hardening scope is unchanged. Final funding must compare the saved
assignment under the actual quota-owner locks before any credit, counter or
reservation mutation. Exact saved admission/reservation recovery precedes fresh
selection. Changed defaults cannot rebase an existing intent; unavailable or
revoked saved configuration holds. The concrete default-change/revocation
predicate and complete projection still require executable review.

The first extraction separates fresh entitlement classification from its
existing credit mutation in the eight-argument private quota owner. The private
`resolve_fresh_quota_entitlement` helper returns the selected plan, original
complimentary link, fallback effect and whether the original owner must acquire
a hold. It acquires no credits and supplies no grant. Existing
active-reservation replay remains outside and before this fresh-only helper.
Public signatures, namespace guards and quota/provider owners remain unchanged.
This extraction alone is not the complete assignment projection, an
assertion-before-funding implementation, preparation persistence or S0
acceptance.

The helper is only a component within a locked owner transaction. Its timestamp
is the original quota owner's sample after its outer locks, preserving existing
v1 time semantics. A future preparation caller must establish those locks before
sampling time; it cannot treat a pre-wait sample, helper result or advisory
preflight as a durable snapshot or funding authority. Schema acceptance still
needs every affected overload/caller/trigger schedule, nested lock modes, and
deterministic policy/entitlement, same-ID, cancellation and zero-mutation
mismatch evidence for the completed shared projection.

The next shared-selector increment extracts the original policy lookup into
`internal.resolve_quota_policy` and the current eleven-argument identification
wrapper's binding lookup into
`internal.resolve_identification_provider_binding`. Both are private invoker
functions, revoked from API roles. They return the complete existing catalog row
and retain the original row lock and denial precedence. The four-argument quota
core calls the policy helper; the eight-argument entitlement owner delegates to
that core. The current identification wrapper calls the binding helper at its
original post-quota position. Older identification overloads and advisory
preflight are unchanged.

This step intentionally does not move locks or change consent/protocol checking,
retry behavior or funding mutation. In particular, the binding helper still runs
after funding in the existing path. It is not a pre-funding comparison or
complete assignment snapshot. The next composition must load an original saved
private assignment under live ownership/deletion/cancellation guards, establish
all current decision rows in the reviewed lock order, then compare before the
first hold/epoch/reservation/counter mutation. Caller-supplied JSON or rollback
after a mismatch cannot substitute for that boundary. Full closed snapshot
schema, policy-writer contention and zero-mutation comparison tests remain
required before preparation persistence can use these helpers.

## One operation, separate storage phases

The logical identity remains `(owner_id, scan_id)` with
`operation_id = scan_id`. A private preparation intent belongs to
`InitialAnalysisLifecycleRepository`. Its source reservation, transform
permission and storage receipts are not provider attempts, quota reservations or
credits. The new private records have no direct API-role table access. Only
fixed service operations may write them.

Fresh preparation atomically claims the existing global content-free
`internal.initial_analysis_operation_fences(scan_id)` under the shared owner and
ingestion advisory scope. A subordinate permanent preparation-state fence
records unissued/issued/handoff-complete/terminal state, never a second
namespace or an independent absence check. Do not fabricate an admitted
submission, M1 cohort, M2 receipt or pending provider-dispatch lifecycle to
obtain storage. M1's foreign keys still require a real admitted submission
before allocation.

The global fence excludes competing v1 admission and legacy reservation,
commit/finalization and recovery writers. Creation must check the complete
existing occupancy inventory, including scans/history, ingestion jobs/intents,
source/analysis records, quota, complimentary usage, invocation and tombstones,
before inserting that fence. A missing private intent behind a permanent fence
is terminal/held, never fresh absence. All generic/raw writers must preserve the
existing global exclusion; exact writer inventory is a schema acceptance gate.
Existing v1 recovery remains exact and cannot acquire v2 authority. This extends
when the existing global fence can be created; it does not relabel v1 bindings.
The v2 final-admission owner consumes that same row only with the exact original
preparation outcome. Consumption is a guarded state handoff, never deletion or
reopening of global exclusion. It never inserts a second fence or exposes a
general pre-fence bypass. Permanent rows retain no owner or content-derived
identity.

The private intent freezes the accepted route, complete ordered semantic input
and descriptions, ordered source identities, preparation options and exact
profile/configuration asset identities. Only prepared-output tuples and original
funding remain unresolved. Existing canonical input rules and limits apply;
there is no second normalization. Source identities include item/role, SHA256,
byte count and media type. Backend generation, opaque destinations and deadlines
are server-selected. Caller paths, URLs, profile flags and current defaults are
not authority. Retry compares the exact frozen candidate; changed input/order,
owner, profile, options or route conflicts. Status/recovery uses the original
identity without reselecting configuration or accepting replacement bytes.

The pre-admission registry is separate from M1's registry and retains only
opaque object ID, backend generation and retirement/cleanup state. Private
source/outcome metadata owns hashes and role mappings. Register each destination
before external I/O. Conditional immutable writes, direct bounded uncached
GET/hash verification and irreversible erasure markers follow M1's storage
rules, with a separate namespace. No caller can redirect the saved destination.

## State, ownership and expiry

The proposed fixed preparation lifetime is 300,000 milliseconds from original
intent creation. It is not renewed by reads, retries, preparation grants or
funding. The profile must have separately qualified time/input/output limits
that fit inside the remaining lifetime; a narrow synthetic envelope cannot
qualify full ingress. These limits require runtime qualification before use.

| Durable phase             | Evidence and authority                                                                                                    | Permitted next action                                                                            | Uncertainty, expiry and recovery                                                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Absent                    | No preparation or admitted operation fence, valid live owner, no deletion/competing writer                                | Create one private intent and permanent fence, register fixed source destinations                | Uncertain creation reads the same identity; absence from one failed read is not permission to choose another identity                                           |
| Sources allocated         | Frozen intent and destinations, no funding and no transform grant                                                         | Retain original bytes; settle exact verified source receipt                                      | Exact bytes may be written only after positive known-absent destination status and within the original lifetime; uncertain PUT reconciles that destination only |
| Sources verified          | Write-once source receipt bound to all original roles                                                                     | Atomically issue the sole nonrenewable preparation grant                                         | Known absence of a grant under the locked owner permits the first grant; an issued grant, even with lost response, never permits another                        |
| Preparation issued        | Permanent issued fence plus private exact token/profile/source/options binding                                            | Only the fresh positively received grant may invoke the bounded transform once                   | Process loss, timeout, cancellation or lost grant response means recovery-needed; no regrant, retransform or fallback profile                                   |
| Output registered         | Original worker has a known bounded output; immutable outcome manifest and destination roles registered before output I/O | Retain and directly verify those exact prepared bytes; settle outcome                            | Manifest alone is not byte proof; uncertain writes reconcile fixed destinations. Missing bytes after worker loss hold; source bytes cannot recreate the output  |
| Outcome recorded          | One private immutable successful outcome, complete source/prepared bytes, exact artifact/options proof                    | Final v2 admission atomically freezes final input/configuration and existing original funding    | Lost settlement/admission responses recover exact saved outcome/binding. New outcome/admission after expiry is rejected; existing live receipts may replay      |
| Admitted, handoff pending | Original v2 binding and funding, pre-admission bytes retained, fixed M1 destinations                                      | Copy exact source/prepared bytes into M1; obtain original M2 verification                        | Copy uncertainty reconciles exact M1 destinations, never transforms. Pre-admission objects cannot retire merely because a copy timed out                        |
| Handoff recorded          | Separate write-once derivation/handoff receipt binds original outcome plus original M1/M2 evidence                        | Retire pre-admission objects; later dispatch must verify the M1 prepared bytes actually consumed | Receipt replay requires live owner/deletion checks; it is not provider permission                                                                               |
| Retired/cancelled/deleted | Permanent content-free fence; all registered destinations marked for erasure before private cascade                       | Exact status and cleanup only                                                                    | No source replacement, new grant, admission, receipt resurrection or automatic inference refund                                                                 |

A preparation denial with a known validation/transform failure may record a
bounded closed failure code, then retire. No raw process output or media is
stored in diagnostics. Unknown execution must remain distinct from a known
failure; neither funds an analysis. Expiry is not proof that execution did not
start. The issued bit never clears, including after private evidence erasure.

Preparation works outside SQL locks on a private exact-length copy of the
verified original source bytes, without externally mutable aliases. The trusted
runtime resolves only the frozen compatible artifact and checks identity before
execution. It must execute all required bounded items under the one operation
grant; partial output cannot authorize partial admission or another grant.
Register output roles only after their known tuples exist. Reuse a source object
only for an exactly equal tuple and bytes; otherwise allocate one bounded new
prepared destination. Do not create speculative unused M1 objects.

## Exact durable outcome and service boundary

The successful outcome is a closed versioned private record, with canonical
bytes and domain-separated digest. It binds the original owner/scan/intent
identity, preparation grant, source-verification receipt, configuration/profile
digest, exact artifact/validator/transform identity, ordered item indices and
source/prepared role tuples, exact options, pre-admission backend/destinations
and verification proof for all output bytes. It contains no media, credentials,
provider result or mutable external URL. An outcome digest alone is not proof
that bytes were retained. Identical settlement replays only after live ownership
and deletion checks; a conflicting tuple, option or receipt rejects.

Fixed logical service operations are: create preparation intent; get preparation
status; settle source verification; issue preparation grant; register known
output; settle preparation outcome; finalize v2 admission; record M1 handoff;
and retire preparation storage. Logical terminal retirement is a distinct state
transition from successful storage cleanup. Cancellation remains the original
logical IC-1 cancel operation extended to recognize pre-admission ownership.
Names describe the contract, not implemented RPCs. Concrete typed declarations,
closed bounded schemas, digest vectors and exact response unions must be
reviewed together with the first implementing schema; there is no
caller-selected routine or arbitrary JSON passthrough. Public/native capture
DTOs do not change here.

Only a fresh issue response carries execution authority. Status and duplicate
issue responses expose phase/references, never a reusable grant. The surviving
original worker may settle its exact known output under the original binding
while live and in time; a replacement worker cannot use status as permission to
run preparation. If it recovers the already registered exact bytes and original
execution evidence, it may finish receipt reconciliation without invoking the
artifact. If these are missing, return recovery-needed. No read establishes a
new execution opportunity once the issued fence exists.

Final admission verifies the saved outcome and original intent under the shared
scope. It must first prove that the remaining original lifetime covers the
qualified full M1/M2 handoff budget and settlement reserve; inadequate remaining
time holds before funding, without renewing the deadline. The 300-second cap is
proposed, not proof of that budget. It then uses the existing original funding
policy/owners in the same SQL transaction as v2 input/configuration/admission
persistence. It does not reselect the preparation profile, perform media I/O or
call a provider. The admitted input includes known source/prepared tuples and
original canonical text. All original provider configuration assets are frozen;
funding eligibility is decided at this transaction, not reserved early to keep
preparation alive. Lost responses replay the original binding and funding;
changed or cross-version retries fail closed. No outcome or funding row may be
inferred from a storage-only digest.

## M1 handoff and terminal ordering

M1 keeps its own object identities and normal admitted-manifest allocator. Its
v1 expiry and receipt semantics stay unchanged. The pre-admission bytes remain
owned and readable during handoff; copying occurs outside SQL transactions and
never calls the preparation artifact. The handoff receipt maps every original
pre-admission role to the final M1 role and verifies exact tuple equality plus
the complete M2 receipt. It cannot attest only a subset of an operation.

The handoff/derivation proof is a self-contained write-once child of the
admitted private lifecycle. It embeds the complete original preparation outcome
and original execution provenance needed to verify every derived tuple, together
with the final M1/M2 mapping. Commit that proof before releasing pre-storage. It
has no cascading foreign key from a pre-storage object, cohort or intent;
ordinary pre-storage cleanup cannot erase it. The admitted submission owns its
lifetime until logical cancellation, scan deletion or account erasure. This
retains derivation authority without requiring deleted pre-storage evidence to
be fetched again.

Successful storage retirement is not logical cancellation/terminal retirement.
After a committed handoff, retire only pre-storage destinations and redundant
private pre-storage metadata; preserve the valid admitted lifecycle, M1 cohort
and self-contained proof. The permanent preparation fence remains consumed, with
a distinct handoff-complete state that cannot grant another preparation. The
table's terminal row applies to logical retirement/cancellation/deletion, not
successful pre-storage release.

The original preparation deadline also bounds new handoff work: M1's later
allocation deadline cannot extend permission to read/write pre-admission bytes.
Handoff settlement and expiry serialize under the same operation lock and read
current committed state and database time there. A complete valid handoff must
commit while eligible before the original deadline. If no such proof exists at
expiry, persist logical terminal retirement and deny new handoff/dispatch before
object cleanup. A draining M2 claim postpones physical cleanup only, never
eligibility. No late M2 receipt or handoff can reverse this terminal state.
Conversely, a committed timely handoff defeats stale expiry snapshots: an expiry
worker must reread under the lock and cannot retire its valid M1 objects.

For expired incomplete handoff, ordinary M1 expiry retirement is insufficient:
M2's accepted v1 rule excludes retirement whenever a verification receipt
exists. The v2 terminal coordinator must use explicit C1 abandonment of the
admitted operation. Within the shared scope it checks the exact original
provider/funding witness, persists terminal cancellation, then erases the
private submission chain; M1's existing retirement-before-cascade path retires
destinations regardless of ordinary receipt exclusion. It must not merely call
ordinary M1 retirement and ignore held/in-use. Original funding is released only
if C1's unchanged exact reserved-funding proof succeeds; contradictory/unknown
provider evidence remains held with no refund. Preparation's eraser itself never
settles funding.

For v2 preparation-backed operations only, M2 claim and settlement must check
the preparation terminal/deadline state before granting a claim or inserting or
replaying a receipt. A claim acquired before expiry cannot settle after a
terminal winner or create a late proof that restores handoff. An already
recorded M2 receipt does not defeat C1 abandonment. A completed timely handoff
exempts its valid M1 cohort from pre-storage expiry, while ordinary M1/M2
lifecycle rules still apply. These are explicit v2 fence additions; the M2 v1
envelope, evidence meaning and behavior for existing v1 admitted operations are
unchanged. External work already issued may drain, but late callbacks cannot
settle; registered objects remain permanently erasable. No claim extends
eligibility.

## Pre-admission cancellation and erasure

C1 receives a distinct preparation-owned branch before its existing
no-submission occupancy rejection. Under the common locked scope, precedence
remains live owner, cross-owner/deletion checks, already-complete denial,
same-owner cancellation replay, then the exact current preparation/admission
phase. No supplied owner or missing record establishes ownership. Erased or
ambiguous state yields generic deleted/unavailable without a caller receipt.

| Cancellation phase                                                                | Durable proof and disposition                                                                                   | Atomic terminal action                                                                                                                                                                                                                                                    |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Owned sources allocated/verified, preparation unissued                            | Exact private intent and global exclusion prove no admission/provider authority and no original funding         | Persist terminal preparation and `cancelled_pre_dispatch` lifecycle under a new guarded pre-admission proof predicate; retire every registered source before erasing private preparation rows; record C1 `dispatch_prevented` receipt, without calling any funding helper |
| Owned preparation issued, output registered or outcome recorded, still unadmitted | Same no-provider/no-funding proof; preparation execution may be unknown, which does not mean provider execution | Same terminal action and no-funding disposition; stop new output/receipt writes and fence late workers; never regrant or transform to finish cancellation                                                                                                                 |
| Admitted, handoff pending or complete                                             | Exact admitted C1 dispatch/funding proof, not the pre-admission predicate                                       | Use existing C1 classification and original settlement rules; terminalize preparation and retire pre-storage plus admitted M1 destinations before private cascade; unknown provider evidence means no refund                                                              |
| Exact same-owner cancellation receipt                                             | Original terminal state and receipt still live                                                                  | Return unchanged C1 three-value envelope after ownership/deletion checks; do not recreate private input, renew work or settle funding again                                                                                                                               |

The new no-funding predicate must positively establish the original private
preparation owner/global fence, no admitted submission/admission/funding, no
provider authorization or invocation/result/completion, and no contradictory
generic work. Missing/contradictory proof cannot yield `dispatch_prevented` or a
refund; owned ambiguous cancellation may fence as `dispatch_outcome_unknown`
without settlement. This is an explicit extension to C1's proof predicates and
lifecycle/cancellation insert guards, not an assertion that its current reserved
quota predicate works before admission. The response union remains unchanged.
Same-owner cancellation stays available after gate closure. Fresh cancellation
with no preparation intent retains C1's existing unknown/no-funding semantics.
Automatic preparation expiry uses this same terminal path, including the minimal
owner-bound C1 cancellation receipt. It reports operation termination, not that
the user requested cancellation. A later same-owner `cancel_initial_analysis`
call replays that original closed `cancelled` envelope with its saved dispatch
classification after normal live-owner/deletion checks. Expiry grants no extra
privacy retention: subsequent scan/account erasure removes the receipt just as
for explicit cancellation. The private minimal cancellation receipt survives
only for same-owner recovery and is erased by later scan/account deletion under
C1's existing privacy rules.

Every mutation and duplicate return rechecks live owner, tombstones and
permanent fences. Lock ordering begins with the existing user row,
scan-ingestion advisory, scan/history and existing
lifecycle/submission/cancellation/admission scope where present. Preparation
private intent/grant/outcome rows follow that scope, then cohort/receipt state
and registry objects in sorted object-ID order. Registry cleanup never acquires
an owner lock after an object lock. Final admission must use the same outer
scope and existing funding lock ordering; it cannot call an independent
admission transaction while holding preparation locks. Handoff must not call M1
from a reverse lock path. Exact implementation lock graphs and concurrent
schedules are acceptance requirements before the schema is accepted.

Scan deletion, pre-row cancellation, account detachment and physical account
deletion all recognize private preparation ownership, even before a submission
or scan exists. Owner lookup, sorted pre-row advisory locking, private-erasure
triggers and ghost-profile merge guards must include the new intent. Before any
private cascade, irreversibly retire every registered destination; cleanup
metadata survives without text/media digests. Retained scientific scan rows do
not preserve preparation evidence. Late source/output PUTs meet the permanent
erasure marker; late outcome/admission/handoff settles cannot recreate evidence.
Deletion wins over identical receipt replay. Account changes never transfer a
preparation intent to a new owner.

## Acceptance and next checkpoint

| Required boundary         | Responsible owner                                                   | Concrete pass condition                                                                                                                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contract agreement        | History primary; initial-engine and independent read-only reviewers | Exact candidate acceptance of pre-admission ownership, one-time grant, no-retransform handoff and funding/privacy boundaries                                                                                                                 |
| Private state and erasure | History primary, independent database review                        | Disposable SQL tests for every state edge, both cancellation/deletion race orders, account cascade/merge, pre-row tombstones and late writes; no private identity survives erasure                                                           |
| Namespace and admission   | History primary, initial-engine review                              | All competing routes deny reserved IDs; atomic v2 funding/outcome binding, identical retry, changed retry and lost-response recovery; unchanged v1 recovery                                                                                  |
| Source/output transport   | History primary, initial-engine review                              | Bounded direct verification, fixed destinations, mutation rejection, uncertain PUT/GET/settle recovery, missing-output hold and zero retransform calls                                                                                       |
| One-way M1 handoff        | History primary, independent concurrency review                     | Every role maps exactly; crash at each phase retains ownership or terminal erasure; both expiry/handoff winners, stale expiry snapshots, late M2 settlement and paused successful cleanup cannot erase a valid proof or revive terminal work |
| Dispatch consumption      | Shared IC-1 contract, history implementation writer                 | Reload and verify the actual retained prepared bytes into a private capsule; separate fresh provider grant; no intervening mutable alias/substitute fetch                                                                                    |
| Runtime qualification     | Separately authorized runtime owner/user                            | Compatible exact artifact and full supported ingress/resource/deadline evidence; local Darwin result never satisfies this row                                                                                                                |
| Integrated candidate      | History primary; independent reviewers                              | Full affected gates at a coherent milestone, all route/recovery/cleanup consumers, final exact-candidate CI after separately approved publication                                                                                            |

The next implementation increment is the inactive private intent/fence and
source-destination lifecycle, including its cancellation/erasure and competing
namespace exclusions. It must be independently reviewed with executable schemas
and disposable concurrency evidence before adding preparation grants/admission
handoff. No phase enables a partial live route. Subsequent increments implement
the reviewed dependency in order; full S0, other media, text history, native and
external qualification remain open. No hosted action, installation, deployment,
publication or broader engine ownership transfer is authorized here.
