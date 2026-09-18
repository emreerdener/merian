# iOS runtime acceptance and performance audit report

The audit infrastructure and regression coverage are implemented. Runtime
acceptance and performance results remain **unverified**: this sandbox denies
the process inspection required by the local build wrapper, and
CoreSimulatorService is unavailable. No numerical baseline, variance, runtime
pass, or production performance improvement is claimed.

## Findings and fixes

- Replaced the unconditionally skipped, Photos-dependent background UI case with
  a seeded queued-audio interruption/dismissal/reopening case. It waits for
  application state instead of sleeping or reading the simulator photo library.
- Added four behavioral cases: stale/duplicate finalization after disk-store
  reopening with Insight restoration; malformed response retaining durable work;
  repeated live execution unable to dispatch/publish twice; cancellation during
  suspended persistence suppressing late presentation effects.
- No production bug was established by executable evidence, and this audit makes
  no production behavior fix. Unrelated production-source changes appeared
  concurrently and were preserved.
- Reused the canonical PCM WAV fixture across unit and benchmark bundles via
  `apps/ios/TestSupport`; no fixture was added to the app target.
  Project/source-membership checks caught and resolved an intermediate XcodeGen
  grouping conflict.

## Durable system

`make ios-local-build ARGS='audit --destination "platform=iOS Simulator,id=UDID" --environment-label "hardware-runtime"'`
runs the existing cache/storage wrapper. It retains one cache lock across pinned
package resolution, one generic Simulator build, acceptance, UI acceptance, and
separate benchmark execution. It retains XCResults and structured summaries
outside `.build` and refuses to test stale products after a failed build.

The selector manifest reuses the existing capture, queue, inference, Insight,
startup/recovery, V50/V51 migration, onboarding, Explore, authentication,
resource-budget and lifecycle owners. The four new unit cases are required by
the existing critical-result validator. The main CI build now compiles the
benchmark target; the manually dispatched **iOS Runtime Audit** workflow
collects measurements separately and retains evidence for 14 days.

Nine report-only benchmarks cover:

1. Durable queue/job SQLite commit.
2. Scalar hydration of 1,000 library records.
3. Projection of 1,000 offline queue rows.
4. Twenty bounded ImageIO decodes per sample.
5. One hundred audio/video/image file-admission checks per sample.
6. One hundred synthetic inference-response decodes/domain mappings per sample.
7. Process-cold launch until responsive.
8. Warm foreground return.
9. Repeated seeded audio Insight presentation/hydration.

Metrics include XCTest clock, CPU, memory, launch and iOS 26+ hitches as
appropriate. Each benchmark requests ten samples in each of three test
iterations. The reporter retains raw samples, sample count, mean, median,
standard deviation, coefficient of variation, minimum and maximum. It compares
only matching hardware/model/runtime/toolchain/configuration identities, with
simulator UDID recorded separately. Dirty state and source fingerprint remain
visible.

There is **no measured baseline yet**. The baseline creation/update procedure is
in the canonical testing strategy. A reviewed successful audit with at least 30
raw samples per metric can be saved as
`scripts/config/ios-performance-baseline.json`. The CI workflow consumes that
file when it exists. It does not fabricate a placeholder baseline.

Behavioral correctness and deterministic resource bounds are CI-gated.
Hardware-dependent timings/CPU/memory remain report-only. An increase greater
than both 20% and three combined standard errors is marked for review, not used
as a release threshold. High variance and missing metrics remain visible.
Invalid/missing execution evidence fails the audit.

## Verification

Passed:

- `make xcodegen` — authoritative manifest regeneration; generated diff
  reviewed.
- `make validate-ios-project`.
- `bash scripts/test-ios-project-source-membership.sh`.
- `bash scripts/check-ios-project-source-membership.sh` — 1,355 app, 672
  unit-test, 3 benchmark and 3 UI-test sources; shared fixtures absent from
  production membership.
- `python3 -B scripts/test-ios-runtime-audit.py` — 12 portable tests.
- `python3 -B scripts/test-local-ios-build.py` — 20 portable tests.
- `make test-ios-ci-tooling` — complete tooling gate, including exact-case
  omission/skip protection. An intermediate expected-case-count failure was
  corrected from 99 to 103 to account for the four newly protected cases.
- Strict SwiftLint on all six changed/new test Swift files (zero violations);
  shared WAV source was relocated without content changes.
- `deno fmt apps/ios/README.md docs/development-guides/08-testing-strategy.md`.
- `make validate-markdown-format`.
- `git diff --check`.
- Python source compilation without writing bytecode; Ruby YAML parsing of the
  workflow and project manifest.

Exact affected-Swift lint invocation:

```bash
SCRIPT_INPUT_FILE_COUNT=6 \
SCRIPT_INPUT_FILE_0=apps/ios/MerianPerformanceTests/PersistencePerformanceTests.swift \
SCRIPT_INPUT_FILE_1=apps/ios/MerianPerformanceTests/MediaPerformanceTests.swift \
SCRIPT_INPUT_FILE_2=apps/ios/MerianUITests/RuntimePerformanceTests.swift \
SCRIPT_INPUT_FILE_3=apps/ios/MerianUITests/merianUITests.swift \
SCRIPT_INPUT_FILE_4=apps/ios/MerianTests/Core/Data/OfflineSync/DiskBackedInferenceAcceptanceTests.swift \
SCRIPT_INPUT_FILE_5=apps/ios/MerianTests/Core/AI/Inference/InferenceLivePipelineDurableVisualTests.swift \
swiftlint lint --strict --no-cache --use-script-input-files
```

Blocked attempts:

```bash
xcodebuild -version
# Xcode 27.0, build 27A266a; CI pins Xcode 26.6.

xcrun simctl list devices available
# CoreSimulatorService connection invalid; device set unavailable.

make ios-local-build ARGS='simulator -- build-for-testing -configuration Debug -destination "generic/platform=iOS Simulator"'
# Refused before compilation: Cannot verify whether xcodebuild is active.

make ios-local-build ARGS='audit --destination "platform=iOS Simulator,id=unavailable" --environment-label "local-sandbox-xcode-27"'
# Preflight failure retained. The unavailable id was a diagnostic placeholder,
# not an actual simulator or a claim that tests were scheduled.
```

Generic Simulator compilation, focused runtime acceptance, performance
measurements, the complete `merianTests` target and relevant UI execution could
not run. New Swift files have been linted and reviewed but are **not
compiler-verified**. CI was configured, not dispatched. No XCResult from a
runtime run exists for this change.

Evidence is under `.artifacts/runtime-audit-validation/`: `tooling.log`,
`local-build-tooling.log`, `swiftlint-affected.log`, `audit-attempt.log` and
this report. The failed audit preflight summary is under
`.artifacts/local-ios/audit-a4b86a844108451f9c4a49a9c1a549e7/`; it records the
source state at that earlier attempted run, not final runtime evidence.

## Remaining coverage and follow-up

No performance measurements exist to rank work by measured impact. The following
order reflects validation dependency and risk:

1. Run the final sources on an accessible Xcode 26.6 Simulator: generic build,
   focused audit, complete unit target and relevant UI tests. Resolve
   compiler/runtime failures before treating this as accepted.
2. Collect repeated matched-environment baselines. Rank performance work only
   after inspecting the distributions and profiling observed regressions.
3. Close composed integration gaps: Capture→queue→live response→Insight; active
   sign-out across that entire chain; concurrent terminal-download callbacks
   with once-only queue retirement/publication; interrupted file-copy/save
   failure; production-bootstrap V50 plan selection through a private store URL.
   The new restart case covers finalization and Insight binding, not terminal
   URLSession callbacks or queue deletion.
4. Add hermetic onboarding and Explore UI scenarios. Existing behavioral owners
   are selected, but full UI paths remain uncovered.
5. Use real devices for camera/microphone/video codecs, image/audio/video peak
   memory, thermal pressure, OS background transfer and forced termination,
   first-install/post-reboot launch, sustained complete-flow retained-memory
   growth and main-thread stall attribution. File-admission and response-mapping
   benchmarks are limited local measurements, not whole-flow or remote-provider
   performance.

Canonical details and selector ownership are in
`docs/development-guides/08-testing-strategy.md`, under “Automated runtime
acceptance and performance audit.”
