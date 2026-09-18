# Runtime audit follow-up — 2026-09-18

Status: **immediate milestone passed for the isolated reviewed candidate**.
Independent review, final compilation, runtime execution, and critical-test
result validation are complete. Broader audit sufficiency remains partial.

## Reviewed source

The isolated candidate is based on `c1a426cd425add1acc5bfb39e2cbc9069049846a`
plus the 14-file [`audit-followup-final.patch`](audit-followup-final.patch). Its
SHA-256 is `457f50b58990c32bed5828aa4b6eaed14db5cddd15da8b97d4e9ff4184130f45`.
The final tracked-source fingerprint is
`1aa5f368f813d99eb0f783cea079e4c9b0010e7ce31a6c327d01e6b19b150c79`. The patch is
also applied in the main checkout. Concurrent unrelated iOS, web, and backend
edits are excluded from this candidate's runtime evidence.

The independent Merian contract auditor reviewed the original handoff,
implementation, fixes, and coverage. See the
[requirement-by-requirement verdict](followup-review.md).

## Fixes and coverage

- Reserve exclusive inference completion ownership before suspension. A
  duplicate result or transport-error callback can no longer retire the active
  completion owner.
- Reserve each inference terminal task's account-work lease until its accepted
  callback finishes. Duplicate callbacks cannot release another callback's
  sign-out protection. Download copies have unique filenames.
- Use explicit manual start and stop in four XCTest benchmarks. The previous
  configuration raised real runtime exceptions under Xcode 27.
- Verify source identity before and after every audit phase, fail closed on
  changes or unreadable identity, and fingerprint benchmark workload files for
  baseline compatibility.
- Add coverage for description admission through real SQLite finalization, queue
  retirement, and Insight reopening; active inference-write sign-out; duplicate
  terminal ownership; partial-file cleanup; and rejected saves followed by a
  writable retry.
- Update the architecture assertion to verify task ownership and lease cleanup
  before the first suspension. Keep admission tests below their 600-line ceiling
  by placing the new composed cases in the existing disk-backed suite.

## Final runtime evidence

| Check                                                    | Result                                                                  |
| -------------------------------------------------------- | ----------------------------------------------------------------------- |
| Final Simulator build                                    | Passed                                                                  |
| Focused acceptance                                       | 431 passed, zero failed/skipped                                         |
| Selected UI tests                                        | 5 passed, zero failed/skipped                                           |
| Benchmarks                                               | 9 workloads passed; 48 metric series, 30 samples per batch, two batches |
| Complete `merianTests` target                            | 4,042 passed, zero failed/skipped                                       |
| Critical suites and exact scan-flow regression validator | Passed                                                                  |
| Source and environment identity                          | Unchanged through final audit and complete target                       |

- [Final audit summary and metrics](candidate/.artifacts/local-ios/audit-c0de018eac044e7abaa46bd9a6e2168c/summary.md)
- [Complete target summary](complete-unit/summary.json),
  [exact command and source checks](complete-unit/execution.json),
  [critical validator](critical-results.log)
- [Reviewed report-only baseline](reviewed-baseline.json),
  [baseline review and limitations](baseline-review.md),
  [all inter-run deltas](inter-run-deltas.json)

The independent reviewer approves this milestone for the exact candidate above.
The baseline is provisional and explicitly ineligible for performance gates.
Final launch measurements increased about 33% between unchanged workloads; the
final batch contains 12 numeric CVs above 15% and two undefined signed-memory
CVs. The generic reporter's zero-mean CV placeholder is disclosed in the review
and baseline metadata; it must be corrected before using CV for future
performance qualification. No stable-runner, regression, leak, or release claim
follows.

## Execution history

The first diagnostic run reproduced the terminal-generation defect and manual
measurement exception. Its measurements are not a baseline.

The first isolated four-phase audit passed its build, 431 focused acceptance
tests, five UI tests, and nine benchmarks. It retained 48 metric series with 30
samples each. Its subsequent full target passed 4,040 of 4,042 tests, with zero
skips; the two failures were the stale architecture assertion and the test-file
size ceiling. Both are fixed. Their focused rerun passed all 16 tests in the
three affected suites. The initial full-target diagnostics remain in
[`initial-complete-unit`](initial-complete-unit).

The first metric batch remains a report-only comparison reference. Its
application and benchmark sources match the final candidate; the final changes
move unit tests, update the architecture assertion, and correct the
documentation owner. The final successful batch is now independently reviewed as
a provisional report-only comparison reference; no performance gate is approved.

The final patch passed
`make test-ios-ci-tooling validate-ios-project
validate-markdown-format`, strict
SwiftLint for changed Swift files, and `git diff --check`. Source membership was
verified. Logs are retained beside this report.

## Environment and limits

Execution uses the managed `make ios-local-build` wrapper and iPhone 18 Pro
Simulator, iOS 27.0, Xcode 27.0 (27A266a), Debug, on MacBookPro18,1 running
macOS 26.6.2. Benchmark configuration is three repetitions of ten measurements
per workload, with parallel testing disabled. Raw XCResults and extracted JSON
are retained in the candidate's `.artifacts/local-ios` directory.

Timing and memory comparisons remain report-only. The first batch contains eight
high-variance series, primarily near-zero memory changes. Percentages for those
measurements are not leak or regression evidence. No hitch samples were exported
despite the requested metric; hitches and stalls remain unverified.

Two selected-UI warnings report synchronous audio-session
activation/deactivation on the main thread. They are non-gating observations.
The first completed four-phase audit's optional post-test Simulator diagnostic
collector was stopped after all UI cases passed, allowing Xcode to finalize its
bundle. The final UI collector exited on its own before the attempted stop
command. The final post-benchmark optional diagnostic collector was also stopped
after all repeated benchmark cases passed. No test runner was stopped in either
passing audit. A later preflight correctly rejected a concurrent Xcode build and
was retried after that other task finished.

The complete original audit remains partial: no physical camera/microphone or
codec qualification, OS process-kill/background transfer recovery, complete
visual capture-to-Insight composition, full active-transfer sign-out
composition, all-effects duplicate counter, full-pipeline timing/retained-memory
proof, or hosted CI execution. This evidence does not validate concurrent
main-checkout changes or establish a stable dedicated performance runner.

## Retained storage

Raw XCResults, samples, source patch, and reports are retained outside managed
build outputs. Candidate cache cleanup is pending because another task started
an Xcode build; the wrapper correctly refuses cleanup while any build is active.

The deferred cleanup command, once Xcode builds are idle, is:

```bash
cd /Users/emreerdener/Developer/merian/.artifacts/runtime-audit-validation/candidate
make ios-clean-build-cache ARGS='--apply'
```

The retained cache is disposable and is not needed to inspect the evidence.
