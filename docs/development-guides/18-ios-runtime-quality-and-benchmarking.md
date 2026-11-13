## Initial photo result and History verification

The existing `-seedInitialMediaHistory` Debug fixture now accepts a staged photo
with and without optional text. Completion295 native01 passed all six initial
photo/audio/video optional-text UI methods: ordinary submission, queue
extraction, completion, the actual result sheet, explicit History enrollment and
retained-store reopening after clean process relaunch. Engine independently
verified the XCResult and all 4,253 unchanged inputs. The overall run remains
red: eleven methods passed, one older recovery fixture violated the unchanged
enrollment-owner architecture guard (HQ-321), and two video QoS warnings remain.
Its scoped correction uses the existing retained enrollment owner, stable
synthetic generation and current validator, without weakening the architecture
rule. Native02 passed all six owning architecture checks and both native-photo
recovery UI tests: eight passed, zero failed/skipped/warnings, 4,253 unchanged
inputs. Engine independently verified the source fix and result; HQ-321 is
closed. The positive native recovery test verifies explicit Add History and an
exact result-route request, not actual Insight rendering. Native01 separately
provides the six ordinary-media actual result/History/relaunch passes. Its
failed aggregate and video warnings remain retained; source-specific evidence is
not flattened into a single wholly passing run.

Photo input is a pair of distinct bounded synthetic inference/display JPEGs, not
camera or codec qualification. Inference-file bytes are checked before
completion; reopening checks retained display bytes and the immutable witness/
proof, not a fresh inference-file read. The shared synthetic result still uses
the existing “Synthetic Audio” label, not photo-specific provider evidence. No
live account, funding, upload, provider, native reserved dispatch, abrupt crash,
resource, phone or cumulative acceptance is inferred. Backend CI524 and the
separate unpublished beta release candidate stay frozen.

The earlier Auth architecture allowance was explicitly approved and applied:
completion293 passed all fourteen architecture methods with independent
verification. HQ-319 is closed for that exact SHA-pinned Debug-only allowance;
the caps are unchanged and earlier failed evidence is retained.

## Initial audio/video completion UI candidate

The Debug-only `-seedInitialMediaHistory` fixture exercises ordinary initial
audio and video, each with and without optional text, through the existing
submission, terminal completion and explicit History enrollment owners. It
retains one private disposable store across clean process relaunch.
Queue-adopted media and exact submitted text/order are frozen before completion;
video original clip, prepared playback, inference frames and extracted audio
remain distinct.

The real terminal owner must preserve its original account/generation proof,
publish exactly once and release its account lease before the fixture is ready.
The actual Insight sheet opens from the captured queue context after its queue
row retires. Explicit enrollment uses a synthetic V3 imported baseline derived
from the immutable completion proof; original provider/media evidence remains
unavailable in that History baseline. Relaunch opens the persisted result and
History without resubmission or reenrollment. The four UI selectors are in
`InitialMediaHistoryUITests`. Native29205 passes all four audio/video
optional-text journeys and all fourteen lifecycle-provider tests. Engine
directly verified the XCResult and 4,253 unchanged inputs. The batch remains
red: 30 methods passed, two architecture checks failed, zero skipped, two
structured QoS warnings. Seventeen coordinator methods passed in the interrupted
prior run and remain separate reused evidence.

Earlier failures are retained: the result-title oracle (HQ-315), controlled weak
AVAsset lifetime reproduction/correction (HQ-316), synthetic funding state lost
during initial Auth cleanup (HQ-317), and a cancelled-stream test-helper hang
(HQ-318). The corrected Debug join observes actual initial handler exit before
one-time synthetic setup and rejects superseded work. All four scoped fixes are
independently verified. The interrupted run is not a green batch or evidence of
a production deadlock. The exact transport inventory correction (HQ-320) passed
its single-method native29207 check with independent verification; the Auth
aggregate budget (HQ-319) was open at that historical checkpoint. Completion293
supersedes that status: the owner approved the exact two-source, SHA-pinned
66-line Debug allowance; all14 architecture methods passed and Engine verified
the result. Physical/adjusted counts and unchanged caps remain recorded; prior
failed evidence is retained.

The synthetic account, entitlement override, running-state transition and server
response do not qualify live Auth, paid dispatch/server admission, upload,
uncertain legacy recovery, abrupt crash, resource bounds, phone installation or
cumulative acceptance. Existing reanalysis review/Undo evidence remains
separate. Shared test seams are restored; fixture-owned retained media and
evidence remain available after the run. Production installation/activation
holds are unchanged.

## Successful persisted reanalysis UI candidate

The additional Debug-only `-seedReanalysisRecoverySuccess` mode supplies an
independent durable synthetic-server ledger to the existing reanalysis restart
fixture. It is unavailable without the existing explicit fixture opt-in. The
three new selectors exhaust the real persisted 30-second checking allowance,
close, make only the synthetic original result available, relaunch, then request
one explicit exact recovery. No new provider dispatch is permitted.

Photo and video use their current completion stores. Audio uses the existing
recovery-only claim/service owner and joins its actual exit; read, upload,
authorize and analyze boundaries fail if invoked. The canonical result binds the
original saved request. Existing History session, selection and review owners
write application records; the separate server ledger validates exact request
identity, revisions and operation replay before returning receipts.

The candidate checks three preserved immutable versions, explicit selection,
rejection/review Undo, a fresh selection Undo, and terminal process relaunch.
After completion, the original fingerprint is retained as a witness; separate
checks verify actual terminal records, selection, review receipts and unchanged
submitted media. Real pending erasure receipts are required, but cleanup is
intent-only: this fixture does not delete media or qualify filesystem cleanup.
Terminal charge is the independent exhausted-budget witness, not a live sidecar
after completion. Native29101 compiled and passed three architecture checks; all
three UI cases failed on an incorrect acknowledgement-message oracle after
review revision invalidation. The source-reviewed test correction requires the
actual stale preview message, explicit Refresh and receipt-backed child
authority/Undo. Corrected native29102 passed all three media UI cases with zero
failures/skips, 4,248 unchanged inputs and independent fix/runtime verification.
Three unchanged architecture01 passes remain applicable: six distinct methods
across the runs. Both01 and02 have a structured QoS priority-inversion warning;
retain both and the original failures. Full iOS tooling01 passed with unchanged
tooling inputs. This qualifies the bounded rendered journey described here.
Synthetic Auth/results, clean restart and local persisted UI do not establish
hosted/phone, abrupt-crash, resource or cumulative functional acceptance.

## Persisted reanalysis checking qualification

`ReanalysisRecoveryRestartUITests` adds separate photo/audio/video selectors for
the existing RUX1/2/6 requirement. Each uses its own persistent disposable
store, real preparation/execution/presentation owners and existing saved-request
sheet. Authentication and exact-outcome replies are synthetic. Close releases
the controlled reader and awaits actual checking-model exit before diagnostics
and process relaunch; this is clean restart evidence, not an abrupt in-flight
crash.

The candidate checks exact child, request digest, selection and media/metadata
fingerprint, zero automatic checking or forbidden execution/authorization,
unchanged settled charge on reopen, the production visible-time threshold, and
persisted exhaustion on a further relaunch. It neither changes clocks/limits nor
repeats saved-preview/Undo suites. Native29001 compiled and passed video plus
three architecture methods. Audio setup and photo action-isolation failures are
retained. Corrected native29002 passed audio/photo and three architecture
methods with zero failures/skips; Engine independently verified both fixes. The
unchanged video01 pass remains applicable, and its QoS warning is retained. The
reciprocal photo action assertions cover the observed button-routing regression.
Whole RUX, accessibility, resources and installed/hosted acceptance remain open.

## Positive recovery-to-History UI qualification

The additional `NativePhotoRecoveryUITests` selector connects actual recovery
sheet controls to existing native completion and enrollment owners in an
isolated Debug fixture. Shared canonical resources supply synthetic server
replies. Native28902 passed one method/case with zero failures/skips, 4,242
unchanged pins and independent verification: explicit Add creates one
enrollment, then Open requests the exact route without changing selection or
prepared bytes. Existing owner postconditions separately preserve the receiving
row. Wrapper 187.757s/UI134.605s are run durations, not responsiveness
acceptance.

The corrected same-button exists/enabled predicate respects asynchronous status
settlement. Failed01's immediate enabled assertion remains retained; its precise
runtime cause was not instrumented. The unchanged observe-only restart and three
architecture passes from01 remain applicable, giving five-method coverage across
runs. Full iOS CI tooling01 passed. This does not establish ordinary
result-screen navigation, server/phone integration, positive process death or
resource acceptance.

## Native photo recovery restart methodology

The registered `NativePhotoRecoveryUITests` selector uses a unique persistent
native fixture, actual acquisition/preparation/receiving owners and the existing
recovery sheet/model/status-budget owner. Only its account and observation
sender are synthetic. The first check is paused, subsequent checking is
explicit, and close/reopen plus a new app process must retain immutable
prepared/received record bytes and the spent checking budget without an
automatic read or result import. The normal app bootstrap and qualification gate
are unchanged. Native28703 passed this selector and three architecture methods
with zero failures/skips, all 4,241 source pins unchanged and independent
review. The UI method took 119.369 seconds; the full build/test wrapper took
383.272 seconds. These are observed run durations, not responsiveness
acceptance. Compilation01 and startup02 failures remain retained. Moving the
construction fence into a synchronous helper resolved the observed startup
blocker; the original generic error did not prove the precise failing stage.
Process relaunch follows an awaited clean close, not an abrupt in-flight crash.
Zero automatic reads is verified at the asserted checkpoints. This direct sheet
fixture does not establish the primary-app navigation, live backend, Add/Open
History, physical performance or whole RUX6 journey.

## November 9 — dedicated held-queue restart methodology

The queued observation UI selector in the manifest uses a unique disposable
SQLite store mounted beneath the existing Debug fixture host. Unlike the normal
in-memory UI-test library, it persists across termination and relaunch of the
same XCUIApplication. The oracle requires a new process, an existing store,
equal persisted queue/job/media/text/funding fingerprints, no automatic reads or
retry/event/import, and rendered observation plus original-unconfirmed copy.
Invoking the synthetic send alone is insufficient.

Auth/send are synthetic and scheduler wake is inert; the real queued view,
authority reader and pure context refresh callback are used. Media references do
not qualify playback. The exact temp namespace is retained in a keepAlways
XCTest attachment for evidence and narrowly owned later cleanup after process
closure; termination alone does not delete it. The exact selector passed
native28504: one method/case, zero failures/skips, 238.507s total and 4,210
unchanged inputs. Engine verified the actual process relaunch and eight explicit
rendered checks. Zero automatic reads is asserted at the reopen/open
checkpoints, not over an unbounded background interval. Failed prior attempts
remain retained. See the
[app fixture owner](../../apps/ios/Merian/App/README.md).

## Literal native/disposable-SQL recovery qualification

`SharedMediaNativeLiteralRecoveryTests` is explicitly armed only after its owned
disposable database and one-shot loopback bridge are ready. An ordinary suite
records a skip, which does not qualify this integration. The dedicated execution
must reconcile the exact method, nonzero case count, no skips/failures, source
and app/test hashes, unchanged native candidate and public wire digests against
the SQL record. Do not add the unarmed selector to a mandatory ordinary audit or
count its skip as success.

The existing `initial_cpm_runtime_contract.py` request journey accepts the
bounded native packet via `initial_cpm_native_bridge.py`; native code consumes
only public allocation/recovery projections. Private SQL
assignment/configuration/funding remain host-side.
`initial_cpm_native_fixture_test.sh`, automatically discovered by the existing
backend tooling gate, exercises packet refusal, literal binding, absolute
deadline, disconnect, child reaping and private ready-file publication. Both
platforms require a fixed canonical temporary root and an owned private
directory. The runner must join its owned child/native processes before database
disposal; already-issued SQL remains uncertain until that owned disposal.

Completion286 join02 executed one method/case with zero failures/skips and 4,238
unchanged native inputs; independent review verified literal parity, 116 SQL
checks plus 12 fixture assertions and owned cleanup. The six roles use two
distinct synthetic byte digests. Captured SQL states replayed through native
transport prove a literal integration boundary, not concurrent live requests,
provider/Auth/R2 upload, real enrollment, process death or hardware behavior.
Build-only and ordinary skipped runs cannot substitute for the armed execution.

# iOS Runtime Quality and Benchmarking

This guide owns Merian's automated runtime-acceptance and
performance-measurement contract. It complements the repository-wide
[testing strategy](./08-testing-strategy.md): deterministic behavior remains a
required test gate, while hardware-dependent measurements remain evidence for
review until a stable runner and approved baseline justify enforcement.

## Sources of truth

The runtime audit is one system with five checked-in owners:

| Owner                                                                                      | Responsibility                                                                                               |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| [`scripts/config/ios-runtime-audit.json`](../../scripts/config/ios-runtime-audit.json)     | Exact acceptance, UI, and performance selectors; suite aliases; source owners where applicable               |
| [`scripts/local-ios-build.py`](../../scripts/local-ios-build.py)                           | Cache lock, package resolution, build-once execution, phase ordering, cancellation, and evidence directories |
| [`scripts/ios-runtime-audit.py`](../../scripts/ios-runtime-audit.py)                       | XCResult completeness validation, metric extraction, baseline validation, comparison, and reports            |
| [`project.yml`](../../project.yml)                                                         | App, unit, UI, performance, and shared test-support target membership                                        |
| [`.github/workflows/ios-runtime-audit.yml`](../../.github/workflows/ios-runtime-audit.yml) | Manually dispatched Xcode 27.0 (`27A266a`) audit and 14-day artifact retention                               |

Prose may explain the matrix, but it must not become a second selector list.
Add, rename, or remove a test in the JSON manifest and its owning test target
first, then update this guide when the methodology or ownership boundary
changes.

## Quality layers

### Deterministic acceptance

The `acceptance` phase exercises cross-owner invariants using focused existing
unit and integration suites. It is the right layer for state transitions,
durable persistence, duplicate delivery, retries, cancellation, account/session
fences, response mapping, and recovery. Missing, empty, failed, or skipped
selected suites fail the phase.

This focused set supplements the complete `merianTests` target. It is not a
smaller substitute for the required compiled iOS gate.

The selected disk-backed acceptance suite composes description admission into a
private SQLite store, synthetic result finalization, real queue retirement, and
Insight dismissal/reopening. This bypasses media encoding and network dispatch.
Its visual case additionally composes real image-file admission, base64
encoding, live request coordination with an injected provider response, real
response parsing/SQLite persistence, exact-generation queue deletion, and
Insight binding after dismissal. An independent context verifies durable
queue/job admission at dispatch. A second admission while the provider response
is suspended is rejected. Sequential replay after completion cannot repeat
provider dispatch, completion publication, hydration scheduling, notification,
or milestone scheduling; saved image bytes and the single completed record
survive reopening. These effect boundaries are counters, not remote uploads or
root navigation presentations. Its interrupted-file test checks removal of
partial destinations under the existing rejected-admission discard policy. It
also rejects a save through a read-only store and retries through a writable
store, verifying that durable queue work survives. Neither case simulates OS
process death or a save failure after copying every media modality.

The background-completion regression exercises duplicate result/error delivery
while another callback owns completion. The sign-out coordinator suite composes
the real inference write drain with injected account effects and verifies that
new writes are fenced. Full active-transfer/sign-out/Insight composition remains
a separate coverage gap. The account-lease case also composes
`AuthRuntimeState`'s real drain with sign-out coordination: releasing one lease
twice cannot release the other or allow SDK sign-out early. It does not simulate
URLSession cancellation callbacks.

The `CaptureTerminalAcceptanceTests` composition starts at a staged image in
`CaptureWorkspaceViewModel`, submits it through real durable admission, and
passes a response file through the production background terminal router. It
uses the real Auth lease state and sign-out coordinator, pauses response
decoding, and delivers duplicate success/error callbacks while finalization owns
the work. The test verifies that duplicate callbacks cannot release the lease or
advance sign-out, then checks SQLite completion, queue deletion, retained image
bytes, and Insight binding. SDK session identity, provider bytes, environment
context, and notification/milestone publication are injected. Live defaults
still use the same SDK session validation and completion effects. This closes
the local staged-capture/terminal/sign-out composition gap; physical camera
capture, real URLSession cancellation and OS process relaunch still require
separate evidence.

The same suite's
`initialAudioRetainsSubmittedBytesAndTextThroughCompletion(withText:)` covers
ordinary audio Capture with and without optional text. It compares the ordered
submitted media values and exact WAV bytes through durable queue admission,
caller-source overwrite, background result finalization and queue cleanup. The
completed record binds to Insight, and replay of the same terminal callback
cannot publish a second result. The method uses a synthetic response file and
injected publication. Native223 adds normal V3 enrollment and lost-state-read
recovery with an exact baseline association and selected preview. The joined
fresh-child selection/Undo path exposed HQ217's missing ordinary-completion
review proof. Native226-02 passes both optional-text cases after the reviewed
proof correction, including the explicit reanalysis access ticket, lost-reply
child recovery and both preserved versions. The same run retains the separate
HQ220 factory architecture failure; native226-03 independently verifies its
same-owner correction with four passing checks. Provider dispatch, installed
routing, process restart and device recording retain separate qualification.
Native222 corrected both test defers to retain unique SQLite/WAL stores through
process exit. Its original passing run's SQLite vnode errors remain recorded as
HQ216. The corrected runtime passed both methods and all three cases without
vnode diagnostics, and independent verification closed the fixture defect
locally.

### UI acceptance

The `ui` phase contains only process and presentation behavior that unit tests
cannot establish faithfully. It reuses the existing Debug UI-test seeds and
production-shaped state owners. Every listed case must appear and pass in the
XCResult; a selected suite passing while a required case is absent is a failure.

`WhatsNewUITests/testLaunchDismissalRevealsMountedWorkspace` covers the launch
announcement’s Continue, Close, and swipe dismissal over the retained Capture
workspace, saving screenshots before and after each dismissal. Its Debug-only
seed exercises the production sheet router without writing acknowledgement.

The protected-chat stale-ticket scenario uses real durable admission, proof
settlement, state synchronization and host projection with synthetic
authenticated response bytes. It checks reopening, explicit identification
refresh, sheet handoff and an empty fresh composer without automatic dispatch.
This proves the prepared native flow, not live provider/network behavior or
production rollout.

Debug fixtures must remain excluded from Release behavior. Automated tests must
not call production endpoints, real providers, personal accounts, or static
real-world coordinates.

### Performance measurements

`merianPerformanceTests` owns file-backed media, mapping, persistence, and
large-state measurements. `RuntimePerformanceTests` owns process launch,
foreground activation, and repeated Insight presentation measurements. The
performance phase is separate from acceptance so a timing sample can never stand
in for a correctness assertion.

The manifest's optional `report_metric_families` records requested metric
families whose absence must remain visible. The audit retains those expectations
and reports `UNMEASURED` when no matching metric identifier was exported for
that workload. The repeated Insight benchmark requests hitch reporting; a
missing hitch series is unverified, never zero hitches. These observations
remain report-only and do not change behavioral pass/fail results.

The maximum-original hash workload measures four complete verifications of a 32
MiB synthetic file per measurement iteration, with clock, CPU and memory
metrics. Fixture streaming and the initial byte-count/identity check happen
outside the measured interval. Each verification uses the existing locked file
owner and descriptor-scoped 64 KiB hash loop; it does not decode an image or
create an upload copy. The manifest requests memory samples explicitly. Results
remain report-only and require matching environment/workload identity; a missing
memory series is unmeasured. This does not qualify retained memory across the
whole native owner, account shutdown, URLSession or a physical device.

The measured boundaries are intentionally narrower than full Capture → queue →
inference → Insight latency. Provider time, real network throughput, physical
camera/audio/video processing, thermal throttling, OS background transfer, and
sustained device memory require separate device or Instruments evidence.

## Running the audit

A runtime execution requires a concrete available Simulator destination. The
generic Simulator destination proves compilation only.

```bash
destination="$(bash scripts/select-ios-simulator-destination.sh)"

make ios-local-build ARGS="audit \
  --destination '$destination' \
  --environment-label 'local-hardware-description'"
```

To compare against an approved matching baseline:

```bash
make ios-local-build ARGS="audit \
  --destination '$destination' \
  --environment-label 'local-hardware-description' \
  --baseline scripts/config/ios-performance-baseline.json"
```

The wrapper holds one exclusive cache lock across package resolution,
`build-for-testing`, and every `test-without-building` phase. It uses only the
checked-in package versions and fails if resolution changes `Package.resolved`.
A build failure blocks all runtime phases; a later behavioral failure remains
failed while subsequent phases may still gather diagnostic evidence. The wrapper
checks the commit, tracked-source fingerprint, Git status, and nonignored
untracked-file contents before and after every phase. A change during the audit
fails that phase and blocks the remaining phases; its artifacts are diagnostic
evidence and cannot establish a candidate baseline.

Run `make test-ios-ci-tooling` when changing the wrapper, reporter, selector
manifest, workflow, result validation, or target contract.

Manifest selectors name executable test types, not source filenames. Portable
checks require each selected suite to be declared or extended in its owner
source. For example, `CaptureWorkspaceSubmissionTests.swift` extends the
`CaptureWorkspaceViewModelRefinementTests` XCTest class; the runtime selector
must use that class name. XCResult validation still requires the selected suite
and cases to execute successfully without skips.

## Evidence contract

Each audit records the source SHA, source fingerprint, dirty-tree flag,
destination, environment identity, ordered phase status, raw metric samples, and
summary statistics. Local evidence is retained under:

```text
.artifacts/local-ios/<uuid>.xcresult
.artifacts/local-ios/audit-<uuid>/audit.json
.artifacts/local-ios/audit-<uuid>/summary.md
.artifacts/local-ios/audit-<uuid>/<phase>/*.json
```

Start triage with `summary.md`, then inspect the failing phase's XCResult. Do
not delete current diagnostic or reviewed release evidence as part of ordinary
cache cleanup. A later run is new evidence; it does not retroactively replace a
failed or incomplete run.

The manual **iOS Runtime Audit** workflow publishes the summaries and uploads
`.artifacts/local-ios` for 14 days even on failure. It has no deployment step
and does not authorize TestFlight, App Store, Supabase, or RevenueCat actions.

## Baseline policy

No numerical baseline is authoritative until repeated measurements exist on a
stable, fully described environment. An approved baseline must:

1. come from a complete successful audit,
2. use the same hardware label, Simulator model/runtime, Xcode version, host OS,
   configuration, and workload as the candidate,
3. retain at least 30 raw samples for every metric,
4. reproduce its count, mean, and sample deviation from those raw samples,
5. link to reviewed evidence and explain why the environment is stable enough.

The reporter rejects malformed or incompatible baselines. It flags high
variance, new or missing metrics, and a candidate mean increase greater than
both 20 percent and three combined standard errors. These observations are
report-only screening signals, not release failures. Never invent a baseline,
pool unlike runners, discard inconvenient samples, or lower a threshold to hide
a regression.

CV uses the absolute mean for signed measurements. A zero mean has undefined CV,
including an all-zero series: JSON stores `null`, the table says `undefined`,
and observations flag it even without a baseline. Inspect raw samples and sample
deviation; neither undefined nor near-zero signed-memory CV establishes
stability or a leak. Historical baselines with a numeric-zero CV placeholder
remain readable because comparisons recompute CV from the validated mean and
deviation. Preserve those original evidence files.

A toolchain, runtime, hardware, configuration, fixture, or measured-workload
change requires a separately reviewed baseline. Preserve the prior evidence so
the reason for rebaselining remains auditable.

The environment includes a workload fingerprint covering the selector manifest,
project manifest, benchmark sources, UI-test sources, shared test fixtures,
app-side `App/UITesting` seed producers (including embedded media), and
`Configuration/TestExecutionCoordinator.swift`. The queued-audio benchmark's WAV
is generated by its seed producer; it has no separate checked-in binary asset.
Changing these inputs rejects comparison with the previous baseline; ordinary
product-source changes, including presentation and startup wiring, remain
comparable.

## Adding coverage

Before adding a selector:

1. identify the user or system invariant and its production owner,
2. choose acceptance, UI, or performance based on what the test establishes,
3. reuse shared synthetic fixtures and existing dependency seams,
4. add the exact selector and XCResult suite alias to the manifest,
5. keep correctness assertions outside measured intervals where feasible,
6. extend tooling contract tests for new manifest or reporter behavior,
7. update this guide only when the methodology or ownership model changes.

Do not duplicate an existing suite merely to give the audit a new filename. A
test should have one source owner and may participate in more than one command.

## Device and provider boundary

Simulator evidence cannot establish camera or microphone capture fidelity,
codec/playback peak memory, thermal policy, process termination, OS background
transfer, first-install launch, actual provider latency, network throughput, or
sustained full-flow retained-memory behavior. Record those gaps explicitly and
use a physical-device matrix, Instruments trace, or authorized staging smoke as
appropriate. Never summarize an unrun device or hosted check as passed.

The audit now targets the arm64 `xcode-27` runner and requires Xcode 27.0 build
`27A266a` before simulator selection. Its executable acceptance manifest
includes the Foundation parser, local-analysis, and feature-flag suites with
their XCResult aliases. Use an iOS 27 destination: skipped parser tests fail
acceptance. The new `github-xcode-27-arm64-27A266a` environment label requires a
separately reviewed baseline; preserve earlier Xcode 26.6 measurements as
historical evidence.

The parser and injected-provider tests do not invoke Apple's model. Before
production activation, complete the
[physical-device matrix](./08-testing-strategy.md#staged-foundation-visual-cue-validation)
and
[canonical activation checklist](../system-architecture/04-ai-engineering.md#stable-toolchain-activation-checklist).
Project Guardrails includes runtime workflow, manifest, and tooling paths so
these contracts cannot change without the portable CI-tooling checks.

## Protected chat proof and refresh measurements

The performance manifest includes an app-process clock, CPU and memory workload
for durable question staging, exact no-admission proof settlement and explicit
identification refresh. Each sample launches the existing enrolled-V2 Debug
fixture, prepares the same question outside the interval, then measures Send
through proof presentation and refresh closing the stale chat. Reopening checks
an empty composer and the retained proof outside the interval. Only strict
server/state responses are synthetic; persistence, delivery, queue ownership,
state synchronization and host projection use production components.

Each test invocation requests ten XCTest measurement iterations; the audit
requests three test invocations. Inspect actual exported sample counts. Each
measurement uses a newly seeded process to keep durable occupancy and authority
identical. These are report-only measurements of that bounded flow, not
sustained heap-retention, leak, real-provider or physical-device evidence. Keep
raw XCResult samples and matching environment/workload identity; no timing or
memory threshold is inferred from one local run.

### Saved audio chooser rendering boundary

The runtime manifest includes the explicit saved-audio chooser UI smoke. It uses
the production sheet and presentation model with a Debug/UI-test-only domain
fixture. The smoke proves disabled-until-selected actions, distinct consumed
result-checking copy, unavailable feedback, refresh clearing selection and
closing the sheet. It does not call a provider, authorize work, access media,
open an account lease or mutate the database.

Persistence and exact consumed-request handoff remain native integration tests.
This rendering evidence does not substitute for durable restart, audio/device,
video, hosted runtime, erasure or storage/CDN qualification. Ordinary App
installation remains disabled; the alternatives card is unaffected.

## Initial video journey composition — November 5

`CaptureTerminalAcceptanceTests.initialVideoRetainsPreparedCohortThroughCompletionAndHistory(withText:)`
uses the real H264/AAC fixture, video preparation and visual enqueue path, then
synthetic original completion and V3 enrollment. It composes a fresh video child
through existing preparation/reservation/upload/execution owners and verifies
lost-reply outcome recovery, immutable versions, preview and current V5 action
exclusions. Shared helper extraction also reruns both existing initial-audio
cases. Native227-02 passed both cases after the retained HQ221 fixture
corrections, with independent outcome verification. This remains local
synthetic-boundary evidence. The existing suite entry in
`ios-runtime-audit.json` includes it.

`ObservationReanalysisLocalVideoInputTests` and `FileIOActorTests` now join the
same acceptance manifest. Completion228 verified the new input's copy fences,
exact cohort retry and preparation recovery in27selected cases, with separate
unchanged35case FileIO evidence. Original compiler/deadlock failures are
retained alongside the independent fix verification. Completion229 passed two
methods and seven cases, extending the initial-video selector to choose the
completed parent's actual current local attachment through this input boundary.
This proves no historical-original authority or installed UI route.

Native230's full target run retained five failing methods and seven iOS 27-only
skips. Completion231 corrected the account fixtures, historical-load delegation
assertion, centralized runtime detection and temporary SQLite cleanup. Its
focused run passed 171 methods / 282 cases with no failures, skips or
vnode-unlinked diagnostics, and Engine independently verified the corrections.
The seven Foundation mapping methods separately passed on iOS 27. The unsigned
Release compile succeeded, but concurrent icon changes invalidated its exact
input match; retain that result as compilation evidence only. The
whole-candidate qualification remains open, including a stable-candidate Release
gate. Exact logs, input manifests, results and findings are recorded under
`.artifacts/native-app-capture-handoff-20261020/completion231-*` and the single
`.artifacts/identification-history-findings.json` register.
