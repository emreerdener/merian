# Runtime audit continuation — 2026-09-18

Status: build, 26 focused tests, 437 acceptance tests and portable tooling gates
passed. The complete unit target has 4,066 passed, 3 failed, zero skipped. UI
and performance phases were blocked twice by simultaneous development builds.
This snapshot is not fully green or performance-qualified.

## Scope and provenance

Active development continues in the shared checkout. Validation uses a separate
snapshot at
`/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate`.
It includes concurrent changes captured during a stable before/after source
check; see `snapshot-origin.json` and `integrated-snapshot.patch`. Later
audit-owned test corrections and regenerated project output are recorded in the
final candidate patch/fingerprint. No result from this snapshot establishes the
state of later shared-checkout edits.

The prior independently approved candidate and its XCResults under
`../runtime-audit-validation/` remain unchanged.

## Changes

- `scripts/ios-runtime-audit.py`: zero-mean coefficient of variation (CV) is
  undefined, including an all-zero series. JSON stores null; Markdown prints
  undefined. Variance observations remain visible without a baseline and for new
  or undersampled metrics. Historical numeric-zero CV placeholders are
  interpreted from the validated mean and deviation. The manifest/wrapper retain
  requested metric families; absent hitch samples are explicitly UNMEASURED even
  on a first run.
- `scripts/local-ios-build.py`: retains expected metric families, validates them
  before building, and fingerprints app-side seed producers/test-mode
  configuration.
- `scripts/test-local-ios-build.py`: exercises seed/embedded-media fingerprint
  changes, retained metric expectations, and malformed optional metadata
  rejection; 25 tests pass.
- `scripts/config/ios-runtime-audit.json`: records the requested Hitch family
  for repeated Insight presentation.
- `apps/ios/README.md`: points directly to canonical runtime guide 18.
- `scripts/test-ios-runtime-audit.py`: five regression tests cover
  signed/all-zero means, rendering and JSON, missing baseline/metric, legacy
  compatibility, and near-zero/nonzero signed means, and requested metric
  absence. The new cases reproduced four assertion failures before the fix; all
  18 reporter tests now pass.
- `apps/ios/MerianTests/Core/Data/OfflineSync/DiskBackedInferenceAcceptanceTests.swift`:
  new visual admission → file-backed queue/job → dispatch boundary → live
  response parsing/SQLite persistence → real queue deletion → Insight reopening
  case. Real image encoding/file bytes and single record identity are checked.
  The same request is executed twice and admission retried; dispatch and
  completion-effect counters must remain one. Provider and external effects are
  injected.
- `apps/ios/MerianTests/Core/AI/Inference/InferenceLivePipelineCoordinatorTests.swift`:
  existing test harness accepts the already-defined request, result and queue
  services, allowing the composed test to use real persistence/queue owners.
- `apps/ios/MerianTests/Core/Network/Auth/AuthLocalSignOutCoordinatorTests.swift`:
  new real `AuthRuntimeState` lease-drain/sign-out composition proves duplicate
  release of one lease cannot release another or let SDK sign-out proceed early.
- `docs/development-guides/18-ios-runtime-quality-and-benchmarking.md`:
  documents the statistics interpretation, new coverage, and injected
  boundaries.

No production Swift, schema, endpoint, payload, feature flag, or release
behavior was changed by this continuation. The shared checkout includes separate
concurrent production edits, which are outside this change's ownership.

## Verification

Final focused Simulator run: 26 tests passed, zero failed or skipped. The exact
selectors were validated from XCResult; source identity was unchanged
before/after. See `focused/summary.json`, `focused/execution.json`, and
`focused-source-*.json`. The first failed test expectation and its raw results
remain diagnostic evidence.

- `python3 scripts/test-ios-runtime-audit.py`: 18 passed.
- `make test-ios-ci-tooling`: initial pass in `tooling.log`; final rerun after
  all review corrections is in `tooling-reviewed.log`.
- `python3 scripts/test-local-ios-build.py`: 25 passed; output
  `wrapper-tests.log`.
- Strict SwiftLint with `--no-cache` on the three affected Swift files: passed.
- `deno fmt` on the changed canonical guide: passed.
- `make validate-markdown-format`: passed for 51 then-changed Markdown files;
  output `markdown.log`.
- Snapshot `make xcodegen validate-ios-project` and source membership: passed
  using the official XcodeGen 2.45.4 release, SHA-256 checked against official
  release metadata. Default installed XcodeGen 2.45.2 was correctly rejected.
- Focused Simulator attempts: wrapper refused while another task's `xcodebuild`
  was active. No competing build was stopped or cache safety check bypassed.
  Both focused runs subsequently executed from the frozen snapshot.
- A concurrent compile exposed Swift Testing macro errors in throwing assertions
  inside the synthetic provider closure. Another task's correction separates
  throwing fetches from assertions; it was preserved and copied into the
  snapshot.

## Broad validation attempts

The first broad audit passed the generic Simulator build on both architectures.
Another development build then started; the wrapper refused acceptance, UI and
performance before execution. These phases are blocked by build contention, not
behavioral failures. The retained audit is
`candidate/.artifacts/local-ios/audit-58f4b4acc5ae412f8280d904dce4ebd4/summary.md`.
The complete unit target finished: **4,066 passed, 3 failed, zero skipped**
(4,069 total). The complete-target evidence gate correctly rejected the run. All
1,264 XCTest cases passed; Swift Testing reported the three failures below.
Source identity was identical before/after (`validation-source-*.json`).
Results: `complete-unit/summary.json`, `complete-unit/tests.json`,
`complete-unit/critical-gate.txt`, and retained XCResult
`candidate/.artifacts/local-ios/3a0f065e301d44008f6fd98d01243656.xcresult`.

These failures concern concurrent Explore implementation captured in the
snapshot:

| Failing test                                                                                | Observed mismatch                                                                                      | Owner to reconcile                                                                             |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| `CoreNetworkIntegrationArchitectureTests.endpointOwnerInventoryIsCompleteAndNonOverlapping` | 19 actual endpoint files vs 18 expected; new `MerianNetworkClient+ExploreReactions.swift`              | `apps/ios/MerianTests/Core/Network/Endpoints/CoreNetworkIntegrationArchitectureTests.swift:17` |
| `ExploreNetworkModelArchitectureTests.focusedOwnersRetireTheAggregateAndStayBounded`        | 14 actual model files vs 13 expected; new `ExploreReactionAPIModels.swift`                             | `apps/ios/MerianTests/Core/Network/Decoding/ExploreNetworkModelArchitectureTests.swift:15`     |
| `IOSHygieneClosureArchitectureTests.oversizedProductionOwnersRemainAnExplicitInventory`     | `Features/Explore/Feed/Views/ExplorePostDetailView.swift` additionally exceeds the test's line ceiling | `apps/ios/MerianTests/IOSHygieneClosureArchitectureTests.swift:24`                             |

These production/test owners are outside this continuation's edits. They were
left intact for the active development owner to reconcile; especially for the
size failure, review whether the view should be split rather than automatically
expanding the exception inventory. This integration snapshot is not fully green.
The managed audit retry passed the generic build and **437 acceptance tests**
(zero failed/skipped). Another development build started before the UI phase;
the wrapper again refused UI and performance before execution. No new
performance measurements were produced. This is build contention, not a
UI/performance behavioral failure, but neither phase can be claimed passed for
this candidate.

Retry evidence:
`candidate/.artifacts/local-ios/audit-c04b8e4eebe14aa881defe464b26ecb5/summary.md`,
its `audit.json`, `acceptance/summary.json`, `acceptance/tests.json`,
`audit-retry.log`, and `retry-source-*.json`. Source identity remained
unchanged. The earlier candidate's 5 UI/9 benchmark passes remain historical
evidence only.

## Historical measurements

`historical-reanalysis/` reprocesses the previous final batch's retained raw
measurements with the corrected reporter. It contains 48 series and correctly
marks the two zero-mean memory CVs undefined and the missing hitch family
UNMEASURED. This is report reanalysis, not a new benchmark, baseline approval,
or stability claim. Original baseline evidence is unchanged. Performance remains
report-only; deterministic behavior is test-gated.

## Review evidence

See `independent-review.md` for findings, corrections and limits. Exact final
candidate contents are retained in `candidate/`; `candidate-files.json` records
owned-file hashes and the candidate patch hash. `snapshot-origin.json` records
the initial capture, including concurrent nonignored files. The patch alone does
not include those untracked files; use the retained candidate for complete
review.

## Entry points for another agent

Use the frozen files for review; the corresponding shared-checkout files may
continue changing after this report:

- [Composed visual acceptance test](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/apps/ios/MerianTests/Core/Data/OfflineSync/DiskBackedInferenceAcceptanceTests.swift)
  and
  [pipeline harness](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/apps/ios/MerianTests/Core/AI/Inference/InferenceLivePipelineCoordinatorTests.swift).
- [Sign-out lease test](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/apps/ios/MerianTests/Core/Network/Auth/AuthLocalSignOutCoordinatorTests.swift).
- [Audit reporter](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/scripts/ios-runtime-audit.py),
  [reporter regression tests](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/scripts/test-ios-runtime-audit.py),
  [managed runner](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/scripts/local-ios-build.py),
  and
  [runner regression tests](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/scripts/test-local-ios-build.py).
- [Coverage manifest](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/scripts/config/ios-runtime-audit.json)
  and
  [canonical methodology](/Users/emreerdener/Developer/merian/.artifacts/runtime-audit-next/candidate/docs/development-guides/18-ios-runtime-quality-and-benchmarking.md).

Review whether the composed assertions would catch lost durable admission,
duplicate provider dispatch, duplicate completed records, lost media, and early
sign-out. Check that injected completion effects are not interpreted as proof of
root navigation or remote publication. Inspect global fixture cleanup before
assuming parallel-suite safety. Confirm that missing measurements, incompatible
workloads and undefined CV cannot produce a green performance qualification.

## Remaining boundaries

The visual composition starts at queue admission, not camera capture or the full
Capture workspace/UI assembly. Completion publication, hydration scheduling,
notifications and milestones are injected counters. Root navigation, remote
publication/upload, active URLSession cancellation, OS process-kill/relaunch,
hitch samples, physical capture/codecs/thermal behavior and sustained full-flow
retained-memory measurements remain unproven. The account fixture follows the
existing suite's global funding setup/reset conventions; it is not evidence of
arbitrary parallel-suite isolation.

Hosted validation requires a reviewed committed candidate available to the
runner. The frozen uncommitted integration snapshot has not been published or
dispatched. No deployment or release action was performed.

## Reproduction and next work

All commands below run from the frozen candidate root given above:

```bash
make ios-local-build ARGS='audit --destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" --environment-label "MacBookPro18-1-iOS27-continuation"'
make ios-local-build ARGS='simulator -- test-without-building -configuration Debug -destination "platform=iOS Simulator,id=33E6776C-4639-4EE9-BDB6-994A3941FEE6" -parallel-testing-enabled NO -only-testing:merianTests'
make test-ios-ci-tooling
```

The `test-without-building` command depends on the matching audit build
products. After cache cleanup, run the audit build first. An idle host/Simulator
window is required for the outstanding UI and performance phases. Reconcile the
three architecture failures with the active Explore owner, then capture and
verify a new stable integration candidate. Do not silently patch this retained
snapshot or treat this snapshot's results as validation of later shared-checkout
edits.

Stable performance qualification still requires repeated matching-environment
samples and an independently reviewed baseline. The zero-mean CV and missing
hitch reporting corrections do not themselves establish performance stability.

Build-cache cleanup was attempted with `make ios-clean-build-cache ARGS=--apply`
inside the candidate. The wrapper refused because another `xcodebuild` was
active. The approximately 7.4 GiB managed cache remains; rerun that same command
from the candidate when the host is idle. Retained reports/XCResults live
outside `.build` and must remain available for review.
