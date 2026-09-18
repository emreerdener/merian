# Review handoff: iOS runtime acceptance and performance audit

## Assessment boundary

This is an implemented audit framework with additional regression tests, not a
completed runtime/performance acceptance result. Another agent should
independently determine whether the implementation is correct and whether its
coverage is sufficient for the original request. **The new Swift tests and
benchmarks have not been compiler- or runtime-verified. No performance baseline
has been measured.**

The primary requested path was Capture → durable staging → live/offline
inference → Insight. Secondary scope included startup/recovery, onboarding,
Explore, offline sync, authentication/sign-out, V50/V51 migration,
cancellation/retry/background interruption and relaunch. The request also
required repeated performance measurements, CI integration, retained evidence
and documentation.

The implementation is uncommitted. Several new files are untracked, so
`git diff` alone does not show the whole change. Inspect `git status --short`
and read the new files explicitly. Unrelated production edits coexist in the
working tree; the exclusions below identify them.

Original request:
[pasted-text.txt](/Users/emreerdener/.codex/attachments/fb8e8c27-13f0-4882-8573-bddc9375d2d6/pasted-text.txt).

Execution report and exact verification commands:
[.artifacts/runtime-audit-validation/report.md](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-validation/report.md).

## Implementation inventory

### Build, execution and evidence

The existing local build wrapper gained an `audit` command. It holds one cache
lock through locked package resolution, one generic Simulator build, acceptance,
UI acceptance and separate benchmark runs. It preserves disk/process checks,
uses test-without-building after compilation, and retains result bundles outside
the cache. A build failure prevents stale-product test execution. Failed
acceptance remains failed even when later phases collect evidence.

The reporter reads XCResult summary/tree/metric JSON, checks selected suite/case
execution, aggregates raw measurements and emits JSON/Markdown. Baseline
validation requires a successful complete audit and at least 30 raw samples per
metric, checking reported statistics against the samples. Environment
comparisons exclude ephemeral simulator UDIDs and include stable
model/runtime/toolchain/host/hardware identifiers. Source SHA, dirty state and
fingerprint are retained.

| File                                                                                                               | Change / review focus                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [scripts/local-ios-build.py](/Users/emreerdener/Developer/merian/scripts/local-ios-build.py)                       | Modified existing wrapper: `Workspace.audit`, `run_locked`, package resolution, environment identity, preflight failure evidence and cache-lock lifetime.                                                                   |
| [scripts/ios-runtime-audit.py](/Users/emreerdener/Developer/merian/scripts/ios-runtime-audit.py)                   | New evidence parser, selected-test validator, statistics, baseline validation/comparison and report writer. Review actual XCResult compatibility carefully.                                                                 |
| [scripts/config/ios-runtime-audit.json](/Users/emreerdener/Developer/merian/scripts/config/ios-runtime-audit.json) | New executable acceptance/UI/benchmark selector matrix with suite aliases and source owners.                                                                                                                                |
| [scripts/test-local-ios-build.py](/Users/emreerdener/Developer/merian/scripts/test-local-ios-build.py)             | Extended portable tests: one-build sequencing, cache lease, stale-product refusal, failure retention, stable environment matching and malformed manifest handling. Current total: 20 tests, including preexisting coverage. |
| [scripts/test-ios-runtime-audit.py](/Users/emreerdener/Developer/merian/scripts/test-ios-runtime-audit.py)         | New 12-case portable suite for evidence validation, metrics, variance, baseline validation and manifest ownership.                                                                                                          |
| [Makefile](/Users/emreerdener/Developer/merian/Makefile)                                                           | Routes `make ios-local-build ARGS='audit ...'` through the existing wrapper; includes reporter tests in `test-ios-ci-tooling`.                                                                                              |

### Behavioral regression tests

| File                                                                                                                                                                                                             | Added or changed behavior                                                                                                                                                                                                                                                                 | Important limit                                                                                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [apps/ios/MerianTests/Core/Data/OfflineSync/DiskBackedInferenceAcceptanceTests.swift](/Users/emreerdener/Developer/merian/apps/ios/MerianTests/Core/Data/OfflineSync/DiskBackedInferenceAcceptanceTests.swift)   | Two new tests. Reopen isolated SQLite; reconcile interrupted inference; claim new generation; reject stale result; race two finalization actors; assert one durable result; restore Insight and fence dismissed presentation. Malformed response retains queue/job and creates no result. | Calls finalization service directly. It intentionally retains the queue row. It does not exercise terminal URLSession callbacks, queue retirement, network dispatch, publication or full process relaunch. |
| [apps/ios/MerianTests/Core/AI/Inference/InferenceLivePipelineDurableVisualTests.swift](/Users/emreerdener/Developer/merian/apps/ios/MerianTests/Core/AI/Inference/InferenceLivePipelineDurableVisualTests.swift) | Adds `completedAttemptCannotDispatchOrPublishTwice` and `cancellationDuringPersistenceSuppressesLatePublication`, reusing the existing pipeline harness and suspension gate.                                                                                                              | Injected persistence/request effects. Duplicate execution is a retired live attempt, not a concurrent terminal-download delivery race.                                                                     |
| [apps/ios/MerianUITests/merianUITests.swift](/Users/emreerdener/Developer/merian/apps/ios/MerianUITests/merianUITests.swift)                                                                                     | Replaces the unconditionally skipped `testBackgroundSyncOfflineDisappearance` with `testBackgroundInterruptionPreservesQueuedAudioInsight` (around line 1424). Checks exact seeded audio/scan across background return, dismissal and reopening.                                          | UI fixture uses an in-memory store. This is not proof of on-disk durability after process termination. Existing four critical scan UI cases are reused by the audit.                                       |

The manifest also selects existing behavior owners for capture admission,
context grace/retry, live recovery, durable inference lifecycle, Insight
lifecycle/handoff, media budgets, task bounds, bootstrap/store recovery,
migration, onboarding, Explore feed and Auth transition/drain behavior.
Selecting these owners is not equivalent to adding new composed end-to-end tests
for every requested scenario.

### Benchmarks and fixture sharing

| File                                                                                                                                                                       | Benchmarks / change                                                                                                                                                                                              |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [apps/ios/MerianPerformanceTests/PersistencePerformanceTests.swift](/Users/emreerdener/Developer/merian/apps/ios/MerianPerformanceTests/PersistencePerformanceTests.swift) | Three new benchmarks: durable SQLite queue/job commit; fresh-context scalar hydration of 1,000 records; projection of 1,000 offline queue rows. Commit verification/cleanup stays outside the measured interval. |
| [apps/ios/MerianPerformanceTests/MediaPerformanceTests.swift](/Users/emreerdener/Developer/merian/apps/ios/MerianPerformanceTests/MediaPerformanceTests.swift)             | Three new benchmarks: 20 bounded ImageIO decodes per sample; 100 media-file admission checks; 100 response decode/domain mappings.                                                                               |
| [apps/ios/MerianUITests/RuntimePerformanceTests.swift](/Users/emreerdener/Developer/merian/apps/ios/MerianUITests/RuntimePerformanceTests.swift)                           | Three new benchmarks: process-cold launch until responsive; warm foreground return; repeated audio Insight opening/hydration. Uses app CPU/memory and iOS 26+ hitch metrics where applicable.                    |
| [apps/ios/TestSupport/InferenceAudioTestFixtures.swift](/Users/emreerdener/Developer/merian/apps/ios/TestSupport/InferenceAudioTestFixtures.swift)                         | Existing canonical WAV fixture relocated unchanged from MerianTests/Support so unit and performance bundles share one owner. App target does not include it.                                                     |

All nine benchmarks request 10 XCTest measurement iterations; the audit requests
three test iterations. Actual exported samples, not those requested counts, are
authoritative. Reported statistics include count, mean, median, sample SD, CV,
min and max.

These are bounded local workloads. File admission is not audio/video decoding,
response mapping is not whole inference processing, process-cold launch is not
first install/post-reboot cold launch, and repeated Insight presentation is not
a complete capture/inference memory-leak workload. The application has existing
timing logs; this change does not add whole-flow signpost measurement.

### CI, generated project and documentation

| File                                                                                                                                                   | Change / review focus                                                                                                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [.github/workflows/ios-build-and-test.yml](/Users/emreerdener/Developer/merian/.github/workflows/ios-build-and-test.yml)                               | Existing normal CI build now includes `merianPerformanceTests`. Runtime complete-unit selection remains `merianTests`; existing four protected UI cases remain unchanged.                     |
| [.github/workflows/ios-runtime-audit.yml](/Users/emreerdener/Developer/merian/.github/workflows/ios-runtime-audit.yml)                                 | New manually dispatched workflow using Xcode 26.6 and the existing wrapper. Uploads audit artifacts for 14 days. Loads a reviewed checked-in baseline if present. It has not been dispatched. |
| [scripts/validate-ios-critical-test-results.sh](/Users/emreerdener/Developer/merian/scripts/validate-ios-critical-test-results.sh)                     | Requires all four new unit regression cases in normal complete-unit XCResult evidence.                                                                                                        |
| [scripts/test-validate-ios-critical-test-results.sh](/Users/emreerdener/Developer/merian/scripts/test-validate-ios-critical-test-results.sh)           | Adds fixtures and missing/skipped-case rejection coverage for those four cases.                                                                                                               |
| [scripts/test-ios-build-and-test-workflow.sh](/Users/emreerdener/Developer/merian/scripts/test-ios-build-and-test-workflow.sh)                         | Requires performance-target compilation and updates protected exact-case count from 99 to 103.                                                                                                |
| [project.yml](/Users/emreerdener/Developer/merian/project.yml)                                                                                         | Authoritative new performance test target; shared TestSupport sources included only by test bundles; performance target added to Merian test scheme.                                          |
| [merian.xcodeproj/project.pbxproj](/Users/emreerdener/Developer/merian/merian.xcodeproj/project.pbxproj)                                               | Regenerated with make xcodegen; inspect source membership and shared fixture relocation.                                                                                                      |
| [merian.xcodeproj/xcshareddata/xcschemes/Merian.xcscheme](/Users/emreerdener/Developer/merian/merian.xcodeproj/xcshareddata/xcschemes/Merian.xcscheme) | Regenerated scheme. Default full-scheme test includes performance target; audit uses explicit phase selectors.                                                                                |
| [docs/development-guides/08-testing-strategy.md](/Users/emreerdener/Developer/merian/docs/development-guides/08-testing-strategy.md)                   | New audit section near line 336: ownership matrix, methods, baseline procedure, gating, limitations, evidence and triage.                                                                     |
| [apps/ios/README.md](/Users/emreerdener/Developer/merian/apps/ios/README.md)                                                                           | Documents benchmark and shared-fixture ownership and links to canonical audit method.                                                                                                         |

## What passed, what did not run

- Project generation, generated-project guards and source-membership checks
  passed.
- Portable reporter tests: 12 passed. Existing/extended wrapper tests: 20
  passed. These are Python tooling tests, **not iOS runtime test results**.
- Complete `make test-ios-ci-tooling` passed; final preflight-report refinements
  also passed the focused Python suites afterward.
- Strict SwiftLint passed on six changed/new Swift test files. The shared WAV
  helper was moved without content changes.
- Markdown formatting and `git diff --check` passed.
- Generic Simulator build was refused before compilation because the wrapper
  could not inspect active xcodebuild processes. Separately,
  CoreSimulatorService was unavailable. Installed Xcode was 27.0; CI pins 26.6.
- Focused acceptance, performance, complete `merianTests`, and relevant UI tests
  **did not execute**. New Swift sources remain compiler-unverified.
- No numerical baseline, variance or measured regression exists. No production
  bug was confirmed by executed regression evidence, and this audit authored no
  production behavior fix.

Evidence files:

- [.artifacts/runtime-audit-validation/tooling.log](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-validation/tooling.log)
- [.artifacts/runtime-audit-validation/local-build-tooling.log](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-validation/local-build-tooling.log)
- [.artifacts/runtime-audit-validation/swiftlint-affected.log](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-validation/swiftlint-affected.log)
- [.artifacts/runtime-audit-validation/audit-attempt.log](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-validation/audit-attempt.log)
- [.artifacts/local-ios/audit-a4b86a844108451f9c4a49a9c1a549e7/summary.md](/Users/emreerdener/Developer/merian/.artifacts/local-ios/audit-a4b86a844108451f9c4a49a9c1a549e7/summary.md)

The failed audit preflight artifact records an earlier attempt, not runtime
evidence for the final tree. `.artifacts` is ignored/local; attach these reports
separately if the next agent does not share this checkout. Runtime reporter
tests were printed to tool output; the full tooling log also records their
execution.

## Sufficiency gaps the reviewer must assess

1. **Whole-path composition:** no single new test traverses actual Capture
   submission → durable admission → injected live response → saved record →
   Insight. Existing owner tests and the new finalization/restoration test cover
   portions.
2. **Sign-out composition:** Auth/drain owners are selected, but there is no new
   combined active capture/queue/Insight sign-out acceptance case.
3. **Terminal duplicate delivery:** direct finalization idempotency does not
   prove once-only queue deletion, upload, funding settlement, notification,
   publication or route presentation across concurrent terminal callbacks.
4. **Partial persistence:** new malformed-response coverage does not inject
   file-copy failure after partial adoption or SwiftData save failure after
   media copying.
5. **Relaunch:** store reopening is narrower than killed-process recovery and
   background replay. The UI seed is in-memory.
6. **Startup/migration:** existing V50/V51 migration and bootstrap suites are
   selected; production bootstrap plan selection through a private injected
   store URL remains a gap.
7. **Secondary UI:** no new complete hermetic onboarding or Explore UI flow.
8. **Performance scope:** no measured end-to-end capture-to-stage,
   stage-to-dispatch, async result-processing or first-render boundary. No
   actual audio/video codec peak-memory measurement or sustained full-flow
   retained-task/memory attribution.
9. **Baselines:** review whether three repeated runs produce useful independent
   evidence, whether environment identity is sufficiently strict, and whether
   the report-only 20% plus three-standard-error heuristic is appropriate. It is
   not a hard CI regression gate.
10. **Evidence validation:** exercise real Xcode 26.6 XCResults, including
    repeated test runs, failed/skipped cases, metric identity, incomplete
    measurements and baseline mismatch. Portable fixtures alone cannot establish
    compatibility.
11. **Execution integration:** verify the benchmark target builds in normal CI
    and the manual audit builds exactly once, uses the same products, retains
    failure evidence and never mixes acceptance with hardware-sensitive gates.
12. **Default scheme:** assess whether including the performance bundle in the
    ordinary Merian TestAction is acceptable. Explicit CLI selectors separate
    audit phases, but a default full-scheme test includes benchmarks.

Physical-device gaps include camera/microphone behavior, codecs and playback,
thermal pressure, actual OS background transfer/termination, first-install cold
launch, full-flow memory growth and main-thread stall attribution. No
measured-impact ranking is possible until runtime data exists.

## Unrelated working-tree edits: do not attribute to this audit

These production-file edits appeared during the work and were preserved. Review
them separately if doing a whole-tree review; do not revert them as part of
reviewing this audit:

- [apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager.swift)
- [apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+URLSessionDelegate.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+URLSessionDelegate.swift)
- [apps/ios/Merian/Features/Capture/Shell/Modifiers/CameraSheetRouter.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Capture/Shell/Modifiers/CameraSheetRouter.swift)
- [apps/ios/Merian/Features/Capture/Shell/Modifiers/CaptureWorkspacePresentationModifier.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Capture/Shell/Modifiers/CaptureWorkspacePresentationModifier.swift)
- [apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Components/Review/CandidatesCard.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Components/Review/CandidatesCard.swift)
- [apps/ios/Merian/Features/Profile/UserProfile/Views/ProfileTabView.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Profile/UserProfile/Views/ProfileTabView.swift)
- [apps/ios/Merian/Features/Scans/Collections/Components/Cards/FeaturedCollectionCard.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Scans/Collections/Components/Cards/FeaturedCollectionCard.swift)
- [apps/ios/Merian/Features/Scans/Collections/Views/CollectionsView.swift](/Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Scans/Collections/Views/CollectionsView.swift)
- [apps/ios/widgets/Explore/MerianExploreWidget.swift](/Users/emreerdener/Developer/merian/apps/ios/widgets/Explore/MerianExploreWidget.swift)

## Suggested instructions for the reviewing agent

Review this implementation independently against the original request. Read
AGENTS.md, the merian-ios skill, the canonical testing strategy, this handoff
and the original request. Inspect tracked diffs and the explicitly listed
untracked files; preserve unrelated changes. Start as a read-only review unless
asked to implement fixes.

Return severity-ranked actionable findings with exact file/line evidence, a
requirement-by-requirement sufficiency matrix (covered, partially covered,
missing, or unverified), and a clear verdict on whether the system is enough.
Distinguish existing selected tests from newly added coverage and isolated
finalization from terminal/background end-to-end behavior. Check fixture
hermeticity, concurrency fencing, retained-task cleanup, test-target membership,
schema/payload preservation, baseline validity and failure evidence. Do not
infer runtime success from lint or portable Python tests.

If the environment supports execution, use the existing make ios-local-build
wrapper and storage policy to compile and run the audit, then the complete unit
target and relevant UI tests. Do not bypass process/disk checks or invoke live
external services. If runtime is blocked, report the blocker and leave
runtime/baseline sufficiency explicitly unresolved. Recommend the smallest
high-value next changes, distinguishing measured impact from risk-based
prioritization.
