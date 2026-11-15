# Consolidation hosted-validation checkpoint — November 13, 2026

## Original candidate checkpoint

The user approved publication and conditional release of
`0b06154b328edbd2cb3d7e060c5a021d48ee2ddf`. It is published in draft PR 152.
Protected main has not moved, and no backend or production-site deployment has
been performed. PR 150 remains separate. The Scan ID History owner confirmed its
independent local simulator work uses synthetic seeds and no beta-dependent test
window; its checkout, app commits, simulator and caches remain untouched.

Both Vercel projects have Auto-Assign Custom Production Domains disabled, saved
and independently read back. Required checks are not yet configured. Importing
the approved SHA on either project exposes only one `test` check, linked to web
job 132315530285 in run 43551741587. The admin identity therefore cannot be
independently verified. The repair gives the two jobs their explicit
package-specific names without changing their validation commands.

The exact-SHA web and admin workflow-dispatch runs passed (43551820397 and
43551822578). Agent Quality passed. Markdown Quality failed on the unformatted
Next.js-generated block in `apps/web/AGENTS.md`; the repair formats that block.
iOS Project Guardrails failed because the new generated-identity test requires
an undeclared `xcodeproj` gem and opens an incorrectly capitalized project path.
The repair keeps the structured assertion, uses the tracked lowercase path,
exposes parser stderr on failure, and provisions a locked parser bundle in the
Ubuntu job. Native startup-safety validation separately timed out during its
18-minute build step before tests ran. The repair allows 35 minutes for that
build within a 65-minute job while preserving the selectors and 12-minute test
limit. This checkpoint does not claim that gate passed. Remaining hosted results
must be read before any release decision.

The unsigned Release archive subsequently passed. Three of six critical UI
smokes failed while looking for `MainTabBar_Scans`. The checked-in production
button already uses `MainTabBar_Naturebook` and sets the same `isScansOpen`
binding. The repair updates only those three stale queries, preserving their
queue, audio and retry assertions. It changes no app source, Debug seed or
shared UI launcher. Their hosted runtime rerun remains required; no repaired
UI-test pass is claimed.

The read-only migration inspection from protected main succeeded in run
43551825109 against beta `qlarqavoqhkuwzmevrmf`: 520 remote versions, no
remote-only versions, and neither `20261108062742` nor `20261108185855` applied.
Comparing the candidate leaves only `20261113222833` and `20261113222835`
pending. The checked-in migration planner returns `normal` against that retained
inventory. This is read-only evidence, not a migration execution receipt.

The repair is local and requires approval of its replacement SHA before
publication or release. The original packet's holds, exact-SHA validation,
protected-main checks, backend-first promotion order and stop conditions still
apply. No failing or ambiguous check may be bypassed.

## Approved replacement and second repair preparation

The user subsequently approved replacement
`d87d87c3040ddd269c8124c23bf78d830507a5c1` under the same packet. That exact
commit was published to PR 152. Both saved Vercel holds remain active, and the
distinct Production deployment checks were configured and independently read
back: `Naturebook Web Quality / test` on `naturebook` and
`Naturebook Admin Quality / test` on `naturebook-admin`. Their imported provider
links resolve to separate jobs 132328770404 and 132328769966, respectively.

On this replacement, web/admin dispatch validation, Markdown Quality, Agent
Quality, iOS Project Guardrails and iOS Startup Safety passed. Dispatch run
43556014258 passed all six critical UI smokes, with zero failures or skipped
tests; artifact 14099531361 retains the exact-SHA evidence. The full native unit
and unsigned archive results remain pending at this checkpoint. Backend dispatch
43556012111 attempt 1 failed on an exclusive migration lock before private
handoff provisioning. The parallel same-SHA PR run passed that step; one
failed-jobs retry is running. Original-candidate backend dispatch 43551816497
subsequently passed, but its different SHA cannot qualify this replacement.

The original candidate's full-unit job 132316121184 reported a missing Debug
fixture consumer in `BackgroundAccountWorkArchitectureTests`, then exceeded its
40-minute limit while continuing serial Swift Testing cases. The failing test
and fixture are unchanged in the replacement. A second local repair preserves
the exact production consumer list and separately verifies the sole fixture's
whole-file Debug guard, activation guard and explicit launch flag. It grants the
complete serial unit step 120 minutes within a 165-minute job; the common
workflow-security limit admits only that exact validation job as an exception.
All production-job limits, test selectors and result assertions remain intact.
This local repair requires its own exact-SHA approval before publication.

This is an incremental replacement of the existing public/admin deployments
serving `c435ea80f5bace1d28b6fc383f290c264c73d3d9`, as retained in the approval
packet. It does not enable DwC-A. The initial-launch fault-injection checklist
is not a new incremental-release requirement; its historical completion record
was not located and is not claimed by this checkpoint. No ad-hoc production
fault tests or cleanup are authorized. Main, beta and both production domains
have not been changed by this operation, and PR 150 remains separate.

## Second approved replacement and simulator qualification repair

The user approved `936f1d72e246c621ae1ac31be5cad9205e6fbfcb` and it was
published to PR 152 under the same gated packet. Exact-SHA backend dispatch
43559253813 passed all three jobs, including Candidate readiness, retaining the
same-attempt C1 and private-handoff artifacts. The checked-in reuse resolver
returned `exact_candidate_verified`. Its native dispatch 43559255692 passed all
six UI smokes without skips and the unsigned Release archive. Web, admin,
startup, project guardrails, Markdown and Agent Quality checks also passed.

The still-running full native unit job reported two failures at
`CaptureNativePhotoRoleAllocationTests.swift:309`: the `accepted` cases in
`freshCaptureSendsOneFrozenSourceAndFencesChanges` and
`firstOriginalPutChecksExactProgressOnce` both observed no `completedRoles`.
Their retained V13 state has an authenticated role-progress receipt, but no
measured-transfer retirement callback. Independent review traced that callback
to the unchanged exact simulator qualification in `PinnedNetworkTransport`:
arm64, iOS 26.5 / `23F77` / `iPhone18,1`. The generic CI selector instead chose
the current simulator. The same dispatch's UI evidence identifies that
destination as iPhone 18 Pro, iOS 27.2 build `24B8117`. These are substantive
failed assertions, not a new timeout pass or a flaky-test exemption.

The local repair prepares and verifies the existing qualified simulator before
the full unit lane, with a bounded Apple runtime installation when needed. It
refuses local/self-hosted execution, runtime/build/model mismatches and injected
simulator identity. It preserves the app's measured-transfer safety fence, all
tests, the pinned compiler, production job limits and the 120-minute native test
budget. The unit validation job grows from 165 to 175 minutes to retain ten
minutes for other setup and evidence after the new ten-minute qualification
step. Its helper command budgets total at most 550 seconds, below that step's
deadline. The exact-job security exception and workflow budget contracts move
together. A non-passing qualification receipt is retained on setup failure or
interruption. Portable adversarial tests cover selection and refusal paths;
hosted installation and complete native validation remain required. This repair
needs a new exact-SHA approval before publication. The running failed candidate
is retained to collect its remaining diagnostics; no full-unit pass is claimed.

Local repair verification passed the complete portable `test-ios-ci-tooling`
target, all 14 final simulator-qualification tests, 27 workflow-security tests,
recursive Edge formatting (1,977 files), changed-test lint, changed Markdown
formatting and diff checks. Independent review found no remaining actionable
issue after the budget and failure-evidence corrections. No local app build or
runtime installation was performed. Backend PR integration 43559231788 also
passed, but neither backend run clears the native failures or qualifies a future
replacement SHA.

## Third approved replacement and exact-build request correction

The user approved `daa624a49327fc88cd14585ebc43caf37e28f354` under the same
packet, and it was published to PR 152. The Vercel holds and distinct Production
checks were read back immediately before publication. Web/admin dispatch and PR
checks, Markdown, Agent Quality and iOS Project Guardrails passed.

The PR native unit job 132368534307 stopped before compilation because the
helper's release-number request, `-buildVersion 26.5`, installed simulator build
`23F73`. The existing exact-build check correctly refused it. Artifact
14104190221 retains the non-passing qualification receipt; no full native result
is claimed. The download completed within its budget, so no timeout increase is
justified for downloading. Apple's
[Xcode release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_1-release-notes.md)
document that `-buildVersion` accepts an exact build update number as well as a
release number. The local correction requests `23F77` explicitly and preserves
the independent installed/build/device readback and all tests. Its regression
now rejects a release-number download request. Hosted exact-build selection and
completed boot remain required on a newly approved replacement.

The exact-SHA manual unit job 132368597470 separately downloaded the required
`23F77` build, but its new simulator exceeded the 120-second boot deadline. This
proves the release-number selector was insufficiently specific and that the
two-minute boot budget was too short for this observed hosted attempt. The
correction gives boot readiness the same five-minute bound already used by the
UI lane. Helper command maxima total 730 seconds within a fifteen-minute
qualification step. Only the unit validation job grows from 175 to 180 minutes,
preserving ten minutes for other setup/evidence beyond the declared package,
compile, qualification and unchanged 120-minute test budgets. A boot timeout
retains bounded progress from the new, empty hosted simulator for diagnosis.
Exact-job security and workflow contracts track these bounds; production jobs
are unchanged. A further boot failure still blocks native testing and release.

The superseded `936f1d7` manual native run was cancelled after its failed path
was diagnosed, to free hosted capacity. Its final retained log contains 25
issues within the same photo-role helper. Independent review traced every
recorded issue to the absent qualified retirement callback and consequent
missing successor/admission state; none is waived. The current complete native
gate must still execute every case. Main, beta and production domains remain
unchanged, and this further local correction again requires exact-SHA approval
before publication.

## Fourth approved replacement and runtime cache preparation

The user approved `55b73a1bd9a2bc2c50768b066830012e75550042`, which was
published to PR 152 after both Vercel holds and Production package checks were
read back. Both the PR unit job 132482605755 (run 43606546399) and exact-SHA
manual unit job 132482805955 (run 43606578336) installed the required `23F77`
runtime, then failed the unchanged 300-second boot check. Retained qualification
artifacts 14118454121 and 14119130620 independently show the same
`com.apple.-0LaunchServicesMigrator` data-migration wait through the deadline.
Neither run compiled or executed the native unit target. Download selection is
corrected; successful boot and full native validation remain unproved.

The next local repair explicitly waits for runtime cache readiness before
creating the device. Apple's
[Xcode 26.4 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes.md)
document degraded performance during cache preparation and the supported
completion command. Chromium's
[simulator helper](https://chromium.googlesource.com/chromium/src/+/93b31d4424cb0fddb7cb5a901f21eb9859270658/ios/build/bots/scripts/iossim_util.py)
uses `xcrun simctl runtime dyld_shared_cache update <runtime-id>` before boot.
The repair uses only the already verified iOS 26.5 runtime identifier on an
arm64 GitHub-hosted runner. Cache preparation is a plausible compatibility
mitigation; the retained migration wait does not prove caches caused it or that
this change will resolve it. No security setting or Apple migration is bypassed.

The cache operation has a 600-second bound and fails before device creation on
error or timeout. Existing download and boot limits stay unchanged. The helper
command maxima total 1,330 seconds within a 25-minute qualification step; the
unit validation job allows 190 minutes, preserving ten minutes for other setup
and evidence after package, compile, qualification and unchanged 120-minute test
budgets. Production limits and test assertions stay unchanged. Passing cache
preparation cannot substitute for booted identity or native test results. This
local change requires replacement-SHA approval before publication.

Fresh read-only inspection 43606754802 at 14:48 UTC on November 14 still reports
520 beta migrations. The exact candidate planner returns `normal`, with only the
two approved retimed migrations pending and both obsolete versions absent. The
function plan remains the original 125 functions against the last successful
actual deployment `c435ea80f5bace1d28b6fc383f290c264c73d3d9`. GitHub's PR
integration tree equals the approved `55b73a1` tree. These read-only checks do
not clear either native failure or authorize a different source SHA.

Earlier read-only inspection 43565069349 also reported 520 beta migrations. The
candidate contains 522, with only the two approved retimed migrations pending;
both obsolete versions are absent and the planner returns `normal`. The
deployment-baseline resolver still identifies `c435ea8`, and the function plan
remains exactly 125 functions. No main, beta or production-domain change has
occurred. PR 150 and History's active checkout remain separate.

## Fifth approved replacement and bounded identity queries

The user approved `2bde1d57d777435a0011b5b3abae931e26ca24e5`, published after
both Vercel holds and Production checks were verified again. Exact-SHA manual
unit job 132489999411 (run 43608984201) and PR unit job 132490266510 (run
43608950244) both installed `23F77`, completed runtime cache preparation and
returned successfully from the 300-second boot check. Both then exceeded the
10-second deadline on the first `SIMULATOR_RUNTIME_VERSION` environment query.
Artifacts 14119559763 and 14120936884 retain the non-passing receipts. Neither
unit job compiled or executed the app tests. This confirms a repeated query
availability timeout, not an observed identity mismatch; its underlying runner
service cause remains unproved.

The next local repair gives each of the three sequential `simctl getenv` reads
30 seconds. It still requires the exact values from the owned simulator and
stops on any timeout, command error, missing value or mismatch, without retry or
fallback. The helper command maxima become 1,390 seconds within the existing
25-minute preparation step. Cache, boot, compilation, full-test and enclosing
job limits remain unchanged. Portable tests cover each timed-out identity read,
the non-passing receipt, no later query or retry, and the aggregate time budget.
The larger query allowance is a bounded mitigation, not a proven hosted fix.

The exact-SHA manual UI lane passed all six required cases and its Release
archive passed structure, embedded-product, privacy-manifest and dSYM checks. PR
startup/migration safety and both package quality checks also passed. The PR
backend run 43608950265 separately failed C1's
`prove_three_admitted_counter_topology` assertion; its fixture admission steps
passed, but the aggregate failure alone does not identify which topology
predicate differed. Artifact 14120368722 is retained for independent review. The
manual exact-SHA backend run 43608981701 passed its complete C1 stage and is
continuing private-handoff qualification at this checkpoint. That comparison
does not clear the PR failure or qualify a replacement source.

Independent source review found that `counter-images` requires three admissions
to share the same minute-based quota windows but did not establish that fixture
precondition. The failed PR fixture ran across 15:48:00 UTC. This is consistent
with a window rollover, but the retained aggregate assertion cannot prove that
was this failure's cause. The companion `counter-order` suite already has a
bounded, sampled precondition for the same assumption. The local repair shares
that existing helper and database sampler with `counter-images`: verify the
60-second user/IP policy and daily counter, require 50 seconds of usable runway,
allow at most one wait/resample within 55 seconds, then admit the three scans.
No admission is retried and no clock, policy, production SQL or assertion is
changed. Precondition failure closes the fixture before any admission. Portable
tests cover that ordering, failure cleanup, read-only bounded sampling, and the
existing near-boundary and midnight cases. C1's retained source manifest also
fingerprints the shared helper. Fresh disposable-database C1 qualification
remains required; this preparation does not clear the failure.

Main, beta and both production domains remain unchanged; replacement-SHA
approval and every new exact-SHA prerequisite remain required before publication
and release.

Local validation passed the complete portable iOS tooling target, complete
Supabase tooling target, 19 simulator-qualification tests, 14 deterministic
counter-window tests, 27 workflow-security tests, recursive Supabase formatting
and changed Markdown formatting. Independent reviews found no remaining
actionable issue after the shared helper was added to the source manifest. No
local simulator or database was used for these repairs. Hosted native
qualification, complete unit execution and fresh-database backend validation
remain unproved for the replacement.

## Sixth approved replacement and identity-process output capture

The user approved `306a3a4bfb09a872a3b52c500eece2992ad95cad`, published on
November 14 at 16:20 UTC after both Vercel holds and Production checks were
verified again. Exact-SHA manual run 43615068314 passed runtime installation,
cache preparation, boot and all three identity queries. Its complete unit target
compiled and is executing at this checkpoint; its UI smokes and Release archive
passed. Both manual backend run 43615065954 and PR run 43615029156 passed C1 and
are continuing private-handoff qualification. These partial results do not clear
the remaining gates.

PR unit job 132508534088 exceeded the first identity query's 30-second deadline.
A single targeted retry, justified by the independent manual qualification
success, failed the same query in job 132519075126. Artifacts 14121767267 and
14123965402 retain the non-passing receipts. Neither PR unit attempt compiled or
executed the app tests. The receipts do not contain partial query output or
direct-process status, so they cannot distinguish a running query from a child
retaining its output pipe. The inherited-pipe explanation remains a hypothesis.

The next local repair captures only the three identity queries in automatically
removed temporary files and waits for each direct process. A synthetic-process
test reproduces a child retaining stdout after its parent exits: pipe collection
times out while direct-process waiting with file capture completes. This proves
the mitigation handles that failure mode, not that it caused the hosted
failures. Exit code zero and the exact bounded ASCII identity remain mandatory.
Missing, wrong, oversized or invalid output, nonzero exit and timeout all fail;
even exact partial output at timeout cannot qualify the simulator. Timeout
receipts add only the identity key, process status, output-presence/exact-match
booleans and cleanup outcome. They never retain raw partial output. Only the
direct query process is killed, with a five-second reap deadline; no process
group or simulator service is terminated. Positional reads leave the shared
output offset unchanged.

The 30-second query deadlines, 25-minute preparation step, 120-minute full unit
target and 190-minute job remain unchanged. The successful command maxima remain
1,390 seconds; timeout cleanup adds at most five seconds. No runtime app code,
SQL, C1 assertion or production limit changes. Portable tests use synthetic
processes and mocks without touching a local simulator. This local repair needs
independent review, complete portable validation and explicit replacement-SHA
approval before publication. Main, beta and both production domains remain
unchanged; PR 150 and History's work remain separate.

Local validation passed all 26 simulator-qualification tests, the complete
portable iOS tooling target (302.5 seconds), all 27 workflow-security tests,
changed Markdown formatting and diff checks. Independent review found no
actionable defect. The full native target is still running for the published
`306a3a4` source; no hosted result is claimed for this local replacement.

## Full native timeout and approved isolated-shard recovery

For approved source `306a3a4bfb09a872a3b52c500eece2992ad95cad`, manual backend
run 43615065954 and PR run 43615029156 both passed all C1/private-handoff and
readiness stages. The canonical reuse resolver verified manual attempt 1, and
both required artifact download digests were verified. Exact-SHA web/admin,
critical UI and Release archive validation passed.

Manual native job 132508670119 in run 43615068314 qualified its simulator and
compiled the targets, then exceeded the 120-minute full-unit deadline. Its log
has 2,155 passed-test markers and 91 passed Swift suites with no located
assertion-failure marker. Those are incomplete observations, not a passing
result; the interrupted XCResult lacks its final Info.plist. The photo-role
allocation suite alone completed in 4,428.651 seconds. Failure artifact
14127495944 and evidence artifact 14127039917 were digest-verified. Both failed
PR identity-query attempts and the full-target timeout remain retained.

The user explicitly selected isolated CI sharding with complete coverage and
unchanged assertions. The local implementation builds one portable product and
inventories the complete target, assigns whole suites to at most sixteen
isolated runners with four concurrent shard jobs per workflow, and verifies
selected inventories before serial execution. A new aggregate requires every
compiled method exactly once, all observed parameter leaves passed and unique,
zero failures/skips, source/run/attempt/product/plan identity, and unchanged
critical-case validation over raw trees. A new attempt requires rerunning all
jobs together; old successful shard artifacts cannot be mixed with new ones.

The build/inventory job allows 95 minutes. Each shard retains 25-minute exact
simulator preparation, allows 240 minutes for its assigned serial suites, and
has a 330-minute job limit. Aggregate reconciliation allows fifteen minutes. The
historical scheduling hints do not establish current runtimes. Native production
code, SQL, fixtures, assertions, parameter matrices and device resource limits
remain unchanged. Review found the existing shared-process leases and
queue-context restoration operate per test; no declared cross-suite state
dependency requires all suites in one runner. Separate processes lose incidental
detection of leaks perturbing later suites on a different runner; per-suite
lifecycle/race assertions and per-shard serial execution remain.

The source already includes the earlier native236 read-checkpoint optimization;
old native230 profiles cannot identify the current remaining hotspot. Sharding
makes full validation schedulable but does not fix or qualify Release/device
responsiveness. History's active composition work and PR150 stay separate. No
later History changes are imported. The independently reviewed local
simulator-query repair `9c435bff7` remains part of the unpublished candidate.
Replacement-SHA approval, both Vercel holds/checks and all new hosted exact-SHA
prerequisites remain required before publication, merge and deployment.

Local validation passed the complete portable iOS tooling target (311.2
seconds), the complete Supabase tooling target (287.8 seconds), seventeen
shard-evidence tests, two workflow-contract tests with adversarial mutations,
all 26 simulator qualification tests, all 27 workflow-security tests, all 26
documentation contract tests, recursive Edge formatting and changed Markdown
checks. The final Supabase gate includes 169 standard TypeScript sources, 73
standard test files, two isolated DTO test files, one isolated evaluator and 24
shell test files. The first tooling run stopped at synthetic terminal input in
the restricted sandbox. The first terminal-capable rerun caught required
documentation wording removed during triage cleanup; that wording was restored,
its focused contract passed, and the final complete gate passed. Both failed
attempts remain retained.

Independent helper/evidence and workflow/contract reviews found no remaining
actionable defect after correcting aggregate source verification, retaining
aggregate diagnostics on failure and updating triage ownership. The final
focused tests also verify the Linux aggregate's different checkout location
cannot relax source, run, attempt or digest identity. The security timeout
exception applies only to unit shards; production job caps remain unchanged. No
local simulator was used. History's later composition migration
`20261114192749_prepare_composition_source_contract.sql`, native composition
files and backend candidate-list additions remain excluded. Portable product
transfer, compiled enumeration/result mapping and the complete shard matrix
still require new exact-SHA hosted validation; local tests do not establish
them.

## iOS 27 identity observation and full-coverage requalification candidate

The frozen PR152 source `eae69e56924f61b33b0081d49de30fec6a6d5495` cannot
satisfy complete coverage on iOS 26.5: seven compiled Foundation parser methods
require iOS 27. The user authorized fixing that conflict without skipped tests,
keeping PR150 and active History work separate and preserving every prerequisite
before merge or deployment. Diagnostic publication is authorized separately;
PR152 and main remain frozen.

Diagnostic source `4f50e0b2ca1d5fcbe3651ce5a06438eeb12dfa04`, run 43683773270
attempt 1, compiled successfully inside its sixty-minute limit and passed the
single identity XCTest with zero failures or skips. Its original verifier failed
because Xcode exported the named attachment with an index and UUID before the
`.json` extension. Artifact 14150013188 was independently digest-verified
(`a734ee6b5979d615fe6bd9f42a8fb6be3fc06733d5837c69eb74615bd1fd0b3b`). The
unchanged preparation, summary, result tree, manifest and attachment bind the
passed test to the owned arm64 iPhone 18 Pro and guest tuple
`27.2 / 24B8117 / iPhone19,2`. A local verifier repair accepts only the observed
`merian-simulator-identity_0_<uppercase canonical UUID>.json` shape in addition
to the literal names; all case, device, configuration, source, run, count,
payload, size and path checks remain. Local reverification observes identity but
retains `qualified: false` and `release_eligible: false`. The original hosted
failure is not relabeled as a passing run. Earlier setup/query and
twenty-five-minute compile failures remain retained.

The unpublished full-coverage candidate pins that observed tuple and adds it
only to the Debug measured-receiver eligibility guard, preserving the old tuple,
test/session/scope/receiver predicates and session invalidation acknowledgement.
Production transport behavior and native resource assertions are unchanged.
Every builder and shard must independently pass its own identity probe. Before
publishing shard products, the builder must requalify all compiled transport,
Capture allocation and Foundation parser methods from a freshly unpacked copy of
the same digest-bound archive. The protected parameterized methods require
exactly two, seven and three argument cases. Full inventory reconciliation
requires all seven Foundation methods and every compiled unit method exactly
once across at most sixteen serial whole-suite shards, with zero failures or
skips. The aggregate independently verifies the focused receipt and unchanged
critical-result checks; focused success never replaces complete coverage.

Only the unit builder (310 minutes) and shards (350 minutes) exceed the common
120-minute workflow-security cap. Compilation is bounded at sixty minutes,
focused native tests at 120 minutes and each shard at 240 minutes. The previous
Capture suite alone took 4,429 seconds; a thirty-minute focus would be too
short. No production job limit changes. A complete local tooling run also
exposed a random temporary-directory suffix incompatible with the recovery
fixture's ownership guard. The test now creates a valid fixed child under a
private random parent and explicitly proves an underscore name is rejected
before container inspection; the runtime guard and SQL are unchanged.

Fresh hosted product transfer, focused resource/parser qualification, complete
unit coverage, UI/archive and all other exact-SHA packet prerequisites remain
required. The simulator support report stays local. No PR closure, main update,
Supabase deployment or Naturebook production promotion is authorized by these
local observations alone.

## Hosted flat-inventory framing repair

Diagnostic `9ddba5fb5b3d7a9bfa3f6525931fcd552e2225ea`, native run 43688035667
attempt 1, passed compilation and the exact in-process simulator identity check.
All six critical UI tests and the unsigned Release archive validation passed.
Their retained artifact digests and source bindings were independently checked.
Full unit validation failed before focused execution: the planner treated
Xcode's `Plan Merian` header as a method identifier. The subsequent missing
focused artifact and aggregate failures are consequences; the original run
remains failed.

Build artifact 14152501591 was independently verified against SHA-256
`49f091fd48bec0321439b01f3bb8c3306b366a966390a6682991823258278c12`. Its raw
enumeration digest is
`8644e88fe687f67417bc7934b97f302a77b33e4572c3dade4f0e9da1433bcb41`. The 7,320
lines comprise the exact plan header, 7,317 executable method selectors across
988 suites, and two bare XCTest lifecycle-support classes:
`ConsentManagerTestCase` and `OfflineQueueTestCase`. Every selector has one
leading tab. Source inspection confirms both classes declare setup/teardown or
helpers and no test methods. All seven required Foundation methods and 24
focused requalification methods are present.

The parser repair recognizes this exact framing, requires and separately binds
the two support-only entries in a version-2 plan, and preserves every executable
method. Unknown bare selectors, duplicate entries, malformed indentation,
unexpected plans, methods under a declared empty base, and support entries in a
selected shard/focused inventory fail closed. The plan binds the raw full
enumeration digest, which focused and aggregate verification recheck. Replaying
the retained hosted inventory produces sixteen disjoint whole-suite partitions
covering all 7,317 methods; it does not execute native tests. No skip selector,
test assertion, native source, runtime identity, timeout or workflow budget is
changed. Fresh hosted product transfer, focused resource requalification and
complete shard/result reconciliation remain mandatory. PR152 and main stay
frozen, PR150 and History remain separate, and the support report stays local.

## Hosted selected-inventory reconciliation repair

Diagnostic `d66f43114ab61a73d79cfef6e997b4d8cfb5ab87`, run 43691877910 attempt
1, passed full inventory planning, portable product unpacking and the focused
native test command. All 24 focused methods and 47 parameter leaves passed on
the exact observed iOS 27 runtime with zero failures or skips. The unchanged
result-tree validator independently accepts those raw results, including the
protected two-, seven- and three-case methods. Current-source UI, Release
archive, web/admin, Markdown and deterministic agent checks also passed.
Optional live agent evaluation produced no evidence because its credential was
unavailable.

The hosted gate remains failed: selected enumeration contains the complete
target, not only enabled selectors. Xcode annotates every unselected entry with
the terminal `(disabled)` suffix. The original selected-inventory parser
rejected this format before checking the passed result tree. Verified artifact
14155023782 has SHA-256
`c744cf8130b37c9b7d2134bcec10dc16a4f8ad22a80a4122e4f41310c3e4ad92`. Its 24
enabled selectors exactly match the planned focused suites, while 7,295 disabled
selectors comprise the other 7,293 executable methods and both support-only
bases. This supersedes the previous assumption that selected enumeration omits
those bases and unselected methods.

The repaired verifier binds selection state across the complete immutable
inventory. Every method and both support bases must appear exactly once; the
enabled set must equal the assigned focus or shard methods, and its exact
complement must carry the observed disabled marker. Unknown or missing
selectors, mixed/duplicate states, disabled assigned methods, unexpected enabled
methods and malformed markers fail closed. Full-target enumeration continues to
reject every disabled marker. This accounts for Xcode's selection metadata;
native results still require zero skipped tests, and the aggregate still
requires every compiled method exactly once. No native source, assertions,
parameter matrices, result-tree checks, runtime pins or budgets change.

Focused enumeration now undergoes the same bound reconciliation immediately
after enumeration, before the 120-minute test step, and again after execution.
Local replay of the unchanged hosted artifact passes the corrected verifier;
that replay neither relabels the failed hosted workflow nor proves the unrun
shards. Fresh exact-SHA hosted qualification, complete matrix execution and all
release prerequisites remain required. PR152/main stay frozen and PR150, History
and the local-only support report remain separate.

## Full-suite observation fixture repair

Diagnostic `83e2de4e065d4e4921ec87d367e1996186da9bc6`, native run 43699310762
attempt 1, passed the focused requalification and its evidence verifier.
Independent artifact readback reconciled all 24 methods and 47 parameter leaves,
including the protected argument matrices. All 7,317 compiled methods remain
assigned across sixteen whole-suite shards. Fresh runners passed product
transfer, simulator identity and selection reconciliation before executing their
assigned suites. Current-source backend, critical UI, unsigned Release archive
and package quality gates also passed.

Full-suite execution exposed a stale fixture in
`boundedAttemptsKeepStatusAndReleaseOnlyVerifiedApplications`: its status reader
returned legacy `{"status":"found"}`. The existing observation-only reader
requires the exact `observe-v1` envelope and correctly rejected that response
with `MerianError.invalidResponse`. Independent source review confirmed the
decoder path and the existing malformed-response regression that rejects this
legacy shape.

The test now uses `ScanObservationTestFixture.response`, binding the response to
the requested account and scan with `rowExists: true`. It retains the complete
capacity loop, read-only status assertions, exact replay and retained-attempt
release checks. No production code, decoder rule, timing limit or assertion
changes. The original failure remains retained; a complete passing native run
and all exact-SHA release prerequisites are still required. PR152/main remain
frozen and PR150 and active History work stay separate.

Shard 2 completed with 305 passed methods, one failure and zero skips. The
unchanged `receivingRequiresTheSealedCoordinatorGrant` assertion found that
`withReceivingLocks` had become module-visible to serve the separate preview
extension. Independent review confirmed that the generic callback should remain
private to its grant-minting file. The repair restores `private` and moves only
the unchanged owner-facing preview method into that file. Preview values and
read access remain in `SharedMediaNativeOriginalPreview.swift`. Three blank
separators between adjacent receiving methods are removed to keep the owner file
within its existing 600-line limit. The capability-boundary test, grant
construction/validation and both success/error release paths are unchanged. This
is a production access-control repair in addition to the test fixture
correction; fresh native compilation and complete validation remain required
before integration.

## Opaque parameter identity repair

In the same diagnostic run, shard 1 passed all 110 native methods with zero
failures or skips, then failed result reconciliation. Its retained tree contains
76 unique parent-bound argument leaves. Two passing cases of
`MediaPreparationActorTests.prepareStillImageReturnsOnlyBoundedPayloads(_:)`
identify `.jpeg` and `.preferred` using short hexadecimal values rather than
64-character identities. The parser's fixed-length assumption rejected them.

The verifier now accepts one nonempty even-length lowercase hexadecimal `args`
value, bounded to 4,096 characters, with exact raw parent URL binding and global
identity uniqueness. Malformed values, extra query keys, fragments, encoded
aliases and control characters fail. Native success, zero skips, complete method
coverage and protected 2/7/3 argument matrices remain required. No compiled test
inputs, native assertions, workflow budgets or simulator identities change.
Retained-artifact replay is local diagnostic evidence only; it cannot relabel
the failed hosted run or clear a release gate. Fresh complete validation remains
required, with PR152/main frozen and PR150 and History separate.

## Video fixture and host-wait repair

Shard 4 of diagnostic run 43699310762 completed 450 methods: 447 passed, three
failed, zero skipped. Two `CaptureVideoReanalysisHostTests` real-media methods
exceeded their one-minute limits. The retained log shows codec/AAC work but does
not establish which preparation or settlement phase stalled. In
`ObservationVideoReservationDeliveryTests.oneSavedAttemptSettlesOnlyKnownCurrentAnswers`,
the conflict and unknown arguments failed while constructing their fixture,
before creating the reservation service: the legacy video writer remained
writing with no error but was not ready at frame 8 within five seconds.

The shared fixture now uses Apple's async pixel-buffer receiver on iOS 26 and
later, with the legacy adaptor retained for older deployment targets. Every
append retains the five-second deadline; timeout/cancellation stops the writer
and waits for actual append exit plus deadline/cancellation task completion
before releasing fixture encoder ownership. A successful append arriving after
the deadline still fails. Controlled lifecycle regressions cover success, append
failure, timeout, caller cancellation and a delayed-deadline race. All existing
fixture media assertions and host handoff/reopen/drain assertions remain. The
host test waiter uses cancellation-aware short sleeps and cancels/joins host
work before propagating cancellation to fixture teardown. Its one-minute limit
and all workflow budgets are unchanged. Phase-only diagnostics separate future
fixture admission, silent writing, AAC/export and host settlement observations.

This is a test-harness repair candidate, not a proven runtime fix. The original
failed evidence remains retained. Fresh compilation, complete native execution
and all exact-SHA prerequisites remain mandatory; PR152/main stay frozen and
PR150, History and the local support report remain separate.

## Review RPC error-expectation repair

Shard 7 completed 493 methods: 492 passed, one failed, zero skipped. The false
argument of `missingGatewayRouteReturnsWithoutRedispatch` expected an Edge
missing-function error from the Reject/Undo database RPC. Confirmation's Edge
case passed. Independent source and history review established that the test
expectation predates the documented transport boundary: only `/functions/v1/`
URLs receive Edge missing-function classification, while PostgREST RPCs preserve
their own HTTP error semantics even with shared gateway headers.

The test retains both parameter rows, the same synthetic gateway response and
the exact one-dispatch assertion. Confirmation still requires
`edgeFunctionUnavailable`; Reject/Undo now requires the exact HTTP 404 and body.
No production error classifier, retry behavior, API payload, SQL or permission
changes. The sibling recovery regression already pins database RPC 404 handling.
Fresh complete hosted validation remains required.

## Saved allocation cancellation readiness repair

Shard 8 of diagnostic run 43699310762 completed 587 methods: 586 passed, one
failed, zero skipped. Both rows of
`NativeAllocationStatusRecoveryTests.cancellationRetainsOwnerUntilSenderReturns`
expired their four-second pre-sender watchdog with neither sender entry nor
operation return. Whole-row durations were 79.88 and 92.99 seconds, including
durable fixture construction. The adjacent passing audit measured sender entry
after 5.98 seconds; this is a test readiness conflict, not evidence that the
cancellation ownership assertions failed.

The repair waits for an explicit event emitted only after the sender's check and
settle validators. Early operation exit closes the stream; test cancellation
unwinds the wait into the existing sender release, operation cancel/join and
owner drain. Both parameter rows, the held-owner assertion, rejection of late
success and unchanged saved-row check remain. A three-minute method limit bounds
whole-fixture execution and cleanup without changing production or workflow
budgets. Three focused event cases cover admission, early failure and
cancellation. Independent review accepted the event design and the limit based
on the observed whole-row durations. Hosted proof remains pending.

## Literal native and SQL coverage prerequisite

Shard 9 completed 577 methods: 576 passed, zero failed, one skipped. The skipped
method is
`SharedMediaNativeLiteralRecoveryTests.nativeCandidateAndSQLRepliesRemainLiteralThroughDurableRecovery`.
Its existing opt-in condition requires a fresh owned disposable Supabase replay
and one-shot loopback bridge. The ordinary shard did not arm that integration.
The zero-skip verifier correctly rejected the result; no passing receipt or
coverage exception was created.

The canonical runtime guide already requires a dedicated armed execution with
source, product, native candidate and public-wire identity reconciliation. No
checked-in hosted job currently supplies that bridge. GitHub-hosted ARM macOS
does not support the nested virtualization needed by the usual Docker setup; the
existing bridge requires a local Unix Docker engine. Independent review
identified an isolated Mac with the pinned toolchain, simulator, Docker and
matching compiled-product workspace as a missing prerequisite. Any dedicated
lane must retain this selector in the immutable full inventory, execute it with
zero skips, and reconcile its exact source/run/attempt/product-bound receipt
with the other shards. That lane is not implemented or qualified here. No
unarmed skip, historical result or separately unbound build can clear coverage.

PR152/main remain frozen. PR150, active History resources and the local support
report stay separate; no merge or deployment has occurred.

## Fresh PUT signed-expiry fixture repair

Shard 10 completed 614 methods: 612 passed, two failed, zero skipped. The video
status paging case failed in the same legacy video fixture before exceeding its
one-minute limit; the shared modern-receiver repair remains awaiting hosted
proof. The new failure was the timeout row of
`NativePhotoUploadLifetimeTests.freshPutTerminationRetainsLeaseAndLocks`. Upload
construction was reached 7.33 seconds after ticket issuance, but its synthetic
ten-second signed window expired before URLSession task creation. Sibling
cancel/account rows reached actual start after 14.21 and 15.45 seconds.

The timeout fixture now receives a delayed ticket with 60 seconds remaining,
keeping the exact original receipt and capability-expiry formula. It still
requires real task creation/start, no explicit cancellation, held ownership and
coordinator exclusion through paused completion, and unchanged persisted state.
The timeout outcome is strengthened from any error to exactly
`URLError.timedOut`. A three-minute method limit bounds fixture setup and drain.
No production deadline, immutable allocation TTL, clock, workflow budget or
decoder assertion changes. Independent review favored this fixture-only repair
over a new production clock or timeout seam. Fresh native validation is still
required; this source change does not qualify the failed original run.

## November 15 — reviewed historical evidence and integration scope

The user requested review of changes since the November 9 test, reuse of
applicable evidence, and only necessary reruns. No new Mac toolchain, simulator,
Docker database or hosted beta mutation is needed for this review.

The retained `completion286-join02` execution finished successfully on November
9: one native method/case, zero failures/skips, 116 SQL checks and 12 fixture
assertions. Candidate and four public-wire digests matched, the owned native and
bridge children exited, and disposable database cleanup passed. The retained
`completion286-runtime-review02.json` independently accepted that bounded
literal SQL/native recovery join. It did not qualify live Auth/provider/R2,
process death, phone behavior, full app acceptance or distribution. The native
log used SDK 27.2; the actual test device was arm64 iOS 26.5 build `23F77`.
These are historical observations, not the current hosted runtime identity.

The integration test itself, native packet validator, runtime journey and
request-journey runner are byte-identical to that receipt. This does not prove
all dependencies unchanged. The historical record had 516 migrations; the
candidate has 522, with six additions and none removed. Eleven inputs in the
862-file SQL record differ, including the bridge and fixture support. The wider
retained manifests include unrelated source, tests, documentation and assets;
changed-file totals do not by themselves establish a new integration failure.

Independent backend review found those eleven inputs unchanged between
`83e2de4e065d4e4921ec87d367e1996186da9bc6` and
`a9970171b0917ba939dca7dad869f10631728f9f`. Their entire `services/supabase`
trees are identical. Candidate Validation run `43699312606` already passed all
three jobs and 53 steps on `83e2de4`; that is supporting validation of the
unchanged backend inputs, not a newly issued whole-candidate receipt for `a997`.
Archive-read tests were relocated into their executable integration runner, not
removed. Storage changes use normal backend coverage; the literal fixture's
fixed local storage responses never qualified live R2. No additional backend
runtime run is warranted solely for this delta review. The packet's final
publication/deployment checks remain separate prerequisites.

The earlier proposal in “Literal native and SQL coverage prerequisite” treated
one same-product joined integration run as mandatory for this consolidation.
That proposal is superseded by the scoped classification below. The original
approval packet preserves unfinished native work and explicitly does not qualify
an app release. Historical integration evidence remains historical; any affected
feature activation or current integration claim needs its own app-workstream
evidence and review. PR150 and active History remain separate.

The schema-3 compiled plan preserves the exact opt-in integration method and its
whole suite in `separate_integrations`. Every other compiled method belongs to
exactly one hosted shard. Missing integration, additional methods in that suite,
changed classification, overlapping assignment, omitted ordinary tests,
failed/skipped results and stale artifacts fail validation. **Hosted iOS unit
tests** reports only ordinary-suite coverage. Its receipt explicitly records
`complete_target=false`, `release_eligible=false`, the full compiled count and
integration `status=not-executed`. The workflow never converts the unarmed skip
or November 9 pass into current integration success. Runtime assertions, test
bodies, SQL, toolchain pins, hosted identity checks, UI smokes and archive
checks are unchanged by this classification repair.

Original shard 11 also completed 621 methods with zero failures/skips. Its
original verifier rejected opaque parameter identities; the already-reviewed
parser repair reconciled all 621 methods and 624 parameter leaves in a local
diagnostic replay. Original hosted failure remains retained. The remaining
original shards and hosted validation of the repair remain pending; no merge,
deployment, activation or app-distribution clearance is claimed.

Independent native review also found real changes in the historical execution
closure: submission session, allocation access, completion documents,
authenticated transport, receiving owner and test helpers differ from November
9. Manifest hashes identify those differences; they do not establish behavioral
equivalence. More recent hosted ordinary evidence already covers the recovery
model and received-status transport (shard 11) and completion documents (shard
4). Relative to `83e2de4`, the later receiving-owner repair restores the private
lock boundary and relocates byte-identical preview code; the literal test's
admission recovery, completion recovery and history acknowledgement bodies are
unchanged. Normal current-source validation must still cover the repaired
bounded-status fixture, private-lock boundary and other reviewed fixture fixes.
It does not need to arm the database bridge for this backend/web packet.

Reachability is deliberately not summarized as “all recovery is disabled.” The
ordinary submission dependency factory does not wire the fresh native photo
submission/allocation factory exercised by the first half of this integration.
Recovery has conditional Release wiring through
`PreparedHistoryReanalysisComposition.isAppInstallationQualified`. Remaining
native acceptance therefore stays with the app workstream; the consolidation
neither installs an app nor establishes current app-release qualification.

An offline preview of the historical compiled inventory preserves all 7,317
methods: 7,316 ordinary methods in sixteen whole-suite shards and the one
explicitly retained integration method. This previews classification only and is
not runtime evidence. The first full portable gate reached the workflow contract
and rejected its stale full-target summary wording. That assertion was updated
to require the truthful scoped summary; the failure log remains retained.
