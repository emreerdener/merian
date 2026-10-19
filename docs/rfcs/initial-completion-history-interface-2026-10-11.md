## October 19 — legacy/native ownership boundary locally verified

The existing queue, job reset, deletion, funding and background writers now
refuse native receiving ownership, reserved markers and ambiguous metadata.
Fresh ownership is checked across suspension points; background mutations share
the canonical per-scan lock. Missing queues cannot recreate scan-ingestion jobs.
Native admission, result settlement and cleanup still require their dedicated
owner; these guards do not activate them or authorize another AI request.

The full shared-checkout target ran 6,309 methods: 6,307 passed and two failed.
Both failures identified the same silent upload-candidate fetch. The correction
adds private error logging and preserves the early fail-closed return. All 34
methods in the five reviewed corrective suites then passed, with zero skips or
runtime warnings. All 2,836 source/project hashes and candidate hashes remained
unchanged during each run. This is retained full-target evidence plus focused
corrective validation, not a green full-target rerun. Earlier compiler and
assertion failures remain retained.

Evidence: `.artifacts/native-legacy-partition-20261019/full06-result.json`
(XCResult `a000c3584a3a49a5aec166ce1a8d19f8`) and `focused07-result.json`
(XCResult `3576b46a2905490e825b286e86b1da16`). Candidate07 SHA256:
`a856e1dd339a1a13f57d98cc387bb90ca5bf735f0e3ba60a6e4c3adaa83277d4`. Independent
and IC-1 reviews cleared the exact correction and execution scope. This is local
shared-checkout validation, not isolated-source, device, hosted or activation
acceptance.

Continue with the same registered native owner, scoped app-container validation,
atomic receiving admission, retained transitions/cleanup and Capture/Auth
composition, then integrated media acceptance and approved version actions and
redesign. The scoped audit must validate inventory-anchored rows and exact
joins; it must not claim detection of completely unanchored corruption or
physical availability. Qualification behavior and limits remain unchanged.
Activation stays disabled, PR116 frozen, the deployment hold active and AWS
unapproved. No routine proceed prompt is required.

## October 19 — receiving validation committed; legacy guards in review

Native receiving fact validation is committed locally as `7d1c455d7`, after
independent and IC-1 review and the 40-method focused pass recorded below. The
next implementation partitions legacy queue/job/deletion/funding helpers from
native receiving ownership. It is not yet runtime-qualified. The canonical
helper contract is in the
[offline pipeline](../backend-and-data/01-offline-sync-pipeline.md#native-receiving-ownership-and-legacy-helpers).
Typed native admission, retained transitions, cleanup and Capture/Auth
composition remain next; then integrated acceptance and the approved version
actions/redesign. Activation stays disabled, PR116 frozen, deployment hold
active, AWS unapproved and limits unchanged.

## October 18 — native receiving immutable facts verified locally

The composition/freeze milestone is committed locally as `06cc8c9cf`; its
complete-target evidence remains below. The reviewed local implementation
introduces `nativeReceivingV1`, a distinct canonical receiving assertion
containing exact `nativeFreezeV3` bytes, historical membership bytes,
binding/queue/observation identity and execution kind/generation. A
domain-separated digest binds all of these facts. Existing consumer V1 and
legacy authority retain their meanings.

Pending readback requires the actual matching membership row. Retained readback
requires its absence and exactly one package revision beyond freeze for the tier
promotion. Later ownership transfer does not alter the frozen package. Current
original reverse references and derivative joins are checked separately from
historical membership; no membership row is fabricated and no physical-file
availability is inferred. The receiving readback cap includes the context, live
membership and receiving payload. It does not replace full admission accounting
for acquisition receipts, cleanup projections and result headroom. Canonical
lowercase UUID queue/observation identities apply to fresh native receiving
only; legacy V1 identities are unchanged. Qualification remains closed to
receiving rows.

This candidate is read-only fact validation, with synthetic receiving fixtures.
It does not implement or accept atomic queue admission, promotion, terminal
cleanup, executor use or Capture/Auth composition. Those remain next under the
single-session agreement, followed by integrated media acceptance and the
approved version actions/redesign. Mutable routing still requires a typed
queue/job/result transition witness; the immutable digest alone cannot authorize
a transfer.

The exact reviewed candidate02 passed all 40 methods in five focused suites,
with zero failures, skips or Xcode runtime warnings. All 2,834 source/project
hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-receiving-20261018/focused02-result.json`, XCResult
`e816a251145443f587fb021b7ae83c81`; candidate02 SHA256
`446c4646600d58d2e8f7d90ad00642a29e3b5b792254c2e25a31b21354ddd613`. The failed
focused01 test-helper compilation is retained. The prior complete 6,286-method
target belongs to the preceding freeze checkpoint; it was not repeated for this
read-only increment. These are shared-checkout local checks, not
isolated-source, device, hosted or activation acceptance.

Next are the reviewed legacy/native queue and funding guards, then typed
admission, retained transitions, cleanup and Capture/Auth integration.
Activation stays disabled, PR116 frozen, deployment hold active, AWS unapproved
and limits unchanged.

## October 18 — two-original composition and native freeze verified locally

The combined composition/freeze candidate passed the complete `merianTests`
target: 6,286 methods, 10,130 parameter-expanded executions, zero failures, zero
skips and zero Xcode runtime warnings. All 2,831 source/project hashes and all
candidate hashes stayed unchanged. Focused03 also passed all 30 expected
methods, including all 14 freeze methods. This is shared-checkout local
evidence, not isolated-source, device, hosted or activation acceptance.

Exact source candidate03:
`e619e3985dde6aab1f4ac835eb0cf2518f0dfef5aa3eed057dcc3b5a80711d26`. Evidence:
`.artifacts/native-freeze-20261018/full03-result.json` and retained XCResult
`2b1fbc3d398a4ae38f417d523c4a55e9`. Independent and IC-1 reviews cleared this
exact source and execution scope before the runs. The earlier multipair
compiler/assertion failures remain in `.artifacts/native-multipair-20261018/`;
corrected focused05 and the complete current target passed. Earlier dated
entries below remain historical evidence.

The native owner now supports two distinct prepared originals and a terminal
`nativeFreezeV3` save binding their explicit order, immutable supporting bytes,
previous envelope/membership hashes and exact revision transition. Original,
AI-input and display identities stay separate. Frozen packages permit
independent new drafts while rejecting metadata or pair retirement changes to
the frozen package. Exact saved acknowledgement is recoverable without new
preparation; it does not promise current physical availability. Current file
identity and hash verification remain mandatory before new use. Historical V2
codecs retain their prior meaning. Freeze creates no consumer, queue or
inference authority.

Next is native receiving ownership and Capture/Auth integration. The reviewed
composition uses the existing app container and one native session/fence, with
one account-work lease per operation and registration before opening awaits. A
failed drain remains sealed. Admission must save freeze, consumer, queue,
deterministic job and event together; legacy enqueue/job-reset/deletion helpers
cannot provide this transaction. Retained consumers preserve exact historical
membership bytes, while current references and file availability are checked
independently. Reanalysis shares into a fresh pending package; existing retained
versions remain immutable. Retirement precedes drain and last-reference cleanup.
The detailed read-only review map is
`.artifacts/native-freeze-20261018/receiving-integration-map.json`.

Integrated photo/audio/video acceptance, individual-version deletion and exact
original export, then the approved Identification/History redesign remain
required in that order. The capture-tools visual refactor remains separately
owned. Activation is disabled, PR116 is frozen, the deployment hold is active,
AWS is unapproved and numeric limits are unchanged. Local work continues without
routine proceed prompts; no push, merge, deployment or hosted test is
authorized.

## October 18 — native two-original composition candidate

Paired-file recovery/retirement was committed locally as `0b38d560e`; its
passing full-target evidence and two disclosed test-fixture QoS warnings remain
below. The next candidate supports two distinct originals with one ready
derivative pair each. Recovery and retirement select an explicit pair; ambiguous
package-only selection fails. The first pair's immutable intent, work facts,
file identities, published revision and bytes survive preparing, abandoning or
removing the second. Only one preparation attempt or unfinished pair may own
processing at a time.

Original acquisition may follow a ready pair. Admission counts original
references against the existing two-original cap, while the complete graph
retains its six reference bound. Package phase reflects active preparation,
unfinished pairs or outstanding original acquisition; a ready survivor does not
hide held work. Acquisition and preparation exclude each other in both
directions. Fresh metadata, sharing, original removal and ready-pair retirement
cannot mutate unfinished work; exact recovery remains available. Prepared
originals require explicit pair retirement before original removal.

Accounting charges all ready-pair cleanup projections and each physical
allocation and logical reference once, plus the one active reservation. Full
encoded metadata must fit the unchanged allowance before processing or file
ownership. Drafts and survivors remain intact on capacity failure. No schema,
numeric limit, activation, legacy reader or provider-dispatch authority changes.
Membership rebuilding uses a narrow ready-pair proof only during transition;
complete aggregate validation and exact readback still precede successful
saves/results.

Evidence: `.artifacts/native-multipair-20261018/`. Source parsing, generation
and project validation are complete; exact independent/IC-1 review and focused
runtime qualification are pending. Tests cover late acquisition, two-ready
reopening, second-pair interruption/retirement, held acquisition cleanup,
active-work exclusion, capacity denial and cross-pair identity collisions. This
entry does not claim runtime acceptance. Freeze, receiving consumers, Capture
composition, integrated acceptance, version deletion/export and the approved
redesign remain next. Activation disabled, PR116 frozen, deployment hold active,
AWS unapproved; local work continues without routine proceed prompts.

## October 18 — native paired files locally verified

The inactive native owner now reserves both outputs atomically, creates
exclusive partials, saves their descriptors before writing, completes exact
bytes and publishes the pair. Recovery may finish only the saved bytes;
reopening inspects without repeating preparation. Original bytes and supporting
text remain intact. One pair is supported at this checkpoint. Multi-original
composition, freeze, receiving consumers and live Capture integration remain
pending.

Retirement saves one canonical closure on the AI lease and an exact digest
marker on its display sibling. It binds the prior state, immutable intent,
envelope, prior/successor membership, writer epoch, retirement identity and both
file identities. Both liabilities remain until both absence proofs pass in one
fenced transaction. Cleanup retries cannot adopt replacement bytes or delete
originals. Maximum closure/state encodings stay reserved within the existing
metadata allowance; retirement releases processing scratch while retaining
unfinished output reservations. No numeric limits or activation gates changed.

Evidence: `.artifacts/native-pair-files-20261018/`. Candidate06
(`497f4d194e1469c637ec08f7cc812506a79c470cbe4d0e96965dd2dfb33753bc`) passed 35
focused methods plus two explicitly verified method selectors. Full06 passed all
6,264 methods (10,090 executions), with no failures or skips. All 2,826
source/project hashes and all candidate hashes stayed unchanged. The result is
`a414c6ef15384c46ad15eb124b9f83ce`. Two runtime priority-inversion warnings were
recorded in unchanged `TestSupport/VideoAudioFixture.swift:163`, both in
`ObservationRetainedVideoTests.nonSquareTransformedDurationBoundaries(audio:)`;
these are retained in `full06-summary.json`, `full06-object.json` and
`full06-result.json`. This is a passing shared-checkout test result with those
fixture warnings, not a warning-free or isolated-source claim.

Exact independent and IC-1 reviews cleared candidate06 and the execution
packets. XcodeGen, project validation, parse, scoped diff checks and Markdown
formatting passed. Failed compiler/runtime candidates and the selector shell
failure remain retained. Full05 passed 6,262 methods and failed only the two
600-line architecture guards; candidate06 moved pure admission checks and
descriptor-relative empty traversal to existing helpers while retaining owner
identity checks, the root lock, namespace unlink and root fsync. No allowlist or
limit was weakened. Full05 result `ca3232477f1a40ecadbb3084b9fd4904` remains
historical failed evidence.

Continue automatically through the reviewed local commit, native two-original
composition and freeze, receiving ownership, integrated acceptance, individual
version deletion/source export and the approved redesign. The next composition
must preserve ready survivors, select pairs explicitly, account for all paired
metadata, and exclude new acquisition/preparation in both directions while work
is unfinished. Exact replay and recovery remain available. Activation disabled,
PR116 frozen, deployment hold active, AWS unapproved; no external operations or
device installation.

## October 18 — native pair plans locally verified

The inactive native owner now durably transfers an exact preparation attempt
into an immutable output plan, with both child work rows, bounded metadata
reservation, exact save-acknowledgement recovery and explicit no-file
abandonment. Draft text, original bytes and sequence survive abandonment; stale
plans cannot release newer work. Global unfinished-work admission and
bidirectional row audits remain closed to output files and ready/retained pairs.

Candidate03 (`a2e48e0b3e03d115a0c3e9cbfa065674b3fc2756a0a20f165b7ccf0effaf3265`)
passed six focused suites: 52 methods, no failures, skips or runtime warnings.
All 2,820 source/project hashes remained unchanged. Exact independent and IC-1
reviews cleared execution. Failed candidate02 is preserved; its duplicate
package registration was corrected by ordering the existing preparation charge
after package registration, with no amount or limit changes. Evidence:
`.artifacts/native-pair-plan-20261018/`, result
`3c71ef9df01c47d0b6609375802deda5`. This is scoped shared-checkout validation.

Continue native paired-file reservation/write/retirement/recovery and ready
publication, then freeze, receiving consumer ownership, live composition and
required acceptance. Version deletion/source export and the approved redesign
remain required afterward. Activation disabled, PR116 frozen, deployment hold
active, AWS unapproved; local work only. No routine proceed approval is needed.

## October 18 — native preparation reservation and worker cleanup locally verified

The inactive native owner now reserves output and metadata capacity before photo
processing, retains an exact V2 attempt, and preserves unfinished work for
explicit recovery. Compact prepared identities avoid recursively retaining old
draft envelopes. The concrete processor uses the existing image pipeline under
the original-file owner; processing results remain in memory until native paired
file publication is implemented. Core focus detection now separately tracks its
visible deadline and actual worker termination, so account transition waits for
actual drain.

The complete gate exposed video cleanup and preview-test readiness races. Video
join/timeout paths now drain children and explicitly discard late owned outputs;
audio extraction retains intermediates across the actual detached result and
cleans them before return. Borrowed originals survive. Explicit lease discard is
idempotent; failed unlink remains nonaccepting and retryable. The preview
fixture now awaits initial player readiness before measuring position. Failed
full12 evidence remains retained; the corrected candidate14 has independent and
IC-1 concurrence.

Candidate14 SHA-256:
`87b6aaefdf1cc93b45d535df5c97a6122ee5c4293f9d6e6cba9e16dcc18d9f26`. Five focused
suites passed 28 methods / 31 executions, then the complete `merianTests` target
passed 6,246 methods / 10,047 executions. Finalized results
`41c54f27b342403fb8a70f999d75cd8a` and `9a4fa521b94c4355936171e7b6a44779` have
zero failures, skips and runtime warnings. All 2,815 source/project hashes
stayed unchanged during verification. Compiler and test-fixture diagnostics
remain preserved in logs; this is shared checkout validation, not
isolated-source or live-composition acceptance.

Native paired-file admission/recovery/freeze, receiving consumer ownership,
Capture/Auth/queue/history composition and integrated acceptance remain open.
The reviewed next transition design requires exact state witnesses,
counter-aware retirement and identity-bound cleanup. Pending graph bounds must
not cap the retained library: audit all retained pages and both directions of
every join. No fresh identification or reanalysis may proceed without actual
photo, audio or video; historical admitted recovery semantics remain unchanged.
After required acceptance, continue individual-version deletion/source export
and the approved redesign. Separate capture visual ownership is unchanged.

Evidence: `.artifacts/native-preparation-integration-20261018/`. Activation
disabled, PR116 frozen, deployment hold active, AWS unapproved. Local work only;
no push or external action. Earlier entries are historical.

## October 18 — native explicit pending abandonment locally verified

The next inactive native integration adds exact-request abandonment of reserved
or held acquisitions. Reopening, inspection and generic recovery preserve raw
unfinished files and their full reservation; they never infer abandonment,
repeat a loader or invoke AI. Explicit abandonment requires the registered
owner's serial operation and exclusive file fences after prior work has drained.
It saves a strict, bounded cleanup proof before file work. The proof binds the
original request fingerprint, namespace and optional parent identities, and the
exact absent, partial or final file descriptor. A current-lifetime sealed
capability permits only matching unlink, directory sync and absence recheck.

Saved abandonment is recoverable across process epochs. Changed files or parents
block recovery; missing rows, age or cancellation do not prove release. Atomic
release removes only the pending work/allocation/lease, records the existing
terminal receipt and exact membership successor, and preserves other originals,
supporting text and the empty draft. Recovery queries one fresh saved intent at
a time. Proof bytes consume the existing result-encoding reservation; no schema
or numeric limit changes. Legacy validators remain closed to this native-only
substate. Typed lifecycle orchestration and sealed disposal values move
together; raw admission, controller and native authority constructors stay
co-located, with private file descriptors retained by the original file owner.

Independent and IC-1 review cleared the implementation and exact execution
packets. The first focused run exposed a test expectation error: cancellation
leaves pending settlement closed until uncancelled drain finishes the held
transition. Candidate02 corrected only that test to require drain and reopen;
the runtime was unchanged. The failed result and both packet-review corrections
remain retained. Thirteen focused suites passed 116 methods / 289 executions;
the complete native target passed 6,215 methods / 10,005 executions. Both
results have zero failures, skips and runtime warnings. Existing compile
warnings in unchanged code remain in the logs.

Finalized results are `5db93abacc964e77b34198a6d46bd86a` and
`adf9c90bd2414d6b8ceb0e53e2df5536`. Candidate sources and all 102 unrelated
baseline states remained unchanged through both runs. Each run removed only its
100 emitted synthetic fixture directories after host exit. This is local
shared-checkout qualification of inactive native sharing/removal/recovery; final
live Capture/Auth/queue/history composition and end-to-end acceptance remain
pending. Separate capture visual ownership stays unchanged. Evidence:
`.artifacts/shared-media-native-pending-cleanup-20261018/`. Activation is
disabled, PR116 frozen, Supabase deployment hold active and AWS unapproved.
Earlier entries are historical.

## October 18 — native sharing, removal and retirement recovery locally verified

The inactive registered native owner now supports sharing into a new
same-account pending draft, reference removal, and completed-original retirement
recovery. Sharing updates paired references, pending membership and the physical
reference counter in one save without copying bytes or changing the source
membership. Existing destinations are rejected. Both counter value and revision
are frozen with the inventory and source package/reference preconditions.

Removal preserves supporting text and stable original ordinals. Removing the
last photo leaves an empty pending draft; fresh identification still requires
media. Explicit whole-draft discard remains separate. Nonfinal removal preserves
survivor bytes. Final removal saves the existing V2 retirement and keeps its
physical charge until exact descriptor-bound unlink, directory sync and absence
proof permit atomic accounting release. Lost acknowledgements use exact saved
state. Later mutation or missing rows alone cannot prove logical success or
recreate references. Dedicated recovery accepts saved retirement while ordinary
mutations remain blocked. Reserved/held acquisition cleanup requires its
separate writer-closure proof and remains held; recovery never repeats a loader
or AI call.

The registered controller, raw admission and sealed capability constructors stay
co-located. Read-only eligibility and namespace inspection move to typed
helpers. No active schema, numeric limit, provider or live composition changes.
Independent and IC-1 reviews cleared exact candidate02 after correcting two
review findings: lost-acknowledgement checks now require the exact canonical
membership successor, and recovery queries one fresh retirement at a time until
none remain. Candidate01 is retained as unrun review-hold evidence.

Twelve focused suites passed 103 methods / 254 executions; the complete native
target passed 6,202 methods / 9,970 executions. Both finalized results report
zero failures, skips and runtime warnings: `1da84328952a472dba6e9657963b5939`
and `22ecb952812e49c6b14fe92696a17ae4`. Source and all 102 unrelated baseline
hashes remained unchanged. Each run removed only its 65 emitted synthetic
fixture directories after the compiler and test host exited.

This is shared-checkout native qualification, not isolated-source or live
Capture/Auth/queue/history acceptance. Continue the independently and IC-1
reviewed explicit abandonment/cleanup of unfinished native acquisitions: raw
reserved/held items stay retained and charged until an exact explicit
abandonment saves cleanup intent; cold recovery may finish only saved intent.
Draft text and other originals remain intact. Final composition remains pending.
Evidence: `.artifacts/shared-media-native-lifecycle-20261018/`. Activation
disabled, PR116 frozen, Supabase deployment hold active, AWS unapproved. Earlier
entries retain historical evidence.

## October 18 — native draft metadata locally verified

The inactive registered native owner now prepares metadata-only draft edits.
Requests bind the inventory, account, package/draft generation, prior revisions,
exact prior envelope and unchanged membership tuple. Desired validated envelope
bytes are produced once and retained across retries. Inventory and package
advance once; membership bytes and revision do not change. Exact post-save
readback precedes old-state CAS; later edits are stale even when their text
matches. Fresh ownership and exact old-state checks run immediately before save.

Presentation entries must resolve to live same-package/same-owner originals and
their paired shared references. Existing geometry/duplicate bounds remain. The
native graph audit now validates these entries instead of rejecting all nonempty
presentation. Metadata, membership and receipt headroom share the unchanged
budget; positive envelope growth adds free-space demand, with no advance credit
for shrinkage. Readback queries return only values under repository-minted
authority; contexts, constructors, account drain and file authority remain
sealed.

Independent review found and corrected repeated full-graph auditing in the
extracted paged reader before execution. A separate sealed inspection authority
now checks the expected header/account lease per page; each receipt must belong
to the current owner. Mutation authority remains unchanged. A 257-receipt test
proves one three-page snapshot performs only its two boundary full audits.

Independent and IC-1 review cleared exact candidate04. Ten focused suites passed
81 methods / 224 executions; the complete native target passed 6,187 methods /
9,947 executions, with zero failures or skips and no recorded runtime warnings.
Finalized results are `605c37a7e42b48c5a94c65aae3918b8a` and
`21e915d769f845deb0298fc328b82024`. Source and all 102 unrelated baseline hashes
remained unchanged. Each run removed only its 42 emitted synthetic fixture
directories after the test host exited. Earlier review holds remain retained.

No saved submission, file, provider, sharing, deletion, schema or numeric limit
changes. Evidence: `.artifacts/shared-media-native-metadata-20261017/`. This is
shared-checkout native qualification, not isolated-source or live
Capture/Auth/queue/history acceptance. Native sharing/removal/recovery and final
composition remain pending in the documented order. Activation stays disabled,
PR116 frozen, Supabase hold active and AWS unapproved. Earlier entries retain
historical evidence.

## October 17 — native atomic acquisition locally verified

The inactive registered fixture controller now prepares atomic original
reservation, completion and held settlement. A sealed capability minted only by
the fenced repository validates current account dispatch and store/root identity
immediately before the sole save. Completion consumes an unforgeable file
inspection, with separate exact byte identity and full descriptor facts. Private
transaction contexts retain the pristine full-graph audit, assert exact
changed-row postconditions, and jointly save receipt, package, membership,
allocation, lease and reference accounting. Hold preserves membership bytes and
revision and the full reservation. Any unresolved acquisition or retirement
intentionally blocks fresh acquisition until a separately qualified recovery
owner resolves it; no capacity is released here.

Exact completed replay returns the original saved result. Reserved/held cold
requests cannot restart a loader. Uncertain save/readback can only reconcile the
same operation. Account shutdown waits for actual callback/file termination.
Verified durable held settlement preserves liability while permitting process
fence release; unknown settlement keeps fences and admission sealed. An explicit
failed-drain retry may reconcile the exact saved state without dispatching work.

Independent and IC-1 review cleared exact candidate08. The nine focused suites
passed 67 methods / 199 executions; the complete native target then passed 6,173
methods / 9,922 executions, with zero failures or skips. Finalized results are
`4349aedd71094fbe98e7ac9ae653040e` and `48036d6b2b7f41f58da8a6fcd30f714c`. Exact
candidate and 102 unrelated baseline hashes stayed unchanged. Each run removed
only its 17 emitted synthetic fixture directories after the test host exited.
Full-target evidence retains Xcode's 600-second simulator-diagnostics collection
timeout and two VideoAudioFixture QoS warnings; neither caused a test failure.

Earlier compiler failures and the interrupted candidate06 run are retained. The
user explicitly authorized stopping that failed, stuck run. Its partial result
is unfinalized and contributes no passing coverage. The correction reuses the
single captured draft encoding, wakes a test gate when acquisition fails before
loading, and avoids unlinking live SwiftData databases. The failure regression
and previously stuck account-drain case pass in both corrected runs.

Evidence: `.artifacts/shared-media-native-acquisition-owner-20261017/`. This is
shared-checkout native qualification; isolated-source acceptance and live
Capture/Auth/queue/history composition remain pending. Continue native draft
metadata, sharing/removal/recovery and final composition in the documented
order. This does not close photo-storage or whole-feature acceptance. Activation
stays disabled, PR116 frozen, deployment hold active, AWS unapproved and all
limits unchanged. Earlier entries retain their historical scope.

## October 17 — registered native original admission locally verified

The inactive Debug fixture controller now registers its mandatory account drain
before asynchronous admission. It holds the existing store/root/namespace
fences, rejects overlapping opens and waits for actual audit termination on
cancellation. A dedicated I/O actor verifies completed bytes and saved directory
identities; retiring absence requires the exact saved directories and no final
or partial. The final complete namespace stream rejects unjoined or replaced
leaves after awaited reverse checks. This is fenced cooperative-owner
validation, not an atomic snapshot against arbitrary external filesystem
mutation.

The original empty-only factory keeps its restrictions. The new read-only
controller can inspect complete native original graphs, including retained
sharing after physical-origin deletion; reserved/held/retiring work remains
recovery-only. It grants no mutation, loader restart or cleanup capability. Live
Auth installation, atomic acquisition transitions, complete-target and
isolated-source qualification remain pending. Independent and IC-1 review
cleared candidate03 after correcting account binding and lease-release ordering
before execution. Its eight-suite run passed 55 methods / 181 executions and
failed one retained-sharing fixture whose draft identity differed from its
package identity. Candidate04 changed only that fixture; the admission suite
then passed all 9 methods / 35 executions with zero failures/skips. The other
seven passing suites are reused unchanged: composite focused coverage is 56
methods / 182 executions, not a clean eight-suite rerun.

Failed XCResult `93c06d249aa54786a39a1ccdeb6afe4a` and passing XCResult
`a8a1d4f8694f4a8da97db8f6bbff2c80` are retained. Xcode's failed-run simulator
diagnostic collection timed out after 600 seconds; no managed build was
cancelled or duplicated. Candidate and 102 unrelated baseline hashes remained
unchanged through each run. Project and Markdown gates passed. Evidence:
`.artifacts/shared-media-native-admission-20261017/`. Continue the
already-reviewed atomic reserve/commit/held integration, then full native and
isolated-source acceptance before live queue/history composition. Activation
stays disabled, PR116 frozen, Supabase hold active, AWS unapproved and existing
limits unchanged. Earlier entries below retain historical scope.

> October 17 inspection continuation: native namespace observations now await
> their owning actor while retaining and rechecking ancestor/leaf descriptors.
> Cancellation cannot detach a suspended observer. Independent/IC-1-reviewed
> candidate02 passed six focused suites (42 methods / 87 executions, no
> failures/skips), after retaining candidate01's pre-test SwiftLint failure.
> Evidence: `.artifacts/shared-media-native-async-inspection-20261017/`. This is
> scoped shared-checkout qualification only. Native admission remains
> empty-only; the registered admission controller, complete file audit, atomic
> transitions and full-target acceptance remain pending. Activation stays
> disabled, PR116 frozen, Supabase hold active, AWS unapproved and limits
> unchanged.

## October 17 — native acquisition graph and metadata locally verified

The inactive native acquisition prerequisite now checks receipt/work/asset/lease
and reference joins in both directions, including orphan and terminal conflicts.
Surviving original references preserve submitted provenance; completed results
remain immutable after distinct sharing references replace the original owner.
Only the exact native inventory mode, ready phase and empty cursor qualify.

Pending accounting pages physical-origin receipt charges and projects every
combination of the existing two originals completing. Receipt result headroom
and membership growth remain inside the existing 1 MiB metadata allowance and
contribute to outstanding free-space reservations. Retained-library occupancy
has no new count limit and does not consume pending slots.

Independent and IC-1 review cleared candidate02 after source-review corrections
before execution. All seven focused suites passed: 54 test methods, 215
parameterized executions, zero failures/skips. Exact source and 102 unrelated
baseline hashes stayed unchanged. Project and Markdown checks passed. Evidence:
`.artifacts/shared-media-native-transactions-20261017/`; XCResult
`.artifacts/local-ios/2e21d6f843a74d608d71f0e5a2ecd579.xcresult`. This is scoped
shared-checkout qualification, not complete-owner or isolated-source acceptance.

The helpers grant no admission or file authority. The constructor stays
empty-only until complete off-main-actor namespace/hash qualification and the
closed atomic reserve/commit controller qualify. Continue that integration, then
the complete native target and atomic queue/history ownership. Activation
remains disabled, PR116 frozen, the Supabase hold active, AWS unapproved and
existing limits unchanged. Later version-actions/redesign remain required.

## October 17 — native photo namespace traversal locally verified

The native read-only traversal now streams fixed-depth canonical directories and
original/partial leaves without a retained-library count cap or whole-library
token set. It holds ancestor descriptors, checks named/opened identity around
recursion and observers, rejects partial/final collisions and unsafe entries,
and distinguishes cancellation and enumeration errors from success. Final files
must be positive; empty partials remain structural recovery observations only.
Legacy inventory limits and all product limits are unchanged.

Independent and IC-1 review cleared candidate02 after correcting zero-final
rejection before execution. All six focused suites passed: 41 test methods, 84
parameterized executions, zero failures/skips. Exact source and 102 unrelated
baseline hashes remained unchanged. Project and Markdown checks passed.
Evidence: `.artifacts/shared-media-native-namespace-20261017/`; result
`.artifacts/local-ios/a72483178e4b48bd890a42ebcc799079.xcresult`. This is
focused shared-checkout evidence, not full-target or isolated-source
qualification.

The traversal is not a globally atomic filesystem snapshot. The native owner
must exclude cooperating writers, join exact receipt/graph ownership, reverse-
audit missing files and revalidate bytes before use. No callback may commit
partial authority. Native admission remains empty-only. Continue the reviewed
closed acquisition transaction integration, then atomic queue/history ownership
and the later approved version-actions/redesign. Activation remains disabled,
PR116 frozen, Supabase hold active and AWS unapproved; no external action
occurred.

## October 17 — native acquisition receipt codec locally qualified

The V64 receipt now has a closed, versioned codec for immutable picker/camera
original requests, exact completion results, held work and terminal replay
witnesses. Cold recovery starts from the persisted row, including terminal rows
that retain no request. A separate expected-intent check rejects substitutions.
Canonical encodings reject unknown or duplicate fields and preserve historical
UTI values without asking the current OS to decode media. The internal 8 KiB
completion headroom stays within the existing 1 MiB metadata allowance.

Independent and IC-1 review cleared the exact candidates. The initial five-suite
run passed 36 test methods and failed one because its changed-size fixture used
the original value. The corrected codec-only run passed all 13 methods with zero
failures or skips; the other four unchanged suites remain passing. Failed result
`37907a7d09fc47de8be932c74fbd17e6.xcresult` and passing correction
`1ada1289441f4b368d313c16da2c28d1.xcresult` remain under
`.artifacts/local-ios/`. Candidate and 102 unrelated baseline hashes stayed
unchanged during execution. Project and Markdown validation passed. This is
composite local shared-checkout codec evidence, not an integrated native owner,
a fresh full-target run or isolated-source acceptance. Exact candidates, review
and results: `.artifacts/shared-media-acquisition-codec-20261017/`.

Continue native reserve/commit, complete streaming namespace and reverse-receipt
audits, combined package metadata accounting, and atomic queue/history
ownership. The codec alone grants no writer restart, file, cleanup or admission
capability. Activation remains disabled, PR116 frozen, Supabase deployment hold
active, AWS unapproved and limits unchanged. Later version-actions/redesign
remain required.

## October 17 — V64 acquisition receipt foundation validated locally

The outgoing V63 schema was frozen and compiled before the additive V64
acquisition receipt model was introduced. The receipt stores immutable request
identity and supports full result retention and a minimal terminal replay
witness. Migration preserves existing native ownership and historical text-only
records and creates no receipts. Legacy and empty-native fixture owners reject
all receipt rows; the model grants no writer, media, cleanup or live authority.

Independent and IC-1 review cleared the exact candidates and the correction.
Focused migration/recovery/storage verification passed 140 tests. The complete
native run passed 6,118 and failed two architecture inventories because the
storage repository reached 601 lines. Consolidating its identical guards in the
existing lookup owner preserved behavior and reduced it to 587 lines; all 43
tests in the five affected storage/purge/architecture suites then passed. No
tests were skipped. These are composite shared-checkout results, not a clean
full run of the corrected candidate or isolated-source acceptance. Static
migration, project, CI-tooling and Markdown checks passed. Candidate and the 102
hashed unrelated baseline paths remained unchanged during validation. Evidence:
`.artifacts/shared-media-native-receipt-20261017/`; failed full result
`bbf6648481124cc0a687569f711c3263.xcresult` and correction result
`dd3c0c6e22674ef79185224f29477ca8.xcresult` remain under
`.artifacts/local-ios/`.

Continue the closed receipt codec and native reserve/commit owner, full
namespace and reverse-receipt audits, and atomic queue/history ownership. The
codec design preserves exact bounded ImageIO UTI values without later OS decoder
dependence; completion headroom and projected memberships share the existing 1
MiB metadata allowance. Held work cannot restart or acquire cleanup authority
from a receipt. The schema foundation does not close native integration or later
approved version-actions/redesign acceptance. Activation remains disabled, PR116
frozen, Supabase deployment hold active, AWS unapproved and product limits
unchanged. No push, merge, deployment or hosted action occurred.

## October 17 — native empty-store owner and exact namespace reopen verified

The Debug-only native fixture owner now admits only pristine or exactly reopened
empty stores. It fences eligibility and binding work, saves the native inventory
and bootstrap together, and rejects partial initialization, mismatched metadata,
legacy graph adoption and real Documents/Application Support roots, including
resolved aliases. Shared photo and inbox reopen no longer recreate missing
namespaces; standalone photo creation remains unchanged. Held directory
replacements fail closed. This empty-only owner grants no media mutation,
cleanup or live composition authority; cold empty-directory inode continuity is
not claimed.

Independent and IC-1 review cleared candidate02. All four focused suites passed
65 tests; the complete native target passed 6,118 tests with zero failures or
skips. Candidate and unrelated baseline hashes stayed unchanged. Evidence:
`.artifacts/shared-media-native-owner-20261017/`; full result
`.artifacts/local-ios/5cf61ea06144431d842a5d1e4332904f.xcresult`. The first
unexecuted candidate's resolved-path admission gap and its correction remain
recorded. This is shared-checkout validation, not isolated-source or live
acceptance.

Continue the closed native reserve/commit owner and complete namespace audit.
Review found that existing P1 reservation rows do not preserve the full
immutable native request. Independent and IC-1 design review concur on an
additive versioned acquisition receipt, exact same-operation recovery, terminal
replay rejection, an explicit partial/final presence matrix and single-save
descriptor-bound absence settlement. The outgoing schema must be frozen and
compiled before the additive model change. Receipt encoding, migration and
transaction implementation remain unqualified; no existing operation is
converted or replayed. Pending accounting limits stay unchanged and retained
physical ownership remains separate.

Activation remains disabled, PR116 frozen, the Supabase deployment hold active
and AWS unapproved. No push, merge, deployment, hosted action or numeric-limit
change occurred. Native queue/history ownership and the later approved
follow-ups remain unfinished.

## October 17 — native original reverse-reference audit locally verified

The read-only original audit checks saved reverse counts independently against
both complete reference directions, including retained packages and missing
physical-origin packages. It rejects orphan or substituted edges, missing
counters, inconsistent owner/generation/lease facts and dirty contexts. Zero
requires positive retirement revision, the exact V2 descriptor byte count and
one final retired pair. The caller must hold an unchanged native store fence;
this snapshot grants no mutation, media or cleanup authority. Pages bound row
materialization, not total database work or measured memory.

Independent and IC-1 review cleared accounting candidate03. Focused coverage
passed 51 tests; the complete native target passed 6,109 tests with zero
failures or skips. Candidate and unrelated baseline hashes stayed unchanged.
Evidence: `.artifacts/shared-media-native-accounting-20261017/`; full result
`.artifacts/local-ios/461182f8231345f1b58f86a6259af1fd.xcresult`. The initial
unexecuted candidate's zero-state gaps and the later paging-offset compilation
failure remain recorded. This is shared-checkout validation, not isolated-source
or live acceptance.

Continue the closed native owner, paired writes, exact memberships, whole-store
and namespace validation, and atomic queue/history ownership. The next private
fixture factory uses distinct native bindings and preserves legacy refusal;
shared reopen must reject missing namespaces without recreating them. These
remain implementation work, not completed native composition. Activation stays
disabled, PR116 frozen, the deployment hold active, AWS unapproved and numeric
limits unchanged. No push, merge, deployment or hosted action occurred.

## October 17 — pending graph and native retirement format locally verified

The bounded pending graph follows logical package references, reservation work,
handoffs and derivative pairs independently of an allocation's physical-origin
package. Exact membership checks reject missing, stale or over-budget saved
assertions. The native-only V2 retirement format binds the stable retirement,
asset/generation, inventory/generation, account and descriptor facts within the
unchanged 512-byte allowance. Qualification V1 remains separate and unchanged.
Neither helper grants mutation, file access, cleanup or provider authority.

Independent and IC-1 review cleared candidate03. Pending-graph focused coverage
passed 40 tests; the codec passed five methods and the separately selected real
filesystem roundtrip/release case passed. The complete native target then passed
6,103 tests with zero failures or skips. Candidate and recorded shared-baseline
hashes remained unchanged. This is shared-checkout validation, not
isolated-source or live acceptance. Evidence:
`.artifacts/shared-media-pending-20261016/`; full result
`.artifacts/local-ios/4e832e68b3c54a8fad056b966735301c.xcresult`. The earlier
actor-isolation compile failure, simulator no-launch failure, omitted-method
coverage gap and shell-selector failure remain retained.

Continue the reviewed closed native accounting operations, paired reference and
count updates, exact pending memberships, complete native audit and atomic
queue/history ownership. A dedicated native validator must preserve legacy
qualification rejection of retained/V2 states. Native composition remains closed
until these owners and their acceptance gates are complete. Activation stays
disabled, PR116 frozen, the deployment hold active, AWS unapproved and numeric
limits unchanged. No push, merge, deployment or hosted action occurred.

## October 16 — V63 consumer ownership foundation locally verified

V63 freezes V62 and adds explicit consumer authority, pending membership,
inventory bootstrap and reverse-reference metadata. Legacy rows retain their
semantics. Canonical, bounded cohort joins bind exact originals, AI inputs,
previews and supporting context; they grant no file, cleanup or provider
authority. Nonempty native metadata blocks the old qualification owners.

Independent and IC-1 review cleared foundation candidate08. The focused run
passed 115 tests with zero failures or skips, including disk migration/cold
reopen, lexical keyset pagination, malformed ownership, exact pending membership
and orphan cleanup barriers. Sources remained unchanged through the run.
Evidence: `.artifacts/shared-media-consumers-20261016/`; result
`.artifacts/local-ios/105372ecfbee4974aef38d9c34da8fae.xcresult`. The complete
native target on candidate09 passed 6,092 tests and failed one stale
purge-inventory assertion, with zero skips and unchanged pinned sources.
Candidate10 added the four new entities to the existing saved/unsaved purge
barrier fixtures without changing runtime code. Independent and IC-1 review
cleared the targeted rerun: all five tests passed with unchanged sources. Reuse
the 6,092 unaffected passes; the failed full result remains failed evidence, not
a clean full rerun. Earlier failures and corrections are retained. This is
shared-checkout qualification, not isolated or live acceptance.

Continue the reviewed pending-membership transaction owner, retained accounting,
atomic queue/result ownership, native composition and remaining acceptance.
Pending slots begin at package creation; retained packages do not consume those
slots. Shared asset release must consider all surviving consumers. New initial
and reanalysis requests still require photo/audio/video media, with optional
supporting text; historical records and admitted recovery retain their meaning.
The later version actions and redesign remain authorized follow-ups. Activation
stays disabled, PR116 frozen, the deployment hold active, AWS unapproved and
numeric limits unchanged. No external action is authorized by this foundation.

## October 16 — durable shared-library cleanup locally validated

The isolated shared inbox owner now has an explicit whole-library purge path. It
saves a versioned, stable reset intent before cancellation, drains its tracked
work, then uses sealed cleanup authority for exact retirement and release.
Restart accepts only the same purge ID through the cleanup constructor. Normal
construction and preparation remain closed. Cleanup orders detached liabilities
and unheld sources before abandoning the remaining handoff, preserving the
unchanged 96 MiB acquisition bound without a new reservation.

Prepared-held envelopes remain immutable. Per-package `purging` is valid only
inside the durable inventory purge. Originals are unlinked after the last local
reference; interrupted release reconciles only saved exact identities.
Completion requires empty shared/P1 graphs and physical namespaces, while
retaining the closed inventory and root bindings. The ordinary liability barrier
stays broad. A typed purge-service seam verifies the same container and terminal
state; legacy P1 namespace presence still blocks ordinary erasure. Reset
projections are deferred until the complete library purge succeeds. No live
composition or automatic reopening is added.

Independent and IC-1 review cleared candidate07. Its purge rerun passed 15
methods / 31 parameterized cases; the complete native target passed 6,081 tests
with zero failures or skips. Source hashes stayed unchanged during both
successful runs. XcodeGen/source membership, Markdown and scoped diff checks
passed. Evidence: `.artifacts/shared-media-purge-20261016/`; full result
`.artifacts/local-ios/1d56d47ebb38427d9d196391e703da42.xcresult`.

Earlier compilation failures and focused03's incorrect lost-ack expectation are
retained. The latter test correction occurred after its compiler/test host had
exited while Xcode still collected diagnostics; the execution-time source pins
and post-execution edit disclosure are retained. No
unchanged-through-finalization claim is made for that failed run. Review also
corrected the legacy namespace bypass and rejected a wrong target before any
destructive work.

This is shared-checkout qualification, not isolated-source or live product
acceptance. Continue native consumer/producer integration, retained accounting,
cloud retention and integrated acceptance. Read-only integration review confirms
atomic freeze/queue/job ownership, version-specific final bindings and separate
pending/retained accounting; no new schema or live composition is claimed here.
Activation remains disabled, PR116 frozen, the deployment hold active, AWS
unapproved and numeric limits unchanged. No push, merge or hosted action
occurred.

## October 16 — shared metadata and local freeze locally validated

L6 uses the same inbox coordinator and fenced store for bounded supporting
metadata and exact local freeze. Positive metadata growth reserves additional
free-space headroom; shrinking adds no reservation. Freeze verifies the entire
saved envelope, ordered originals, both derivative roles and every exact file
identity. Prepared-held packages reject draft mutations. Lost-ack/restart
recovery requires the retained exact request; no server admission or provider
invocation is added.

Independent and IC-1 review cleared candidate03. Eight focused suites passed 109
cases; the complete native target passed 6,066 cases, zero failures or skips.
Source hashes stayed unchanged through both runs. XcodeGen, source membership,
Markdown and scoped diff checks passed. Evidence:
`.artifacts/shared-media-freeze-20261016/`; full result
`.artifacts/local-ios/16c5efaf0b4c484c9393459fa7c298c5.xcresult`. This is local
shared-checkout qualification, not isolated-source or live product acceptance.

Continue durable shared-owner library cleanup, then real producer composition,
cloud retention and integrated acceptance under existing local authorization.
The cleanup contract preserves a closed terminal inventory/root binding and
requires exact physical release before ordinary library deletion. Its agreement
is `.artifacts/shared-media-purge-20261016/agreement.md`; independent/IC-1
concurrence is recorded there. No production composition is enabled.

The approved future cloud-backed LRU direction has no age-only expiry; final
original/preview cache budgets remain undecided. Current numeric limits are
unchanged. Activation remains disabled, PR116 frozen, Supabase hold active and
AWS unapproved. No push, hosted action or deployment occurred.

## October 16 — paired derivative runtime locally validated

L5 now owns paired AI-input/display files through the existing isolated inbox
coordinator, repository, account lease and destination actor. Originals remain
separately owned. Replacement retires the old pair before reserving the new
pair; publication requires both verified completions. Recovery reads saved
complete files only, and cleanup retains charges until both exact file
identities are absent and synchronized. Account validity is rechecked after
normal and lost-ack save returns before further file work or acknowledgement.

Independent and IC-1 review cleared candidate04. Its four focused suites passed
all 44 cases with zero failures/skips. Full01 retained 6,055 passing cases, two
file-size guard failures and no skips; the reviewed lookup extraction fixed both
failures, and the four-suite rerun passed. Unchanged full-run passes are reused;
this is not a claim of a new all-green full-target run. Earlier failed compile,
account-boundary and formatting evidence remains retained. XcodeGen, source
membership, Markdown and scoped diff checks passed. Evidence lives in
`.artifacts/shared-media-derivatives-20261016/`; final focused result is
`.artifacts/local-ios/1fdbde7fd30a480291de5eea21d8788f.xcresult`.

This is scoped shared-checkout qualification, not isolated-source or live
product acceptance. Continue the reviewed L6 metadata/local-freeze agreement
without a new proceed prompt. Live composition, cloud retention and integrated
acceptance remain open, followed by version actions and redesign. Numeric limits
are unchanged; activation disabled, PR116 frozen, Supabase hold active and AWS
unapproved. No hosted action, push or deployment occurred.

## October 16 — derivative schema prerequisite locally validated

L5 uses the existing isolated inbox coordinator for paired AI-input/display
ownership. V61 was frozen and compiled before adding V62's scalar pair/work
entities. Migration adds empty tables without adopting files or replaying work;
all retained inbox/handoff fields keep their meaning. Startup plans, purge
barriers and schema inventories include both entities. Until the paired runtime
is implemented and qualified, derivative rows block fresh qualification. This is
a schema prerequisite, not derivative or whole-product acceptance.

Independent and IC-1 reviews cleared schema candidate03. Its two affected suites
passed all 82 tests, including persistent V61→V62 ownership preservation; the
other six focused suites passed in focused02 and remain unchanged. The first
compile failure and the four fixture failures in focused02 are retained with
their reviewed corrections. XcodeGen/source membership, migration guard and its
mutation regressions, startup selector, remaining iOS CI-tooling commands,
project resources and Markdown checks passed.

Evidence: `.artifacts/shared-media-derivatives-20261016/`; successful rerun
`.artifacts/local-ios/257a242f02dd4d768aa20e10fe7027f2.xcresult`. This is scoped
shared-checkout validation, not a new full-target or isolated-source pass. An
unrelated Explore edit was observed and preserved; none of the unrelated work is
included in this scope. Continue paired runtime implementation automatically.
Numeric limits stay unchanged; activation is disabled, PR116 frozen, Supabase
hold active and AWS unapproved.

## October 16 — joint inbox/P1 handoff locally validated

The inactive joint handoff now uses one coordinator and fenced repository for
source holds, exact destination copies, original-account recovery and cleanup.
Abandonment preserves the source and account-owned draft phase/revision; it can
release liabilities under low disk while unchanged S+H+A caps remain enforced.
Saved irreversible intents and exact inode/directory proofs govern source and
detached-destination release. Surviving originals and destination references
remain owned. Empty-directory cleanup preserves all live and pending tokens.

Candidate04 passed 94 focused tests across six suites and the complete native
target: 6,038 XCResult cases, zero failures or skips (4,580 Swift Testing tests
across 669 suites). Independent and IC-1 pre-execution review concurred. The
initial compile failure from an extracted helper's missing actor annotation is
retained; the corrected helper restores its original main-actor isolation.
Project generation/membership, migration guardrails, Markdown and diff checks
passed. Evidence: `.artifacts/shared-media-handoff-20261016/`; full result
`.artifacts/local-ios/3c0cc00700dd4a4abf6c64e3cc23e1ae.xcresult`.

This validates the isolated handoff in the shared checkout, with 102 unrelated
paths and their generated-project delta preserved. It does not close isolated-
source, live capture, device, hosted or whole-product acceptance. Continue the
shared derivative lifecycle under existing local authorization, retaining the
approved retire-old-first/incomplete-needs-attention behavior. Activation stays
disabled, PR116 frozen, Supabase hold active, AWS unapproved and limits
unchanged. No push, merge, deployment or hosted action occurred.

## October 16 — typed source inbox locally validated

SMA-1 L4 now has an inactive durable source-inbox foundation on V61. Exact
selected original bytes, prepared identities and partial inode ownership survive
reopen without repeating the source callback. Closed-writer occupancy separates
occupied bytes from unwritten reservations without reducing the total charge.
Explicit discard persists exact irreversible intent before namespace-owned
unlink, synchronization, absence proof and joint row reclamation. Legacy inbox
owners reject the bound namespace before mutation. No live routing or file
adoption exists. Handoff records remain rejected until the joint destination
extension is implemented; L4 and whole-product acceptance remain open.

V60 was frozen and compiled before V61 changes. Schema validation passed 116
cases, including disk migration and startup recovery. Source-focused validation
passed 94 tests, then 31 tests after the occupancy correction. The full shared
checkout run retained 6,021 passing and four failing cases, zero skipped. Three
failures were factory-size guards (two oversized-owner inventories and one
direct line-count assertion); one was the purge schema inventory. The reviewed
formatting-only factory correction and two additional purge blocker fixtures
passed all 50 affected architecture, purge and startup checks. Migration and
startup guardrails passed. Unchanged runtime evidence is carried forward with
independent and IC-1 concurrence; no exact-final-candidate full-green or
isolated-source claim is made.

Evidence: `.artifacts/shared-media-inbox-20261016/`, including
source-candidate05, source-full01-summary and source-correction-summary.
Continue the adopted joint inbox/P1 handoff, recovery and cleanup agreement
automatically. Numeric limits, activation disabled, PR116 freeze, deployment
hold and AWS unapproved remain unchanged. No push, merge, deployment, hosted
test or device action occurred.

## October 16 — shared-photo lifecycle locally validated

SMA-1 L3 extends the inactive isolated photo adapter with same-account sharing,
exact reference retirement, restart-safe physical release and bounded
row/directory reclamation. Surviving references preserve the original bytes and
their charge. Retained share requests cannot resurrect reclaimed references.
Saved retirement binds exact file and directory identities; absence
reconciliation proves current absence, never acquisition or AI closure. Pending
acquisition remains charged. Numeric limits and V60 fields are unchanged.

Independent and IC-1 review concurred on exact candidate03 manifest
`ef3abced1ba2cbfd5dc0906e31159a09b789bbe7521808e7a4bf21b70751f6a8`. The focused
gate passed 66 tests across four suites. The complete native target passed 6,009
XCResult cases (4,551 Swift Testing tests across 667 suites), with zero failures
or skips. Project generation/membership, migration guardrails, Markdown and diff
checks passed. Review-held candidates01/02 remain retained; candidate03 only
corrects an EOF blank line after candidate02 source concurrence. Final
documentation and scoped staging receive carry-forward review before the local
commit.

Evidence: `.artifacts/shared-media-lifecycle-20261016/`, with full result
`.artifacts/local-ios/c567429f8f9d48dd98e6c8a20b4b7888.xcresult`. Validation ran
in the shared checkout with 102 unrelated paths preserved, including a
separately retained generated-project delta. This closes the isolated reference
and release checkpoint, not isolated-source, device, hosted or whole-product
acceptance. Inbox/source handoff, derivatives and shared live composition remain
open. Canonical behavior is in
`apps/ios/Merian/Core/Data/SharedMediaStorage/README.md`. Activation stays
disabled, PR116 frozen, Supabase hold active and AWS unapproved. No external
action occurred.

## October 16 — isolated P1/shared-storage adapter locally validated

The local adapter adds `SharedMediaPhotoAcquisitionOwner` for exact
original-byte acquisition in a dedicated persistent fixture. It uses one joint
P1/shared save before the provider and one joint completion save. Exact readback
resolves lost acknowledgements without another provider invocation. A pending or
interrupted write retains its maximum reservation and fixed destinations; only
jointly committed handles can be recovered. Missing or changed originals block
use without replacement or regeneration.

Standalone P1 repositories hold a shared lifetime lock on the zero-byte
`.merian-media-fence` control file in the SQLite parent and reject shared ledger
rows. Every shared-storage mode takes that fence exclusively before the existing
parent-directory, authority and P1 locks. The fence is never removed or
upgraded; its held/named identity, zero length and single link are revalidated.
This keeps co-located standalone purge compatible without opening an
allocator-admission gap. It excludes participating owners, not arbitrary
external filesystem mutation; replacement invalidates the owner without repair.
A persistent P1-root marker also excludes standalone access through another
database after the adapter closes. First binding accepts only empty P1 rows and
namespace. Existing unbound P1 fixtures keep their behavior.

One physical destination contributes once to filesystem reservation and to the
durable budget. Its paired P1 lease also contributes to acquisition/temporary
budgets; each package's bounded empty envelope contributes once to logical
durable totals. Limits and V60 fields are unchanged. No source/inbox handoff,
derivatives, freeze, sharing, deletion, physical release, ordinary capture,
network or AI admission is enabled. Generic L1 mutations reject adapter mode.

Exact candidate05 passed all four focused suites (52 tests) and the complete
`merianTests` target (5,995 XCResult cases; 4,537 Swift Testing tests across 667
suites), with zero failures or skips. Independent and IC-1 source review
preceded execution. Project generation/membership, migration guardrails and
Markdown checks passed. The retained candidate02 compilation failure and
candidate03 legacy-purge failure led to the reviewed corrections; they are not
erased or counted as passes. Candidate04 was held at review for an EEXIST
durability race; candidate05 closes it with unconditional file/parent
synchronization and identity revalidation before admission.

Evidence is under `.artifacts/shared-media-p1-adapter-20261016/`. The native
gate ran in the shared checkout with 102 unrelated paths preserved; this is
local checkpoint validation, not isolated-source, device, hosted or
whole-product acceptance. Next is a separately reviewed source-owner/inbox
handoff and cleanup increment; no live producer, derivative or release authority
is inferred. PR116 remains frozen, activation disabled, Supabase hold active and
AWS unapproved. The L1 validation record below remains historical evidence for
that earlier scope.

## October 16 — inactive SMA-1 L1 foundation locally validated

The local implementation freezes V59 and adds four scalar V60 storage entities,
explicit fixture ownership, durable reservations/references/leases, and a
fail-closed identity/purge guard. The SQLite parent and authority directories
provide lifetime exclusion; SQLite file locking remains with Core Data. There is
no live composition, file writer, physical-release acknowledgement or AI
admission. Legacy observations remain advisory, with no completeness or
promotion claim.

The V59 disk migration and startup recovery passed. Candidate09 passed all 16
focused storage tests; its full shared-checkout execution ran 5,972 tests and
retained four failures (three size inventories and an outdated purge inventory).
Candidate10 changed production code only by formatting and corrected purge
coverage; all 23 targeted checks passed, including each new row blocking purge
before callbacks in saved and unsaved states. Independent and IC-1 review concur
with reuse of unchanged passing results. This is combined local evidence, not a
green full rerun on candidate10 or isolated-source qualification. Receipts and
failed runs remain in `.artifacts/shared-media-foundation-20261016/`.

The next dependency is an isolated P1/shared-storage handoff with explicit
ownership links, joint durable transitions, and enforced producer exclusion.
Whole-product allocation, source import, physical release and mixed-producer
qualification remain open; this is not overall acceptance closure. Limits stay
unchanged. PR116 remains frozen at `135555d66`, activation and ordinary P1
access disabled, Supabase hold active and AWS unapproved. Local continuation
needs no routine proceed prompt; push, merge, deployment and hosted tests remain
barred.

## October 16 — shared native allocation agreement reviewed

[SMA-1](shared-media-allocation-ownership-2026-10-16.md) recommends additive V60
ownership in the existing store, non-destructive legacy inventory, explicit
accountless inbox ownership, and reference-directed cleanup. The 384 MiB cap
remains pending CPM packages only; retained history occupies real disk but
receives no new quota or eviction policy. Legacy observations confer no write,
cleanup or fresh-admission authority.

This is a proposed agreement, not implementation or mixed-producer
qualification. G1–G4 and A2/A3/A5/A14/A16/A17 remain open. The next bounded
dependency is the exact inactive foundation file/lock/migration packet after
independent and IC-1 review, followed by producer integration and required
acceptance. Existing media-required submission and exact admitted recovery
remain unchanged. Unknown AI execution permits neither another invocation nor a
refund.

PR116 stays frozen at `135555d66`; activation and ordinary P1 access disabled,
Supabase hold active, AWS unapproved, limits unchanged. No push, merge,
deployment, hosted test, device operation or capture visual refactor is
included.

## October 16 — C1 observer correction validated locally; PR116 still frozen

The retained exact-source diagnostic reproduced CI's `ZX452` with only the
unknown-cancellation count predicate failing. The owner-delete fence now erases
private cancellation records before the old test observer ran. Funding and the
protected accounting projection were unchanged. The correction changes only the
account-batch test: preserve its full original assertion before the real fence,
then independently verify private erasure and unchanged accounting after it.
Enabled trigger order/function and exactly-once observations are checked. No
production migration, runtime behavior, API or activation change is needed.

Exact independent and IC-1 execution review preceded the corrected candidate.
The complete affected account-batch and admitted-expiry suites passed 9 and 12
checks on separate fresh owned local databases. Expiry waited 292.165 seconds
for the original deadline, without timeline edits. All three diagnostic/test
databases were reconciled and disposed; failed evidence remains retained.
Recursive formatting/lint and Python syntax passed. The complete tooling gate's
TypeScript, evaluation and DTO checks passed; a sandboxed synthetic terminal
fixture stopped its shell phase. That failure is retained, and the failed plus
remaining ten mock-only shell tests passed with terminal access. Passing prefix
checks were reused rather than repeated. No hosted credential or provider call
was made.

Evidence and exact review/commit receipts:
`.artifacts/c1-account-batch-diagnostic-20261016/` and
`.artifacts/c1-account-batch-correction-20261016/`. This is scoped
shared-checkout local evidence, not a new full candidate/remote CI verdict.
PR116 remains frozen at `135555d66`, with its failed CI result unchanged until
separately authorized publication. All unrelated edits are preserved. Activation
stays disabled, ordinary P1 access nil, Supabase hold active, AWS unapproved and
limits unchanged. No push, merge, deployment, hosted test or schedule change
occurred.

The next feature dependency remains durable shared allocation/inventory and
cleanup ownership, then original-media integration and remaining acceptance,
followed by approved version deletion/export and redesign. Existing
media-required submission, immutable descriptions and exact admitted recovery
rules remain; unknown execution grants neither another AI invocation nor a
refund. The capture visual refactor and broader engine work retain their
separate ownership.

## October 16 — separate local continuation; PR116 remains frozen

The user authorized local feature continuation on
`codex/history-original-media-followup`, based on
`135555d66434dbd6cdf812849745295f6db4f760`, with reviewed local commits. PR116
remains frozen at that exact head. This supersedes earlier instructions to wait
for integration before local follow-up construction; no push, merge, deployment
or hosted test is authorized. Activation stays disabled, ordinary P1 access nil,
Supabase integration hold active, AWS unapproved and all limits unchanged.

The first reviewed scope confines legacy FileIO operations so paths cannot
bypass the private PhotoPreparation, ReanalysisQueue or inbox owner. It also
removes absolute-source basename substitution. This is an ownership
prerequisite, not common allocation or product-wide lifetime qualification. The
durable shared allocator/inventory agreement, remaining media and integrated
acceptance, then version deletion/export and redesign remain in their approved
order. No capture visual refactor or broader engine ownership is absorbed.

The ownership correction passed 47 focused tests and the complete native unit
run: 5,955 expanded cases, zero failures or skips (4,497 test declarations in
665 suites). The required critical-suite result validator also passed. These are
shared-checkout simulator results, not isolated-source or device qualification.
The earlier full run, with ten failing replay declarations, remains retained:
the replay fixture had injected its Documents root but still used global
cleanup. Explicit FileIO owner injection corrected that mismatch without
broadening cleanup authority; success, cancellation and error paths now use the
same owner.

Independent and IC-1 exact-source concurrence preceded the corrected execution.
Scope and failed/passing results are retained in
`.artifacts/history-media-confinement-20261016/`. A local commit requires
separate final result review; review and commit receipts must identify the exact
candidate in that directory. All 102 unrelated paths are preserved. Auto-prompts
remain paused.

PR116's iOS Build/Test and Startup Safety checks passed. Supabase Candidate
Validation run `38864594630` failed C1 `account-batch` at
`actual_two_item_account_tombstone_rollback`, SQLSTATE `ZX452`. Its compound
pre-user-delete accounting assertion did not reveal the failed predicate at this
checkpoint. The disabled-gate restoration passed. That unresolved assessment and
proposed diagnostic are superseded by the later October 16 C1 observer
correction recorded at the top of the alpha-readiness RFC. The original CI
failure remains historical evidence; remote CI has not been rerun. See
`pr116-ci-blocker.json` in the evidence directory. PR116 remains frozen and is
not merge-ready.

## October 16 — PR116 feature scope frozen; merge-readiness proposal

The human requested a feature freeze and exact merge-readiness proposal with
independent/IC-1 review. The frozen implementation is
`ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`; its local evidence checkpoint is
`fdddf66198f0fbfd568534c62fa4b3a7e18e3254`. The 102 unrelated working-tree paths
are excluded. No further feature additions belong in PR116. This current
direction supersedes the immediate common-allocation next-step recommendation
below and the historical October 13 integration cut; existing evidence and
remaining acceptance requirements are preserved.

Proposal:
`docs/rfcs/identification-history-pr116-merge-readiness-2026-10-16.md`. ISQ-1
closes only isolated local NCO/BI qualification. Cumulative PR safety, exact
final CI and live deployment containment remain open. The local active history
hold blocks the entire Supabase production job, but does not protect old jobs or
external Vercel hooks. Remote PR116 remains draft at `878932268`; its checks do
not qualify the 101 newer local commits. No push, merge, hosted qualification,
deployment, device installation or activation is authorized.

The proposed next checkpoint is a two-hour read-only readiness audit, at most
128 MiB evidence and the 20 GiB disk floor; execution awaits approval. Exact
proposal review receipts are retained in
`.artifacts/pr116-merge-readiness-20261016/`. Proposal concurrence is not
whole-PR acceptance or release approval. Common-allocation/original-photo
integration continues in the next feature PR after the integration boundary;
later version deletion/export and redesign retain their sequence and ownership.
No acceptance gate is waived. Activation disabled, ordinary P1 access nil, AWS
unapproved, limits unchanged; automatic scheduling remains stopped.

## October 15 local / October 16 UTC — ISQ-1 isolated execution passed

The approved XcodeGen 2.45.4 selection correction resumed ISQ-1 within its
original 03:07:08–07:07:08 UTC window and unchanged bounds. The clean managed
worktree at `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f` passed generation with
identical project bytes, project/migration/CI-tooling/source-membership checks,
managed Debug build, 561 acceptance tests, all 27 UI cases, all ten report-only
performance workloads, all 5,923 unit tests, the actual critical-result
validator and unsigned generic Release compilation. No failures or skips were
reported. The unit XCResult's 9,363 per-device executions are a separate count;
BI-1's earlier 5,945 total remains shared-checkout evidence.

Source and pinned hashes remain unchanged; all 102 unrelated primary file
identities are preserved. Storage accounting normalizes only the reviewed
simulator-container relocation, charges new/grown files including 23 new fixture
roots, and preserves raw alarms. Working allocation/evidence/free-space checks
remain within the original bounds. No performance baseline was adopted; high
variance and missing hitch samples remain explicit limitations.

Result: `docs/rfcs/client-prepared-media-isq1-isolated-result-2026-10-16.md`.
Evidence: `.artifacts/local-ios/isq1-20261015/result-resumed.json`; final exact
independent/IC-1 disposition belongs in `result-review-02.json` in that
directory. Closure is limited to the isolated local NCO/BI portion of A19 after
that concurrence. P1 common-allocation/photo and device, audio/video quality,
server admission/shared references, integrated history, external/CI and later
version deletion/export/redesign gates remain open. The next recommendation is a
bounded common-allocation/original-photo ownership and integration proposal.

Activation disabled, ordinary P1 access nil, AWS unapproved, existing limits
unchanged. No push, merge, deployment, hosted test or device installation. Stop
at this local checkpoint; automatic scheduling remains stopped. Earlier stopped
attempts and proposal states below are historical and retain their evidence.

## October 15 local / October 16 UTC — ISQ-1 stopped at tool prerequisite

The human approved ISQ-1 for 03:07:08–07:07:08 UTC. Exact independent and IC-1
execution concurrence preceded the first qualification command. The clean
managed worktree at `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f` selected XcodeGen
2.45.2; the project requires 2.45.4. The primary checkout had selected the
installed 2.45.4 executable, so its preliminary tool inventory did not establish
the clean worktree's command lookup. Generation failed before changing files.

Stopped without retry or repair. No package downloads, builds, runtime tests or
later qualification gates ran. Worktree remains clean; all 106 primary file
identities (102 unrelated plus four proposal/status paths) were preserved before
this owned reporting update. Source qualification and all remaining product
gates stay open. Result and proposed environment-only correction:
`docs/rfcs/client-prepared-media-isq1-qualification-result-2026-10-15.md`.
Evidence: `.artifacts/local-ios/isq1-20261015/`. Independent and IC-1 concur
with this stopped disposition; exact receipts are in
`.artifacts/local-ios/isq1-20261015/final-review.json`.

Activation disabled, ordinary P1 access nil, AWS unapproved, existing limits
unchanged. No push, merge, deployment, hosted action or device installation;
automatic continuation remains stopped. Earlier proposal/active statements below
are historical; human approval does not erase this failed preflight.

## October 15 local / October 16 UTC — ISQ-1 proposed; execution awaits approval

BI-1 is committed locally as `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`. Its
passing validation is shared-checkout evidence; 102 unrelated dirty paths remain
preserved. Earlier pending-commit or active-window statements below are
historical. Automatic continuation stopped at BI-1 completion.

The next proposal is
`docs/rfcs/client-prepared-media-isolated-qualification-proposal-2026-10-15.md`:
one four-hour local window, one clean managed worktree at the exact commit,
explicit locked package downloads, managed native qualification, 16 GiB new
working allocation and 2 GiB retained evidence, with the 20 GiB disk floor.
Independent and IC-1 concur on proposal SHA-256
`8043861c9d55968175a9123ca944e891f622b63e88779f029b70a54458957862`; receipts are
in `.artifacts/local-ios/isq1-proposal-20261015/review.json`. Human execution
approval remains pending. No execution or implementation is authorized by this
entry. The proposal separates isolated-source evidence from
common-allocation/device, audio/video, server admission, integrated history,
external/CI and later deletion/export/redesign acceptance; those remain open.

Fresh initial/reanalysis requires photo/audio/video, with optional immutable
supporting text; retained originals suffice, missing media blocks, historical
records and exact admitted recovery remain preserved. No new Supabase project is
required: the later human shared-alpha-target decision supersedes historical
nonproduction-only wording, without granting any current hosted operation.
Activation disabled, ordinary P1 access nil, AWS unapproved, existing product
and runtime limits unchanged. No push, merge, deployment, device or hosted work;
automation remains stopped. Prior evidence and failures remain unchanged below.

## October 15 local / October 16 UTC — BI-1 validation passed; inactive integration checkpoint

BI-1 completed its planned local validation within the approved
01:56:04–03:56:04 UTC window and 1 GiB additional evidence allowance. Candidate
02 passed managed Debug compilation, 96 focused tests, all 5,945 unit tests, all
six critical UI smokes, unsigned generic Release compilation, full CI tooling,
project validation and the actual critical-result validator. Raw XCResult
per-device counts are retained separately. These are shared-checkout results,
not isolated selected-source qualification or P1/alpha acceptance.

Final staging exposed two whitespace diagnostics in newly added files. The
frozen V58 snapshot retains its exact inherited bytes; the test file loses only
one terminal blank line (candidate 03). The staged audit permits only the known
frozen-line diagnostic. Final review must concur with evidence reuse for this
formatting-only correction; candidate-02 runtime results remain accurately
labeled in the result and raw artifacts.

Independent and IC-1 source-selection review concurred on the 59-file NCO/BI
source/configuration/project selection. Local commit requires final exact
combined-patch review; receipts and commit identity are retained in
`.artifacts/local-ios/bi1-20261015/`. Unrelated working-tree edits remain
intact. BI-1 automatic continuation ends at this checkpoint and does not advance
the broader roadmap. Earlier active/paused/proposal status below is historical.

Activation disabled, ordinary P1 access nil, AWS unapproved, existing limits
unchanged. No hosted action, push, merge, deployment, device installation or
distribution occurred. Installed/mixed-allocator, audio/video, server admission,
integrated history and later deletion/export/redesign acceptance remain open.
Result: `docs/rfcs/client-prepared-media-bi1-integration-result-2026-10-15.md`.

## October 15 local / October 16 UTC — BI-1 approved; bounded validation active

The human approved automatic continuation for BI-1 only, from 01:56:04 through
03:56:04 UTC, with at most 1 GiB additional retained evidence. Candidate 02 has
exact independent and IC-1 concurrence, a passing managed simulator build, all
96 focused tests passed and a passing full CI-tooling gate. Complete unit
validation and selected-tree/final evidence review are in progress. These are
shared-checkout results; no clean-source acceptance claim. No runtime source
change beyond the reviewed Auth consolidation was added by BI-1.

The BI-1 follow-up is active only within this fixed window and stops at
completion or a genuine blocker. Earlier paused/proposal-only status is
historical. Activation disabled, ordinary P1 access nil, AWS unapproved and
existing limits unchanged. No push, merge, deployment, hosted or device actions
are authorized. Evidence: `.artifacts/local-ios/bi1-20261015/`. Proposal
boundary:
`docs/rfcs/client-prepared-media-bounded-integration-proposal-2026-10-15.md`.

## October 15 local / October 16 UTC — BI-1 integration proposal; execution gated

The human requested a bounded proposal for the remaining Auth guard, stale
capture CI selector and baseline dependency. BI-1 proposes a fresh two-hour
local window with at most 1 GiB additional evidence: consolidate existing Auth
helpers without changing caps or fences; prove pending-video interruption and
late-result cleanup before replacing the critical selector; and explicitly
integrate the account-bound capture baseline hunks needed by NCO. The dependency
includes admission fields, account-change hooks and cleanup, not just
CaptureDraftSession.

Independent and IC-1 re-review concur on proposal SHA
`4125ea97f243d0b6d6d03ef19500bfc2cac60308f7b226f40c6ef845adc2e15a`. The
corrected critical test targets pending startup cancellation and preserves
started-recording stop/completion. Human implementation approval remains
pending. Review receipt: `.artifacts/local-ios/bi1-20261015/review.json`. No new
runtime change, build or test is authorized by this proposal. NCO's existing
shared-checkout evidence and open full/UI/Release/installed/integrated gates
remain unchanged. Activation disabled, production P1 access nil, AWS unapproved,
all existing limits unchanged, auto-prompts paused. Unrelated visual/backend
work remains outside the handoff. Canonical proposal:
`docs/rfcs/client-prepared-media-bounded-integration-proposal-2026-10-15.md`.
Earlier entries remain historical.

## October 16, 2026 — NCO-1 local checkpoint; shared acceptance blocked

The approved local implementation and four-script validation extension are
implemented. Candidate 07 passed 103 focused native tests; its complete unit
target had 5,939 passed and four failed. Candidate 08 fixes the V59 factory's
three architecture failures and passes its managed build plus all 18 affected
architecture tests. The unchanged Auth budget failure and pre-existing capture
critical-selector mismatch remain open; the full gate is not green.

Evidence is for the shared checkout. P1 depends on uncommitted baseline
CaptureDraftSession account APIs, so no standalone NCO commit was made or
unrelated changes absorbed. The bounded patch and exact source snapshot are
retained. Further baseline/CI ownership reconciliation is required; UI/Release
runs are held, and P1/integrated acceptance remains open. Activation disabled,
production access nil, AWS unapproved, limits unchanged, auto-prompts paused. No
hosted action, push, merge, deployment or device installation occurred. Current
result: `docs/rfcs/client-prepared-media-nco1-local-result-2026-10-15.md`.
Earlier entries remain historical and do not supersede this checkpoint.

## October 15, 2026 — NCO-1 implementation authorized; validation in progress

The human approved a four-hour local implementation and validation window from
23:17:59 UTC through October 16 03:17:59 UTC, including up to 2 GiB of new
native evidence. The outgoing V58 model freeze passed independent/IC-1 review
and managed build-for-testing. The V59 ledger, inactive capture ownership seams
and cleanup integration are now under exact-candidate review; they have not
passed runtime acceptance. Earlier proposal-only status below is historical.

No P1 completion or integrated qualification is claimed. Production access stays
nil, activation disabled, AWS unapproved, package/storage limits unchanged and
auto-prompts paused. No hosted action, push, merge, deployment or device
installation is authorized. Current local evidence:
`.artifacts/local-ios/nco1-20261015/`. The native ownership agreement remains
the scope authority; capture-tools/redesign work remains separate.

## October 15, 2026 — NCO-1 native agreement; P1 execution awaits approval

The authorized two-hour local agreement scope after `600b5ce28` prepares P1-L1:
freeze V58, add four standalone V59 ownership entities, retain exact original
bytes before draft release, and bind capture/cleanup to account-work leases and
fail-closed purge. The canonical NCO-1 packet records the concrete file boundary
and acceptance plan. Exact independent/IC-1 review is required for closure; its
evidence is retained with this candidate. The next request is one four-hour
local implementation/validation window, including up to 2 GiB new native test
evidence under the existing managed-build procedure. It is not authorized yet.
Qualification excludes competing non-P1 allocators; installed mixed-allocator
and integrated product gates remain open. No tests, builds, runtime edits or
hosted actions occurred. No transport rerun is justified. Activation disabled,
ordinary access nil, AWS unapproved, existing limits unchanged, auto-prompts
paused. Canonical packet:
`docs/rfcs/client-prepared-media-native-ownership-agreement-2026-10-15.md`.
Earlier entries remain historical and exactly recoverable.

## October 15, 2026 — CP-1 reviewed source boundary; native ownership agreement required

CP-1 preparation was authorized after `cae2329a1`. Its twelve-file source review
finds that original-photo retention needs durable draft/package ownership,
separate from ordinary queue funding and dispatch. Proposed P1-L1 typed native
ledger and the exact schema/capture/cleanup handoff remain unadopted;
implementation is not ready. Next proposed scope is at most two hours to close
those two named agreements and return the exact four-hour P1 packet. No tests,
builds, runtime changes or hosted actions occurred. No new transport test is
justified. Activation disabled, AWS unapproved, limits unchanged, auto-prompts
paused. Current result:
`docs/rfcs/client-prepared-media-original-photo-cp1-result-2026-10-15.md`.
Earlier entries remain historical and exactly recoverable.

> Current October 15 GAC-1 local result: the loader fix and validation passed;
> one offline package, denial control and 20-read serial campaign completed. All
> 20 media reads verified and closed on one worker; teardown/removal passed.
> GAC-1 passed with case-4 warning retained. Peak partial proxy: 38.796025 MiB;
> cross-cohort Q increase: 7.8125 MiB, close to the unchanged 8 MiB gate. This
> closes only the finite local checkpoint, not hosted, whole-worker/native/CPU
> or product acceptance. Exact result and limits:
> docs/rfcs/client-prepared-media-gac1-local-result-2026-10-15.md. Activation
> disabled, AWS/160 MiB unapproved, all other limits unchanged, auto-prompts
> paused. The single package/control/campaign allowances are consumed. Earlier
> entries below are historical and remain exactly recoverable.

---

> Current October 15 GAC-1 continuation result: the corrected explicit-file type
> gate passed, reusing 54 unchanged passing tests. Staged/main lint then found
> unsafe throws in both local bundle loaders; the first-failure stop closed this
> window before packaging, control or campaign. The concrete cleanup-error
> preservation proposal requires a new implementation decision:
> docs/rfcs/client-prepared-media-gac1-loader-lint-result-2026-10-15.md.
> Activation disabled, AWS/160 MiB unapproved, all other limits unchanged,
> auto-prompts paused. Product/native/integrated gates remain open. Entries
> below are historical; their exact source bytes remain recoverable.

---

> Current October 15 GAC-1 precheck result: the approved local scope stopped
> when pinned Deno 2.9.4 rejected the recursive type-check command before
> checking source. Formatting/lint and 54 tests passed; recursive typing and
> staged lint remain unqualified. No packaging, control or campaign ran.
> Independent and IC-1 review recommend a command-only correction; another
> execution requires a new decision. Canonical result and continuation proposal:
> docs/rfcs/client-prepared-media-gac1-precheck-result-2026-10-15.md. Activation
> disabled, AWS/160 MiB unapproved, all other limits unchanged, auto-prompts
> paused. Product/native/integrated gates remain open. Entries below are
> historical; their exact source bytes remain recoverable.

---

> Current October 15 GAC-1 adoption: the user approved the revised local
> acceptance contract and bounded implementation preparation. Exact independent
> and IC-1 source review is required; no tests, packaging, control or campaign
> execution is authorized yet. Canonical adoption and execution proposal:
> docs/rfcs/client-prepared-media-gac1-implementation-2026-10-15.md. The old
> four-point stop becomes a reported warning only for the explicit GAC-1
> candidate; the 8 MiB comparison tolerance and other limits stay fixed. Prior
> failures retain their original classifications. Activation disabled, AWS/160
> MiB unapproved, auto-prompts paused. Product/native/integrated gates and
> follow-up sequencing remain open. All entries below are historical.

---

> Current October 15 result: the denial control passed; the four-read prefix
> stopped at the unchanged 8 MiB growth gate (10.278900 MiB increase). All four
> media bodies closed; teardown and removal passed. Original-call bins localized
> rises/falls within verified reading/hashing; stopped case4 remains
> unclassified. No leak/GC/idle conclusion or qualification pass. Both
> allowances consumed, no retry. Canonical result:
> docs/rfcs/client-prepared-media-memory-bins-result-2026-10-15.md. Activation
> disabled, AWS/160 MiB unapproved, all limits unchanged, auto-prompts paused.
> Product/native/integrated gates and follow-up order remain open. Earlier
> entries below are historical; no hosted or credential action occurred.

---

> Current October 15 approved scope: local fixed-bin diagnostics in the fresh
> 16:37:22–18:37:22 UTC window. No new memory call or timer; unchanged gates and
> limits. One denial control and conditional four-read prefix each require exact
> independent/IC-1 concurrence; current candidate is not yet execution-approved.
> Scope and evidence: .artifacts/client-prepared-media/memory-bins/scope.md.
> Activation disabled, AWS/160 MiB unapproved, auto-prompts paused. Prior
> results remain historical; product/native/integrated acceptance and follow-up
> order remain open. No hosted, credential, deployment, push, merge or device
> action.

# Initial completion and history interface

> Current October 15 memory review: retained data shows phase-varying external
> memory and a valid 8 MiB growth stop, without establishing a leak or
> reclamation mechanism. A bounded proposal would expose existing samples in
> fixed bins and run only the original four-read prefix, after human approval
> and exact independent/IC-1 concurrence. No additional memory calls, idle
> timers or gate changes are proposed. Packaging must fit existing storage caps;
> feasibility remains conditional. Canonical proposal:
> docs/rfcs/client-prepared-media-memory-growth-review-2026-10-15.md. This turn
> performs no construction or runtime test. Prior failures and exact evidence
> remain preserved; activation disabled, AWS/160 MiB unapproved, limits
> unchanged, auto-prompts paused. Product gates and follow-up order remain open.
> Earlier status entries are historical.

> Current October 15 result: the baseline reproduced the retained pool error;
> the proposed control and campaign teardown passed with no runtime errors and
> confirmed removal. The campaign workload FAILED the unchanged 8 MiB growth
> gate after 42.235 seconds: one worker, five requests, four media
> reads/closures, three verified and 13.654 MiB four-point growth. Sustained
> reuse remains unqualified. Both controls and the single campaign are consumed;
> no retry. Canonical result:
> docs/rfcs/client-prepared-media-pool-retirement-result-2026-10-15.md. Executed
> candidate af9802a14a9833e1ef8e2eb9f7c5b6f65a2549cef3351347dff5f607b3e4e147
> received separate exact independent/IC-1 concurrence before controls and
> campaign. Both reviewers concurred with the result and stop disposition; final
> review receipts are retained under
> .artifacts/client-prepared-media/pool-retirement/. Source and prior evidence
> remain preserved with status snapshots. Activation disabled, AWS/160 MiB
> unapproved, all limits unchanged, auto-prompts paused.
> Product/native/integrated gates and approved follow-up order remain open. No
> hosted/credential action or cleanup obligation. Earlier status entries are
> historical.

> User approved bounded pool-retirement construction and local execution in a
> fresh October 15 window,15:48:12–17:48:12UTC. Exact independent/IC-1
> executable concurrence is required before two one-shot controls, and
> separately before the conditional unchanged campaign. Scope:
> .artifacts/client-prepared-media/pool-retirement/scope.md. No new
> clock/watchdog controls; reuse qualified unchanged sources only after review.
> Earlier failures remain preserved. Activation disabled, AWS/160MiB unapproved,
> all limits unchanged, auto-prompts paused. No hosted or credential operation.
> Product gates and follow-up sequencing remain unchanged; earlier status
> entries are historical.

> Current October 15 proposal: read-only pinned-runtime review identifies a
> pool-channel teardown ordering issue. A bounded post-terminal idle retirement
> request plus positive empty-registry observation is proposed as a hypothesis,
> preserving zero grace and every existing limit. See the
> [retirement proposal](client-prepared-media-pool-retirement-proposal-2026-10-15.md).
> Proposal review does not authorize construction or another run; human approval
> and exact independent/IC-1 executable concurrence remain required. Prior
> lifecycle failure stands. Activation disabled, AWS/160 MiB unapproved,
> auto-prompts paused; earlier status notes are historical.

> Current October 15 result: shared-clock qualification and the independent
> stalled-parent watchdog passed. Replacement baseline reproduced the original
> failure; proposed listener retention still produced the pool shutdown-send
> error. Complete receipt ordering and cleanup do not override lifecycle
> failure. The conditional campaign did not run; no retry is authorized. See the
> [exact result](client-prepared-media-clock-qualification-result-2026-10-15.md).
> Activation disabled, AWS/160 MiB unapproved, all limits unchanged,
> auto-prompts paused. Earlier states below are historical; product gates remain
> open.

> User approved the reviewed clock-method amendment in a fresh October 15 local
> window, 14:57:29–16:57:29 UTC. Construction and focused tests are complete;
> exact independent and IC-1 review is pending before execution. One
> delayed-child clock check, one inert watchdog control and two replacement
> case-26 controls are allowed; campaign remains conditional on successful
> controls and separate exact concurrence. Scope:
> .artifacts/client-prepared-media/clock-qualification/scope.md. Prior failed
> baseline and candidate evidence remain historical and preserved. Activation
> disabled, AWS/160 MiB unapproved, all limits unchanged, auto-prompts paused.
> No hosted or credential actions. Product gates and follow-up order remain
> unchanged. Earlier approval requirements below are historical for this new
> scope.

> Current October 15: the approved first shutdown control reproduced both
> runtime errors and exit 1; EOF and external cleanup are confirmed. Python
> 3.9.6/macOS clock origins invalidate cross-process ordering and transferred
> absolute-deadline qualification. Independent and IC-1 review concur with
> stopping; the second control and campaign remain unused. See the
> [clock finding and bounded next-method recommendation](client-prepared-media-shutdown-clock-finding-2026-10-15.md).
> No runtime change or further execution follows without explicit amendment and
> exact review. Activation disabled, AWS/160 MiB unapproved, all limits
> unchanged, auto-prompts paused. Earlier status text is historical; product
> gates remain open.

> Current October 14: the approved request-boundary campaign completed all 20
> media reads on one worker in 682.342 seconds, but failed runtime shutdown
> qualification after a worker-pool shutdown error (exit 1). External container
> removal is confirmed. See the
> [exact result](client-prepared-media-request-boundary-result-2026-10-14.md).
> The single campaign is consumed; no retry or limit change. Activation
> disabled, AWS unapproved, auto-prompts paused. Earlier preparation/proposal
> states below are historical; product acceptance remains open.

> Current October 14: the user approved local preparation, but independent and
> IC-1 review found an unproven parent-to-worker idle-timer cancellation path.
> Two inert controls are complete; no bundle or verifier campaign ran. See the
> [prelaunch finding and proposed method amendment](client-prepared-media-allocation-diagnostics-preflight-2026-10-14.md).
> Launch remains blocked pending explicit scope resolution and exact-candidate
> review. Activation disabled, AWS unapproved, limits unchanged. Earlier
> approval/status text below is historical.

> Current October 14 follow-up: local allocation diagnostics and harness
> shutdown correction are proposed in the
> [bounded approval scope](client-prepared-media-allocation-diagnostics-proposal-2026-10-14.md).
> Draft/review only; human approval is required before construction, controls or
> another run, followed by exact-candidate independent/IC-1 concurrence before
> execution. Previous failed campaign and cleanup evidence remain valid.
> Activation disabled, AWS unapproved, all limits unchanged. Earlier status
> entries below remain historical.

> Current October 14: the approved local campaign ran after exact independent
> and IC-1 concurrence, then stopped at the unchanged 8 MiB growth gate after
> approximately 42 seconds. One worker, five attempts, three verified reads; all
> four opened bodies closed and the container was removed. No retry. See the
> [exact result](client-prepared-media-controlled-worker-result-2026-10-14.md).
> Post-run independent/IC-1 review concurs with the corrected report, including
> its shutdown defect. Sustained reuse and product acceptance remain open.
> Activation disabled, AWS/160 MiB unapproved, all other limits unchanged.
> Earlier status/approval statements below are historical.

> Current October 14 prelaunch finding: the user approved local preparation and
> execution only after exact-candidate review. The pinned runtime's default
> supervisor retires at half the configured lifetime, so the 900-second setting
> conflicts with the 682-second schedule. No campaign launched; allowance
> unused. See the
> [prelaunch finding and unapproved amendment](client-prepared-media-controlled-worker-preflight-2026-10-14.md).
> Existing limits remain unchanged, activation disabled, AWS unapproved. Earlier
> approval/status notes below are historical.

> Current October 14 controlled-reuse proposal: the attended v1.77.0 run
> completed all 26 checks and cleanup, but all 25 reads reported different
> worker aliases. Hosted warm reuse, growth and physical read overlap remain
> unobserved. The user authorized only the
> [local controlled-worker proposal](client-prepared-media-controlled-worker-reuse-proposal-2026-10-14.md)
> and independent/IC-1 review; construction and execution await approval.
> Activation disabled, AWS and 160 MiB unapproved, credentials retained,
> auto-prompts paused. Earlier status entries below are historical. No product
> acceptance, ownership or follow-up sequencing changes.

> Current October 14 v1.77.0 qualification: the reviewed startup correction
> passed the hosted denial and two closed controls, then stopped at the runtime
> version gate. Cleanup completed; both credentials are retained by explicit
> user decision. Old control closure is reconciled; its private object remains
> untouched. Local v1.77.0 compatibility and independent/IC-1 review are covered
> by the
> [current packet](client-prepared-media-runtime-177-hosted-packet-2026-10-14.md).
> No new hosted action is authorized. Activation disabled, AWS and 160 MiB
> unapproved, auto-prompts paused. Earlier current-state entries below are
> historical; product acceptance and follow-up sequencing are unchanged.

> Current October 14 runtime correction: the approved test-auth attempt stopped
> at case 26; route/settings were removed. Both R2 keys remain active per the
> user's corrected statement, and the old private control object remains
> unresolved. Local pinned-runtime reproduction found a decorated-version
> validator defect; correction and safe diagnostics are under independent/IC-1
> review. The
> [new exact packet](client-prepared-media-runtime-diagnostics-hosted-packet-2026-10-14.md)
> requires fresh hosted approval. Earlier preparation-only entries below are
> historical. Activation disabled, AWS unapproved, auto-prompts paused.

> Current October 14 test-auth revision: local construction and independent/IC-1
> review are authorized; the
> [revised hosted packet](client-prepared-media-test-auth-hosted-packet-2026-10-14.md)
> requires new approval before uploads, secret installation or deployment. The
> previous JWT candidate was never deployed/run. A dedicated short-lived test
> key removes the iOS app-session prerequisite only for this experiment;
> production authentication, G1–G4, media-required scope and product acceptance
> remain unchanged. The existing R2 credentials are locally available with no
> values logged. Activation is disabled, AWS unapproved, auto-prompts paused.
> Earlier runtime-packaging status below is historical for its exact candidate.

> October 14 runtime-packaging update: the user authorized four hours of local
> construction and independent/IC-1 review. See the
> [exact hosted-test packet](client-prepared-media-runtime-packaging-and-hosted-packet-2026-10-14.md).
> User-reported private R2 fixture setup is complete; no credentials have been
> read/installed and no hosted test or deployment is authorized. Local packaging
> does not close CPM-1 G1–G4 or IC-1 product acceptance. Package/storage limits,
> media-required scope, historical recovery and later version-actions/redesign
> sequence remain unchanged. AWS is unapproved, activation disabled and
> auto-prompts paused. A single experimental-route exception to the
> whole-backend release hold requires the separate exact hosted approval; PR116
> remains held.

> October 13 subsequent human approval: proceed with the reviewed CPM-1 policy
> targets, bounded local feasibility preparation and PR116 whole-backend source
> hold under the
> [approved local plan](client-prepared-media-approved-local-plan-2026-10-13.md).
> Earlier pending-approval wording below is historical for that decision.
> Runtime schema/audio/reference agreement and candidate qualification remain
> open; hosted/device/push/merge/deployment restrictions remain unchanged. AWS
> is unapproved and activation disabled. The hold is a local source change only.

> October 13 evaluation update: the user authorized drafting and reviewing the
> [CPM-1 client-prepared media amendment](client-prepared-media-amendment-2026-10-13.md)
> before any AWS decision. It proposes a distinct fresh-submission version; it
> does not weaken or reinterpret this document’s existing server-prepared or
> historical contracts. Adoption and implementation remain pending. AWS is
> unapproved, activation disabled, and all external-operation restrictions
> remain. Revision 3 records the user-required G1–G4 acceptance gates:
> original-byte retention, final audio plus signal/quality evidence, concrete
> storage limits, and end-to-end recovery/shared-asset deletion. Specification
> closure and candidate proof remain separate and open; missing numeric budgets
> or feasibility decisions block implementation, not merely release.
>
> The
> [concrete limits and PR116 integration proposal](client-prepared-media-limits-and-integration-proposal-2026-10-13.md)
> now supplies recommended defaults for approval. Its proposed whole-backend
> source hold is separate from activation flags and is not installed. Neither
> integration, new resource limits nor implementation is authorized by the
> proposal.

Contract revision: IC-1 revision 3, October 12, 2026 (media-required scope
amendment). This is a design and writer agreement for checkpoint 0 of the
[alpha readiness roadmap](identification-history-alpha-readiness-2026-10-11.md),
not implemented behavior or permission to activate a partial lifecycle.

Implementation baseline: `b8eb3d64f66045ba95c4e4fa5feec82d0462d5df`. The SQL
baseline remains the 466-migration catalog referenced by the existing history
evidence; no SQL change or new runtime qualification is claimed here. Exclude
unrelated working-tree changes. Exact document-hash acknowledgements and
validation are recorded in
`.artifacts/initial-completion-agreement/checkpoint.md`.

Participants:

- History primary: thread `01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1`, sole writer.
- Initial-analysis hardening: thread `01a112ae-2c97-77a1-bd53-5a4434510d4c`,
  interface owner/reviewer for the separately planned initial lifecycle. No
  implementation ownership transfers.

The user explicitly authorized coordination and recording this agreement. The
October 12 direct decisions in
[Check current slice](codex://threads/01a12460-a2c6-7b21-abcf-d3be41331b45)
require media for both new identification and reanalysis, and include video
reanalysis in current scope. This amendment supersedes the standalone text-only
milestone and video-reanalysis exclusion while preserving revision 2's original
identity, atomic completion, recovery, accounting, privacy and writer contract.
Its review evidence is `.artifacts/media-required-scope/`; the exact revision
acknowledgement is recorded there separately from runtime qualification.

Fresh eligible image/audio/video may have optional accompanying text. Original
source media is sufficient for reanalysis; absent/removed media needs
replacement or a blocked submission, never text-only fallback or
thumbnails/another version as source. New no-media admission is denied natively
and server-side. Previously server-admitted Describe work and historical records
retain their original route/input identity and exact recovery/deletion. A
local-only queued no-media request is preserved for explicit remediation, not
automatically accepted as replay or silently rewritten; uncertain admission
requires exact status recovery first. No destructive route/data removal or new
invocation follows this rule.

The generated initial DTO stays unchanged unless an explicit later contract
review requires a shape change. There is no new text-only Gemini profile or
text-child gate. Preserve existing media provider policy. Video source reuse,
preparation/retention, immutable media/context and native qualification are
required; video community publication/review is not implied. Production
installation and all activation gates stay disabled.

The separately planned
[Simplify capture tools](codex://threads/01a12c47-6f54-7500-bab9-679c2babf9a0)
visual/session refactor still needs both relevant workstream handoffs and fresh
final implementation approval there. This scope only includes functional media
admission and history journeys, not that refactor or a schedule/ownership
change.

### Current prerequisite boundary — October 13, 2026

After private admitted-proof SQL parity at `8d4f8c50c`, the coherent atomic
admission/original funding/M1, complete private receipt/status recovery,
positive-unused C1 cancellation/expiry and erasure checkpoint is accepted
locally at `bc2a5af507a0ee56cbdb1a357f5221bec611371b`. Independent and IC-1
acceptance and exact shared-checkout evidence are in
`.artifacts/initial-atomic-admission/final-gates/local-checkpoint.json`; this is
not isolated commit-tree or hosted qualification. Stage93's original deadlocks
remain unreproduced, cause unknown, under the recorded residual-risk
disposition; this does not qualify a new dispatch lock graph. The
[C1 addendum](initial-cancellation-interface-2026-10-11.md) defines
cancellation, including the conservative `dispatch_outcome_unknown` outcome; it
is not successful completion. Its three-value response takes precedence over the
original two-value cancellation summary in section 3 below. Provider dispatch,
quota commit, result capture and successful completion remain blocked in this
increment and require the later separately reviewed S0 owner. Exact historical
receipt recovery and live unused-settlement proof remain distinct. The hardening
owner confirmed this clarification on October 12 without any implementation
ownership transfer.

The pure Deno handoff proof checkpoint
`10ffb151a4bf38bdf557cbf163fa27a3682a8b3f` and private SQL parity
`f7b7181ec016b4d37206a290d0f54bce822d463d` are accepted locally. Exact SQL
evidence is
`.artifacts/initial-media-handoff-v2/sql-parity/local-checkpoint.json`; all 172
catalogs/6,672 assertions, 3,821 DB-backed Edge tests and recorded affected
gates pass. This establishes consistency and role denial only, not stored
issuance, physical verification or mutation authority.

The inactive runtime copy/M2 v2/transfer family is implemented and passes its
required local full gates and current-source focused qualification under the
[handoff runtime contract](initial-media-handoff-runtime-2026-10-13.md).
Full-family v6 passes 172 catalogs / 6,706 assertions, 3,935 Edge tests / 598
steps, strict lint and advisor gates (warnings retained). Five affected focused
suites cover owners, private readers, transferred recovery/C1, cleanup
contention and one video/audio resource cohort. Exact shared-checkout sources,
independent and IC-1 decisions, original outcomes, database disposal and local
checkpoint identity are recorded in
`.artifacts/initial-media-handoff-v2/runtime-implementation/`. This does not
qualify an isolated commit tree, hosted CI, installed backend, media structural
validation or device behavior. Historical deadlock evidence remains unresolved
and preserved under its recorded scope; later passes do not waive recurrence
handling. The narrow Ghost target-funding prerequisite stays with history
primary; broader identity-merge and Field Trip ownership do not transfer.

The next bounded dependency is a concrete structural-validator and
transform-attestation protocol for the same immutable retained bytes, under the
[S0 dispatch-fence agreement](initial-dispatch-fence-interface-2026-10-13.md).
The
[revised dependency inventory](initial-media-structure-attestation-2026-10-13.md)
recognizes existing local WAV executable qualification and the original
pre-admission preparation ordering. Its dependency boundary is independently and
IC-1 reviewed. The concrete
[local owner integration agreement](initial-preparation-local-owner-integration-2026-10-13.md)
has exact-source independent and IC-1 launch review. The local owner run and
both existing artifact regressions pass. Independent and IC-1 final evidence
review is complete, and local checkpoint
`b3864361dd5c8b4d921650891ca1926a798d9bb0` is committed. Exact decisions are
retained in `.artifacts/initial-media-structure/owner-final-reviews.json`. The
[next target composition proposal](initial-preparation-target-composition-2026-10-13.md)
names an unqualified Linux worker and its feasibility gaps. Independent and IC-1
bounded design concurrence is recorded in
`.artifacts/initial-media-structure/target-design-v4-reviews.json`; the next
implementation agreement awaits a concrete named target. This authorizes no
installation or execution. This binds the original preparation owner to the
pinned WAV artifact only in a separate Edge-ineligible synthetic fixture; it
does not close target runtime or other-format S0 acceptance. No post-M2
transform or duplicate WAV helper is required. Retained-byte transfer alone does
not authorize a provider grant. Initial dispatch, durable result capture,
successful completion, native media-backed journeys and integrated acceptance
remain open. Installed signer/backend and device qualification retain separately
named authorization requirements. Activation remains disabled and ordinary
access nil. History primary retains all overlapping writes; broader hardening
and capture visual work remain separate. Approved deletion/export/redesign
follow current-scope acceptance.

## 1. Identity and immutable original input

One initial logical operation is keyed by `(owner_id, scan_id)`;
`operation_id = scan_id`. `route` is a frozen enum of `identify-multimodal`,
`identify`, or `identify-describe`, not another execution namespace. Reusing a
scan ID through a different route conflicts. Provider attempts, quota
reservations, recovery claims and media operations keep distinct identities;
none may mint a second primary authorization for the logical operation.

The existing route families derive `generatedScanId` through
`resolveAIRequestId`. Every supported fresh media-backed native request must
durably store and transmit its existing client scan/idempotency identity before
I/O and reuse it after restart. Server fallback generation must not become new
identity on an uncertain native retry. This requirement needs qualification;
current route mechanics alone do not prove it.

The proposed private owner `internal.initial_analysis_submissions` exists before
a scan row. It freezes versioned canonical identity bytes and digest, the full
accepted semantic input, ordered verified media identities, ordered submitted
descriptions, execution configuration and original funding association. Its
durable lifecycle repository, `InitialAnalysisLifecycleRepository`, belongs to
the initial engine; history consumes its completion contract instead of
maintaining a parallel execution framework. Table names here are planned
identifiers, not existing database objects. Two other private record families
share this one owner: `internal.initial_analysis_results` stores write-once
validated result evidence, immutable provenance and original
dispatch/attempt/accounting references; `internal.initial_analysis_completions`
stores the immutable receipt binding input, result, configuration, funding,
descriptions, finalized media and initial projection. Private description
evidence is an immutable projection/table in this repository, not another
completion owner. Dispatch/cancellation/retirement state belongs to the same
lifecycle; a narrow permanent fence may use its own physical table.

Fresh admission requires verified eligible physical media. Descriptions alone
cannot satisfy media eligibility for any fresh route, and cannot identify its
full semantic input. Changed images, inference-affecting context, route, item
order, explicit configuration selection or other semantic input must conflict
even if description text is unchanged. Configuration and funding resolve once
under the existing policy. A retry recovers saved choices rather than comparing
against newly resolved defaults or allocating new funding. Native
session/account generations still fence delivery; a saved owner ID is not
authorization.

Freeze the input before its admission acknowledgement can be lost and before
provider authorization. The immutable admitted value must supply both provider
request construction and completion; mutable
`scan_ingestion_intents.request_payload`, later `scans.captured_media`, notes,
model output and decorated prompts are not original-input authority.

| Producer                       | Source of ordered descriptions                                                                                              | Completion adapter                           |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `identify-multimodal/index.ts` | Accepted normalized contexts in validated owner-timeline order; all descriptions, not only `persistedObservationContext[0]` | `_shared/identify/db.ts:insertScan`          |
| `identify/index.ts`            | Its accepted optional description after existing provider-facing normalization and before prompt decoration                 | `_shared/identify/db.ts:insertScan`          |
| `identify-describe/index.ts`   | Its accepted required description under the existing route semantics, before `buildObservationPrompt` adds telemetry        | `identify-describe/db.ts:insertDescribeScan` |

The Describe producer row above remains an inventory of existing accepted-work
recovery, not permission for fresh text-only admission after cutover. Do not
remove its original recovery path or silently relabel its saved route.

Zero descriptions are an explicit empty ordered array. Each adapter freezes the
route's accepted user text once; SQL verifies identity and bounds without a
second trim or normalization. Do not impose multimodal trimming on another route
silently. Existing initial bounds remain applicable and are represented in
shared vectors; history child text retains its separately specified exact
no-trim contract.

## 2. Minimum dependency S0 and checkpoint boundary

S0 is a shared dependency within the approved roadmap, not an additional product
feature or a second initial engine. Before the new completion path may run it
requires:

1. Immutable admission/input binding, original funding association and execution
   configuration with exact retry/conflict behavior.
2. A permanent logical-operation primary-dispatch fence, bound to the original
   attempt and accounting. Only a fresh successful authorization response
   permits invocation. A recovered or repeated grant response cannot.
3. A durable private validated-result evidence owner retaining the bounded
   original result, original attempt/configuration/funding binding and
   allowlisted initial scan projection. An input digest is not a result and
   cannot finalize missing provider output.
4. Exact media verification/binding and immutable promotion evidence required by
   the retained initial route. Description preservation does not waive media
   lifecycle prerequisites.
5. Pre-row cancellation/deletion, account erasure and permanent non-execution
   versus unknown-execution distinctions across every route and worker.

Checkpoint 1 can prepare the private schema, contracts, gated routines,
enrollment projection and isolated tests using this agreed interface. Existing
live handlers must not switch to a partially implemented path. Integration
acceptance for initial completion waits for S0, fresh media admission/route
adapters, accepted historical-route recovery and affected recovery/cleanup
workers; installed/live qualification waits for the broader required hardening
and external rows. Keep admission/dispatch disabled until exact-media binding
and old-writer/worker quiescence are proven.

Fresh-library scope excludes broad old-store migration/backfill qualification,
while preserving historical records, already server-admitted exact recovery and
competing-writer safety. Existing runtime paths are not silently altered by
preparing inactive contracts. The server-owned
`initial_analysis_lifecycle_enabled` gate defaults false. No client flag or
missing protocol may select legacy execution for an operation bound to the new
lifecycle. The existing handlers either use the complete coordinated path or
remain on the unchanged path while the new path is inactive; there is no
opportunistic description sidecar write.

## 3. Fixed service boundary and atomic completion

All service operations use strict bounded version-1 envelopes, one original
logical identity and fixed routine selection. Transport uncertainty remains a
typed unknown outcome, never a fabricated success or absence. Closed semantic
denials include conflict, unavailable, cancelled and deleted where applicable.

| Fixed operation                       | Contract and successful/held outcomes                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `admit_initial_analysis`              | Atomically bind immutable submission, configuration and original funding association. `admitted(binding)` or `replay(binding)`; neither is dispatch authority.                                                                                                                                                                                                                   |
| `authorize_initial_analysis_dispatch` | Validate original identity/funding/media/consent under cancellation fences; consume permanent one-time logical authorization and commit provider quota. `granted(single-use original attempt binding)` only on a fresh positively received grant, otherwise `held(status)` or closed denial. Complimentary credit consumption remains completion settlement under current rules. |
| `record_initial_analysis_result`      | Original-dispatch-bound immutable validated result/provenance/usage capture. `recorded(result_ref,digest)` or exact `replay`; a conflicting result/provenance rejects. Original late result capture after orchestration expiry requires live ownership and exact dispatch proof, with no new dispatch authority.                                                                 |
| `complete_initial_analysis`           | Resolve immutable submission/result/configuration/funding/media proofs. Atomic completion returns `completed(receipt)` or exact `replay(receipt)`; absent/corrupt durable result is `held(result_evidence_unavailable)`, never inferred from input.                                                                                                                              |
| `get_initial_analysis_status`         | Read-only original owner/scan/expected-identity lookup using the closed status union below. Returns bounded references/receipt internally, never invocation permission.                                                                                                                                                                                                          |
| `cancel_initial_analysis`             | Idempotent delivery of the owner-bound durable cancellation outbox. `cancelled(dispatch_prevented)` or `cancelled(dispatch_already_authorized)`; both fence result resurrection. Neither implies a refund after authorized/unknown execution.                                                                                                                                    |

### Atomic completion

The fixed logical service operation is:

```text
complete_initial_analysis(
  owner_id, scan_id, submission_digest,
  result_evidence_id, result_digest, expected_config_digest,
  expected_funding_identity, finalized_media_proof, expected_completion_digest
)
```

This specifies adapter semantics. Concrete typed SQL declarations are generated
and reviewed during implementation; there is no dynamic routine selector. The
authenticated service adapter derives the owner from verified authority. Private
stores have no direct API-role access, including service-role table access; only
narrowly granted fixed routines cross the boundary.

The transaction resolves the durable submission and validated result, checks
original attempt/configuration/funding and finalized media bindings, then
commits the scan, private ordered submitted-description evidence, versioned
completion receipt and required terminal/settlement transitions consistently. It
uses the existing accounting owners and policy, including applicable named
settlement overrides, never a new allocation. No external I/O occurs while locks
are held. A sidecar write in a second HTTP transaction is forbidden.

Descriptions come only from the immutable submission. The finalizer cannot
accept another description payload. The result projection is validated and
allowlisted; arbitrary caller-supplied scan JSON cannot bypass review or privacy
rules.

The immutable version-1 receipt binds these named fields:

- `version`, `owner_id`, `operation_id`, `scan_id` (operation and scan equal);
- `route`, `submission_digest`, `input_schema_version`, `config_digest`;
- `funding_binding_id`, `funding_binding_digest`, `funding_binding_version`, and
  the original settlement outcome through the completion projection;
- `result_evidence_id`, `result_digest`, `result_schema_version`;
- `ordered_description_digest`, `ordered_description_count`;
- `finalized_media_binding_digest`, `completion_projection_digest`.

Retained records resolve the hashes to immutable exact values while ownership is
live. Exact receipt replay does not regenerate timestamps, model, funding or
projection fields. These private digests and configuration/funding references
remain inside the restricted service/repository contract, not public logs, job
errors or generic client receipts. Initial client response DTOs remain
unchanged; future minimal native recovery projections require explicit contract
review, not accidental exposure of this private envelope.

Specify deterministic bounded canonical encoding and shared positive/negative
digest vectors before executable schema acceptance. Later mutable scan fields
must not change the completion digest.

Exact duplicate completion returns the same receipt after live-owner/deletion
checks, without replacing user edits. Different submission, owner, route,
result, text, item order or immutable completion identity rejects without
mutation. A scan without the matching receipt is a reconciliation/conflict
condition, not successful completion and not permission to retrofit evidence.
`persistOwnedScanRow`'s scan-owner existence check is insufficient for this
contract; neither returned SDK errors nor absence reads alone prove rejection.

## 4. Exact recovery and settlement

The fixed read-only service operation `get_initial_analysis_status` accepts the
original owner/scan identity and expected submission identity. It returns a
closed projection; no branch authorizes provider invocation or chooses funding.

| Status                                    | Permitted next step                                                                                                                  |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `not_found`                               | Reconcile admission facts. After an uncertain write this is not permission to execute, mint another ID or refund.                    |
| `pending_pre_dispatch`                    | Recover the original admitted binding. Only a separately authorized fresh dispatch grant can permit inference; status itself cannot. |
| `recovery_needed(reason)`                 | Exact status/result-evidence recovery or held-state reconciliation. Never a provider retry or timeout refund.                        |
| `result_ready(result_ref, result_digest)` | Claim settlement-only work and complete the exact durable known result under original authority.                                     |
| `complete`                                | Verify and return the exact immutable receipt and recover the same authorized result for delivery. Never scan-owner existence alone. |
| `cancelled` / `deleted`                   | Preserve terminal fences; no private evidence resurrection or result delivery after deletion.                                        |

The closed recovery-needed reasons are `dispatch_outcome_unknown`,
`result_evidence_unavailable` and `write_outcome_unknown`. Before dispatch,
retirement or original-funding release requires proof of non-invocation under
the existing accounting owner; status absence alone is insufficient.

Cross-owner callers receive no private status or existence disclosure. Deleted
status is available only where the existing authorization/fence permits it;
otherwise return the authorization-safe absence/denial projection.

Save validated result evidence before promotion/finalization. Lost result-write
acknowledgement permits exact evidence recovery, not another inference. If
provider execution may have happened but no validated result can be recovered,
retain Recovery needed. No result is reconstructed from an input digest or
provenance alone.

A known original result may settle after original worker lease expiry under a
new settlement-only claim. That claim cannot authorize dispatch, change the
saved result/configuration or replace funding. Deletion/cancellation wins
resurrection. Completion-response loss recovers the same receipt and result;
device delivery is separate from provider execution and financial settlement.

## 5. Privacy and locking

Submission and result evidence exist before the scan, so a scan foreign key
cannot be the only deletion mechanism. Scan-deletion admission must fence the
pre-row identity and erase private submission/result/description/receipt data.
Account detachment and deletion erase those records for both enrolled and
unenrolled scans, including when a restricted scientific scan row survives.
Text-derived digests, private provider outcome material if retained, and the
imported V3 description projection are private and are erased too. Authorized
scientific scalar retention remains unchanged; no private V3 evidence survives
as retained history. No such payload or digest enters scientific retention,
diagnostics or public output.

Retain only the minimum content-free lifecycle tombstone/dispatch-retirement
identity required to prevent resurrection and repeat execution, with explicit
account-erasure disposition in schema review. An immutability guard must allow
authorized erasure. Every admission first-write and exact admission replay
acquires the pre-row deletion fence and checks live ownership; after erasure it
returns the authorization-safe deleted/denied outcome, never the old binding.
The finalizer and duplicate receipt resolver likewise recheck live ownership and
deletion fences before returning private evidence.

New initial lifecycle entrypoints preserve this scoped outer sequence: owner row
`FOR UPDATE` → scan-ingestion transaction advisory → existing scan row
`FOR UPDATE` → history row when present. No fictional parent/history row is
created for initial work. Private submission/result/receipt rows are locked
within that scope. Child paths retain existing parent/source/child nesting;
multi-owner operations preserve deterministic owner ordering.

This is an entry contract, not a blanket replacement of existing nested funding
lock orders. Before SQL acceptance, append the actual expanded function,
trigger, FK and settlement lock sequences/modes to the retained lock inventory
and prove compatibility with deletion, merge and quota/pruning callers. Never
acquire these outer locks late from an opposing inner-lock path. Existing
uncovered contention tests remain required; agreement is not a deadlock proof.

Already-dispatched provider input cannot be recalled by deleting local evidence.
Local erasure fences late callbacks, result persistence and delivery. Provider
cancellation, remote retention and remote erasure remain separately qualified
obligations, with the applicable guarantee or limitation recorded in external
acceptance. Local deletion tests do not prove remote provider erasure.

## 6. Enrollment consumer

History retains `enroll_owned_observation_history`. Under its current owner,
observation and history locks, it consumes the live matching completion receipt
and private submitted-description evidence. It imports the initial result as V3,
without inventing provider execution time or execution digest.

Two exact V3 evidence variants are agreed:

```text
{schema_version: 3, origin: "saved_identification",
 imported_at_ms: <existing bounded integer>, availability: "unavailable"}

{schema_version: 3, origin: "saved_identification",
 imported_at_ms: <existing bounded integer>, availability: "available",
 items: [{kind: "description", text: <exact accepted submitted text>}, ...]}
```

Unavailable means no submitted descriptions; it does not mask missing required
completion evidence for a fresh candidate scan. Available requires a nonempty
ordered list matching the receipt/evidence. Neither variant exposes the private
receipt or funding internals. SQL constraints and all server/native page/state
readers change together. Missing/foreign/deleted evidence rejects enrollment
where the candidate contract requires it; no notes, mutable replay or model
reasoning fallback. Description availability is not media availability. Fresh
source-bound children require independently validated retained or explicitly
chosen image/audio/video evidence plus any accompanying text, as specified in
the amended roadmap. No new standalone text V1 child is implemented. Historical
text readers remain exact; they cannot grant new no-media execution eligibility.

## 7. Sole writer and ordered delivery

History primary retains all overlapping implementation writes during S0 and
checkpoint 1. Hardening coordinates/reviews read-only. This does not authorize
engine implementation in the hardening thread or transfer the conditional
successor reservation from its existing RFC.

| Owner surface                                                                                                                                                                                                             | Reserved writer / responsibility                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `identify-multimodal/index.ts`, `identify/index.ts`, `identify-describe/index.ts`; their canonical preparation values                                                                                                     | History primary implements the agreed adapters when implementation starts; hardening reviews initial-engine semantics.                                                                                        |
| `_shared/identify/db.ts:insertScan`, `identify-describe/db.ts:insertDescribeScan`, new shared lifecycle repository/adapter                                                                                                | History primary owns coordinated atomic completion and exact status integration.                                                                                                                              |
| `_shared/scanPersistence.ts`, `scanIngestionIntents.ts`, `scanIngestionJobs.ts`, `scanIngestionCompatibility.ts`, `scanIngestionRetry.ts`, `_shared/identify/completedResponse.ts`, affected replay/media/account workers | History primary controls overlapping edits; hardening reviews original-attempt/recovery/deletion invariants. No independent writer starts on these paths.                                                     |
| All shared forward migrations, funding/deletion/account routines, private evidence, `enroll_owned_observation_history`, source-media/context contracts and native history queue                                           | History primary, with independent read-only contract/concurrency review.                                                                                                                                      |
| Broader initial-engine hardening and remaining runtime qualification                                                                                                                                                      | Hardening effort retains its design responsibility; implementation assignment follows a later explicit handoff/user instruction. Existing open obligations remain open.                                       |
| This agreement, alpha roadmap and history continuation records                                                                                                                                                            | History primary. Hardening may acknowledge through messages; it does not edit this revision.                                                                                                                  |
| `main-analysis-lifecycle-hardening-2026-10-10.md`                                                                                                                                                                         | History primary owns the explicitly agreed October 12 documentation-only scope amendment/current matrix; Hardening reviews read-only. Historical reviews remain unchanged; no engine implementation transfer. |

Forward migration/dependency order:

1. **A — private lifecycle and fences:** immutable submission/result/receipt and
   description storage, least privileges, permanent dispatch/cancel identities,
   pre-row deletion and account-detachment erasure. No enabled writer precedes
   these fences.
2. **B — fixed service operations and adapters:** admission, status, dispatch,
   validated-result save and atomic completion, then fresh media route/Describe
   admission guards and accepted historical-operation recovery/cleanup adapters
   behind closed gates. Integrate original funding and exact media
   prerequisites; do not switch live traffic early.
3. **C — history import:** V3 completion-backed description projection and
   coordinated SQL/server/native readers.
4. **D — media-backed history children:** photo/audio/video source identity,
   preparation/retention and accompanying context; source fingerprints/profile,
   admission/dispatch/completion/recovery and native action/queue contracts.
   Complete current-scope video reanalysis without inferring publication/review.

These are logical dependency groups, not invented migration timestamps. The sole
writer generates forward-only filenames with repository tooling when
implementation starts and records the resulting ordered catalog. Dependencies
may be reviewed in gated commits; no stage alone authorizes runtime cutover.

## 8. Required acceptance

The history primary records implementation evidence; hardening and independent
read-only reviewers assess the combined contract. Required cases are:

- Fresh media routes and accepted historical Describe recovery: exact replay,
  conflicting completed-ID replay, route collision, changed media/context with
  unchanged text, explicit empty and multiple ordered descriptions,
  route-specific accepted Unicode semantics.
- Lost input, grant, result and completion acknowledgements; process loss after
  dispatch authorization; repeated status and fresh recovery claims cannot
  create another invocation or funding association.
- Known result after lease expiry; duplicate completion; conflicting validated
  result or completion digest; receipt recovery preserves initial completion
  identity and later user edits.
- Transaction rollback leaves no partial scan/evidence/receipt/settlement;
  original accounting settles once under the applicable existing policy.
- Scan deletion before row creation, account detachment and deletion, enrolled
  and unenrolled races in both orders; conflicting-owner denial; no late
  completion or receipt read resurrects private evidence.
- Both closed V3 variants, exact ordered prefill and rejection of missing
  required receipt/evidence; text-only/source-null records cannot enter fresh
  media-backed execution. Media availability is checked independently of text.
- Fresh no-media denial at native and backend boundaries; local-only old queued
  requests are preserved and require remediation, while already server-admitted
  operations retain exact recovery. Unknown admission is never reclassified as
  fresh merely from absence; no silent rewrite or duplicate invocation.
- Effective privileges/catalog and complete nested lock delta checks; existing
  cross-version quota/terminal/multi-owner cases remain independently required.
- Route/worker cutover closure, installed photo/audio/video journeys and hosted
  erasure/media qualification remain separate acceptance rows. Tests with
  injected owners cannot substitute for them.

Any baseline, frozen-input/receipt shape, ownership, lock order or supported
route change reopens this agreement for review. Agreement closes roadmap A1's
design prerequisite only. A2–A6 and A15 remain implementation/qualification
work; final candidate CI and all external/device controls remain open.
