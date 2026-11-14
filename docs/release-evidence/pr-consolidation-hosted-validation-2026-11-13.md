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

Fresh read-only inspection 43565069349 still reports 520 beta migrations. The
candidate contains 522, with only the two approved retimed migrations pending;
both obsolete versions are absent and the planner returns `normal`. The
deployment-baseline resolver still identifies `c435ea8`, and the function plan
remains exactly 125 functions. No main, beta or production-domain change has
occurred. PR 150 and History's active checkout remain separate.
