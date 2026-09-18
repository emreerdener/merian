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

### UI acceptance

The `ui` phase contains only process and presentation behavior that unit tests
cannot establish faithfully. It reuses the existing Debug UI-test seeds and
production-shaped state owners. Every listed case must appear and pass in the
XCResult; a selected suite passing while a required case is absent is a failure.

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
