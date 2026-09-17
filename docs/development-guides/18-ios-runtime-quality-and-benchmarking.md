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
| [`.github/workflows/ios-runtime-audit.yml`](../../.github/workflows/ios-runtime-audit.yml) | Manually dispatched Xcode 26.6 audit and 14-day artifact retention                                           |

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
failed while subsequent phases may still gather diagnostic evidence.

Run `make test-ios-ci-tooling` when changing the wrapper, reporter, selector
manifest, workflow, result validation, or target contract.

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

A toolchain, runtime, hardware, configuration, fixture, or measured-workload
change requires a separately reviewed baseline. Preserve the prior evidence so
the reason for rebaselining remains auditable.

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
