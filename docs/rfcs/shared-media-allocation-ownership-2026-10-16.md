## October 19 — native owner dispatch and settlement separation

`SharedMediaNativeOriginalOwner` owns the registered account lifecycle in its
own file. Its private constructor and file-local capability constructors remain
closed. The repository retains its private constructor, file fences and
file-local binding/mutation/inspection authority constructors. No second owner,
container, drain registration or production installer is introduced.

Every cross-file repository operation requires a dispatch grant tied to the
actual account lease and unique active operation, owner, process epoch and
existing qualification profile. It expires when the operation ends, Auth seals
the owner or pending settlement closes dispatch. Debug fault hooks stay owned by
the controller and grant no runtime authority.

Settlement uses a different capability type, binding a unique pending identity
and exact request only after the loader/file writer has returned. The repository
can only read that receipt, acknowledge completed/held state, or persist the
existing reserved-to-held transition and read it back. It cannot load media,
write files, reserve another operation or mint preparation/cleanup operations.
Missing evidence after a loader started remains closed and retains the fence and
capacity. Only successful exact reconciliation clears pending settlement.

This inactive structural integration preserves the existing qualification
profile, topology, persisted formats, limits and recovery semantics. Scoped
app-container validation, native receiving admission and live composition remain
pending. Activation stays disabled, PR116 frozen, deployment hold active and AWS
unapproved.

The exact reviewed candidate02 passed all 112 methods in eleven focused suites,
with zero failures, skips or Xcode runtime warnings. All 2,838 source/project
hashes and candidate hashes remained unchanged. Evidence:
`.artifacts/native-owner-capabilities-20261019/focused02-result.json`, XCResult
`49eaa7c7223f49bfa27d2fd12a7c2fbe`; candidate02 SHA256
`72e4306e15e96026a0bf543a4a976379f7d44d671c6d5b7ecbb845e6c862a8ea`. Candidate01
was held before execution for a throwing test expression; candidate02 corrected
that expression without a runtime delta. The prior complete-target legacy
partition evidence and focused correction remain historical; this run was
focused shared-checkout validation, not a complete-target rerun,
isolated-source, device, hosted or activation acceptance.

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

## October 16 — joint handoff construction under review

The source inbox foundation is committed locally as `6342477a`. Its successor
implements the adopted joint inbox/P1 agreement in the same isolated owner:
exact request replay, paired source holds, original-account recovery, stat-only
abandonment, S+H+A accounting, and proof-backed source/detached cleanup. Source
and destination work leases have separate disposal rules. Runtime qualification
is pending; no new schema, numeric limit, live composition or activation is
adopted. The current owner contract is the
[shared-storage README](../../apps/ios/Merian/Core/Data/SharedMediaStorage/README.md).

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

# SMA-1: shared native media allocation and cleanup

The agreement below records the original pre-implementation proposal. Current
implementation and validation status is recorded above; outstanding integration
obligations in this agreement still apply.

Proposal-time status (historical): October 16, 2026. Independently and IC-1
reviewed proposed agreement, following local checkpoint `0d6865e40`. This
document specifies the next foundation; it does not install an allocator, change
a schema, adopt new limits, or qualify mixed-producer operation. History primary
remains the sole writer. PR116 stays frozen at `135555d66`. Activation and
ordinary P1 access remain disabled, Supabase integration hold active, and AWS
unapproved. No push, merge, deployment, hosted test, device operation or
schedule change is included.

## Recommendation

Use one durable allocation authority in the existing native SwiftData store,
with additive scalar records in the next schema, currently V60. Keep each media
owner responsible for its namespace and semantic references. The common
authority decides whether bytes may be allocated and when their reservation can
be released; it does not acquire server admission, funding or erasure authority.

Start with an inactive foundation and non-destructive legacy inventory. Then
integrate producers and cleanup one bounded checkpoint at a time. Do not enable
original-photo preparation in ordinary capture until every competing writer is
registered or positively excluded for the complete operation lifetime. This is
more work than counting files at enqueue, but it closes the race between
checking free space and another producer consuming it.

A separate JSON inventory is not recommended: queue/history ownership already
lives in SwiftData, and a second authoritative database would introduce another
cross-store commit and erasure problem. File writes still need explicit durable
intent and recovery because a SwiftData save cannot atomically commit a file.
Migration starts the additive inventory empty and closed to allocation; it does
not discover files or rewrite saved operations inside a migration callback.

## Evidence and unchanged boundaries

At proposal time, the current alias was V59. `PhotoPreparationRepository` owns
four P1 entities and reserves only within its private namespace. Its file owner
takes a shared Documents lock and an exclusive PhotoPreparation lock. Neither
that lock nor the legacy `OfflineQueueStoragePolicy` estimate supplies common
allocation. `FileIOActor` now confines generic access to regular single-link
flat files, but cannot infer durable references or prove writer closure from a
path.

`CapturedMediaPersistenceService`, ordinary queue admission and
`InferenceProcessingActor` still have separate file lifetimes. Reanalysis has
its own private file owner; `ExternalImageImportStore` has an Application
Support inbox and JSON manifest. Queue deletion and library purge have existing
ordering that must be adapted explicitly, not bypassed by generic cleanup.

The adopted
[CPM limits](client-prepared-media-limits-and-integration-proposal-2026-10-13.md)
and
[NCO-1 P1 agreement](client-prepared-media-native-ownership-agreement-2026-10-15.md)
remain authoritative. P1's local qualification and the earlier confinement tests
are evidence for those scopes only. The server reference agreement, audio
quality, video preparation and integrated acceptance remain separate open gates.

## Accounting contract

| Account              | Existing bound and treatment                                                                                                                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CPM pending          | Four packages including the preparing draft; 384 MiB durable total; each complete package at most 96 MiB including metadata. Unknown work retains its slot and liability.                 |
| CPM temporary        | 192 MiB total: 96 acquisition/commit, 64 preparation, 32 transfer/export. One active preparation and one active transfer; export shares that transfer slot.                               |
| New allocation       | At most 288 MiB for a new worst-case package plus its temporary work; preserve 256 MiB free after outstanding allocations. Completely new worst-case admission requires 544 MiB.          |
| Retained library     | Existing physical bytes reduce observed free space. The pending cap is not a total-library quota. No new eviction, TTL or retained-library size cap is introduced.                        |
| Legacy pending/inbox | Inventory their actual bytes and unresolved future allocations. Preserve their existing contract and limits; do not convert them into CPM packages or grant fresh admission by migration. |

For a locked capacity decision, require observed available bytes minus all
previously reserved but not yet materialized bytes minus the requested new
allocation to leave at least the existing 256 MiB reserve for CPM work.
Materialized bytes already reduce observed free space: do not subtract them a
second time there. Separately enforce every applicable package, role, pending
and temporary cap using materialized bytes plus outstanding reservations. Use
checked integer arithmetic and refuse unknown capacity, overflows or
inconsistent totals. Recheck during bounded writes; outside processes can still
consume disk, so reservation is not a filesystem guarantee against ENOSPC.

Count each physical copy, including partials, atomic replacement copies,
processing scratch, upload/export staging and interrupted leftovers. Matching
hashes or APFS clones do not grant a discount. A verified rename within the same
volume does not create a second copy; charge both sides until an ambiguous move
is reconciled. Multiple references to the same immutable owned file count once
physically, while every logical package still satisfies its own role/cohort
limits. Logical sharing never permits exceeding accepted media counts.

Completed-package conversion is not a counter decrement on an AI response.
Retained ownership must be durably acquired before the pending hold is retired,
with the same physical allocation identity preserved. Unknown transitions retain
the conservative liability. This local conversion proves neither cloud retention
nor server reference release.

## Proposed durable authority

Add scalar records for the following responsibilities; final declarations,
indexes, uniqueness and exact file boundary belong to the implementation packet:

| Record responsibility  | Required identity and state                                                                                                                                                                     |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inventory generation   | Library/store identity, contract version, bootstrap cursor and completion state, revision, admission/retirement generation.                                                                     |
| Physical allocation    | Stable allocation UUID, producer/namespace, opaque relative token, physical file identity, measured bytes, byte ceiling, pool/profile, verification and cleanup state.                          |
| Reference/hold         | Stable edge UUID, allocation UUID, authoritative local owner kind/ID, account or explicit unassigned provenance, role, owner revision and live/retired state.                                   |
| Reservation/work lease | Stable work UUID, generation, owning operation, fixed destinations, reserved/unmaterialized and materialized bytes, purpose, process/session identity, writer/read status and closure evidence. |

References and physical charges are different records. Allocation identity
survives package-to-history handoff. No current-login default may attribute an
unassigned import or an older account's files. Known user/account identity is
copied only from its authoritative owner; no raw paths or media hashes enter
diagnostic logs. Native private records may retain what their cleanup duty needs
until verified erasure under the existing privacy contract.

Use one injected authority per store/root composition, with cross-instance
serialization and fresh-context revision checks. A process-local actor alone is
insufficient. A stable lifetime fence covers bootstrap, writers and purge; short
allocation transactions serialize reserve/commit/retire. Namespace owners keep
their descriptor-relative protection. Do not hold the allocation transaction
while awaiting a provider callback or file copy. Persist the reservation first,
retain a lifetime lease, perform bounded work, then reconcile exact identity and
generation in a fresh transaction. Purge closes admission before waiting for
leases; it cannot wait while holding a lock needed by completion.

Before construction, enumerate the full lock acquisition order against existing
P1/reanalysis root locks and queue persistence locks. No adapter may call back
into the allocation owner while holding a lower-ranked lock. Existing P1's
namespace-lock-across-save implementation must be adapted deliberately; simply
wrapping it with a second lock would not establish deadlock freedom.

## Existing-file bootstrap

Bootstrap is a restartable inventory operation, not permission to delete or
relabel media. Keep fresh CPM allocation closed until a complete inventory
generation and all required producer barriers agree. Read in bounded pages and
persist progress; reopen resumes the same generation. No full-library Data load
or unbounded decoding is needed. Before marking complete, revalidate the owner
revision and file identity under the applicable mutation barriers.

| Observed state                                                                | Required result                                                                                                                                                                                                                                  |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| File with exact saved owner reference                                         | Record a `legacyObserved` allocation and reference evidence in place. Preserve bytes, paths, operation identity and historical media role. This observation grants no cleanup or write authority. A processed image does not become an original. |
| Same file referenced by queue and saved history                               | Record both reference observations on one proven physical file. After owner handoff, both become durable holds before any release authority is enabled. Neither queue cleanup nor deleting one version may erase the survivor's bytes.           |
| Referenced file absent or changed                                             | Retain a missing/conflicted record and recovery identity; block dependent fresh submission. Do not substitute another basename, preview or inferred source.                                                                                      |
| Unreferenced or ambiguous file in a managed media root                        | Record a recovery hold and measured liability in place. No age-based sweep, account guess, automatic adoption or recursive deletion.                                                                                                             |
| Unsupported entry, symlink, hard link, inaccessible root or corrupt inventory | Refuse adoption and keep the affected allocation gate closed. Preserve evidence/state; do not follow the entry or broaden a permitted root.                                                                                                      |
| Other app files outside managed media roots                                   | Exclude from media ownership; their occupied space still affects actual free capacity. The allocator is not a whole-Documents cleaner.                                                                                                           |

Reconciliation first asks the existing producer/queue/history owner for exact
references and original work status. Proven completed local work can finish its
original commit; proven abandoned local work can retire under its existing
discard authority. An unresolved file stays held, with a specific recovery
reason. Explicit user discard may release only the named local owner after
writer closure and survivor checks; it cannot authorize remote erasure or infer
an unused AI operation. Missing bytes need replacement for a fresh submission,
while exact admitted recovery retains the original operation meaning.

Ordinary existing-library reading remains available while bootstrap is held.
Temporary-directory entries are ephemeral observations, not durable originals;
the OS or existing producers may remove them. Scan only registered media
destinations there, never adopt the entire temporary directory. A later producer
handshake must establish a durable owner before a temporary source can count as
retained media.

Do not gate the currently shipping legacy path through this unfinished owner.
Installation of coordinated writer barriers belongs to the later integration
checkpoint; no claim of a stable concurrent inventory is made before then.

## Producer and cleanup ownership

| Participant                            | Required integration before mixed operation                                                                                                                                                                                                                      |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1 original acquisition/preparation    | Replace namespace-only capacity authority with shared reservations; keep P1 role/immutable-context validation and private file ownership.                                                                                                                        |
| FileIO and capture/queue media         | Reserve before any copy/write; commit exact files and caller/queue holds durably; a failed queue insert retains caller draft and the cleanup duty for provisional copies.                                                                                        |
| Audio/video processing                 | Reserve source, output and scratch separately before processing. Freeze only final approved recipe output; this agreement does not settle recipe/quality acceptance.                                                                                             |
| External import inbox                  | Register before copying into Application Support; retain explicit unassigned import ownership until an account-bound handoff. Destination commit acquires a hold before source release. If copied, both files remain charged until source deletion is confirmed. |
| Reanalysis/history                     | Acquire source holds before preparation; commit child references before retiring preparation holds. Never reconstruct submitted evidence merely to repair missing inventory.                                                                                     |
| Upload, download and export            | Register staging and original task/session identity; reattach or reconcile existing tasks on restart. URLSession/system-owned copies need measured coverage or a proven exclusion before qualification.                                                          |
| Queue/scan/draft/nonbiological cleanup | Request retirement of the exact owner/revision. Paths and `validPaths` cannot authorize shared-file deletion. Preserve current domain deletion authority and unrelated owners.                                                                                   |
| Auth/library purge                     | Close admission, drain actual local/background writers, retire applicable references, reconcile/unlink through namespace owners, then remove the last cleanup authority. Failure retains the barrier and recovery records.                                       |

An inbox manifest remains its content catalog, not an independent capacity
counter. Until its adapter exists it is an excluded competing producer, not
assumed to honor P1 locks. The same applies to every unmapped temporary writer.
Bootstrap labels inbox entries `unboundInbox`. Retain this accountless owner
across an account switch; do not include it in an account's erasure by guessing
ownership. An account-bound destination obtains a separate exact handoff hold;
source discard still belongs to the inbox owner. Global capacity sees both. Any
producer outside the chosen composition must be demonstrably drained and blocked
for the whole operation, not merely absent when a test starts.

Cleanup saves retirement intent before unlink. Last-reference retirement must
serialize with new reference acquisition; readers, exports, copies and
unresolved writes retain holds. After actual writer closure and zero surviving
holds, the namespace owner verifies the exact identity, unlinks and synchronizes
the directory, then acknowledges physical release. Lost acknowledgement causes
reconciliation of that identity, not a second arbitrary delete. Never reuse a
retired token for a new file. Failure remains charged and retryable; TTL expiry
or cancellation request is not closure.

After process restart, a killed in-process writer can be reconciled only after
exclusive lifetime fencing and inspection of its fixed destinations. Background
URLSession work may outlive the process and needs its original session/task
terminal evidence. Local closure does not prove that a remote PUT or AI request
has ended. Remote reservations, references, late-upload cleanup and funding stay
under the existing backend authority. Unknown AI execution permits
status/outcome recovery only, never another provider invocation or refund.

## User experience and acceptance

At a cap, unavailable file or unresolved inventory, preserve draft text,
selection, owned originals and the original operation identity. Explain whether
the user needs free space, source reselection or recovery of existing work. Do
not compress an original, discard history, silently split a package or fall back
to text-only submission. If a provider temporary file was never durably
acquired, state that reselection is needed rather than claiming the source was
saved.

The first implementation checkpoint is an inactive allocator/repository with
disk-backed recovery tests and a non-destructive inventory adapter. It includes
the outgoing V59 freeze/build before additive V60 changes, migration/startup
registration, library-liability inspection, and isolated namespace fixtures. It
does not wire AppDI/live capture, replace production cleanup or mutate actual
user media. Final source/file inventory and lock order require independent and
IC-1 review before implementation; this proposal is not that exact candidate.

| Gate                         | Measurable pass criterion                                                                                                                                                                                                   |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Migration/bootstrap          | Disk-backed V59→V60/reopen preserves all old records and files; additive state cannot admit until inventory complete. Interrupt each page/commit and recover without duplicate charges or destructive adoption.             |
| Accounting                   | Exact cap accepted; cap+1 denied before allocation; checked overflow/unknown space denied. Two owner instances race in both orders without oversubscription. Existing library bytes are not mischarged as pending packages. |
| Write/commit/restart         | Interrupt reserve, write, flush, rename, ledger commit and owner handoff. Every physical copy has a conservative liability; zero cleared drafts lose the sole original. Ambiguous saves keep original IDs.                  |
| Reference/deletion           | Two live owners share one file. Delete each first, race a new hold with retirement, interrupt unlink/acknowledgement and verify surviving owners remain readable and retired identity cannot resurrect.                     |
| Bootstrap conflict           | Missing files, cross-account references, unknown entries, legacy text-only queues, basename collisions and private namespaces preserve exact historical semantics and cannot become fresh admission.                        |
| Account/cleanup              | Close-before-drain and failed purge retain authority; stale generation cannot allocate/commit. Restart does not treat cancellation or elapsed time as background writer closure.                                            |
| Mixed producer qualification | Every listed writer registers or is enforceably excluded. Measure maximum physical coexistence, scratch and transfer copies within unchanged pools; mocks alone cannot close G3.                                            |

Run focused checks then complete affected native/migration/project gates using
the managed build cache. Reuse unchanged prior evidence only for its original
scope. Retain failures; no source edits during compilation. Workstation headroom
must remain at least 20 GiB; it is separate from the device reserve. Device and
hosted acceptance require their existing separate authorization.

## Decision and next boundary

Recommend additive SwiftData ownership, conservative in-place bootstrap and
reference-directed release. These preserve the approved limits and retention
policy. The tradeoff is deliberate: inconsistent legacy state blocks fresh CPM
work until reconciled instead of being swept away. No new automatic eviction or
legacy-data deletion policy is requested.

This agreement does not close G1–G4 or permit activation. After review, prepare
the exact inactive foundation file/lock/migration packet, then implement and
qualify within the authorized local scope. Producer integration follows that
foundation. Remaining media acceptance precedes version deletion/source export
and the approved Identification/History redesign; capture-tools visual changes
and broader engine/Field Trip ownership remain separate.

## Source anchors

- [Schema alias](../../apps/ios/Merian/Models/Aliases.swift),
  [V59](../../apps/ios/Merian/Models/Schema/SchemaV59.swift),
  [migration plans](../../apps/ios/Merian/Models/SchemaVersions.swift) and
  [container recovery](../../apps/ios/Merian/Core/Data/StoreRecovery/Services/ModelContainerFactory.swift).
- [P1 repository](../../apps/ios/Merian/Core/Data/PhotoPreparation/PhotoPreparationRepository.swift)
  and
  [file locks](../../apps/ios/Merian/Core/Data/PhotoPreparation/PhotoPreparationFileStore.swift).
- [Legacy FileIO](../../apps/ios/Merian/Core/Data/Database/FileIOActor.swift)
  and
  [queue deletion](../../apps/ios/Merian/Core/Data/OfflineSync/Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift).
- [Captured-media persistence](../../apps/ios/Merian/Core/Data/CapturedMedia/CapturedMediaPersistenceService.swift),
  [inbox](../../apps/ios/Merian/Core/Data/Images/ExternalImageImportStore.swift)
  and
  [reanalysis files](../../apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisFileStore.swift).
- [Library purge](../../apps/ios/Merian/Core/Data/Database/ScanLibraryPurgeService.swift)
  and
  [liability inventory](../../apps/ios/Merian/Core/Data/OfflineSync/Persistence/LibraryMutationInventory.swift).

## Review result

Independent review and IC-1 concurred on candidate01 without an agreement-level
blocker. Exact hashes and review receipts are retained in
`.artifacts/shared-media-allocation-agreement-20261016/`. This is proposal
concurrence, not implementation or acceptance closure. The next exact packet
must resolve lock ordering, irreversible retirement that rejects new holds,
account-specific versus whole-library purge, and whole-lifetime producer
registration/exclusion. These are implementation contract obligations, not
permission to change limits, discard unknown media or activate P1.

## Cloud-backed local-cache policy direction — approved October 16

The user approved this revised direction in planning thread
`01a12460-a2c6-7b21-abcf-d3be41331b45`, turn
`01a14730-9707-7a03-b0b6-0ec88a3c58be`, for the cloud-retention integration
checkpoint. It does not interrupt the current local implementation, enable cache
eviction now, or change pending-package, temporary-space or safety limits. Use
the existing shared ownership/recovery system; no separate storage owner.

Replaceable cloud-backed originals use a bounded least-recently-used cache.
Evict eligible local replicas for budget or storage pressure, not solely because
of elapsed age. The earlier seven-day expiry suggestion is superseded. Backend
acknowledgement must establish that the exact original is durably retained and
recoverable under the correct owner, with no active local dependencies or
leases. Never evict the only copy, unsynced drafts, or pending, interrupted or
uncertain work. Upload success or an analysis receipt alone is insufficient.

Local eviction preserves history, cloud originals/references and the user's
Photos library. Reanalysis/export retrieves the exact authorized original when
absent. Offline original availability is best-effort; guaranteed Keep offline is
separate future work. Previews require separate bounded policy and accounting.

The 256 MiB original-cache size remains a provisional test candidate, not an
approved final limit or measured optimum. Validate representative photo, audio
and video workloads at cloud-retention integration, then resolve final original
and preview budgets explicitly. Eligibility, release intent, writer closure and
recovery proofs remain mandatory. This policy approval does not authorize hosted
testing, deployment, external publication or activation.
