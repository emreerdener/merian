# Independent runtime audit review — 2026-09-18

Read-only review by the Merian contract-auditor agent, using the original
request, handoff, current implementation, and subsequent primary-agent changes.
The configured reviewer agent could not start because its model was unavailable;
the contract auditor performed the independent review instead.

## Final independent verdict

**PASS for the immediate milestone, scoped to the isolated reviewed candidate.**
The reviewer independently verified the final build, 431 focused acceptance
tests, five selected UI tests, nine benchmarks, and the complete 4,042-test
`merianTests` target. All passed, with zero failures or skips. Source and
environment identities remained unchanged. The critical-suite/exact-regression
result validator passed.

The [reviewed baseline](reviewed-baseline.json) is approved only as a
provisional report-only numerical reference: two matching 30-sample batches
across 48 metric series. Runner stability is not demonstrated. There are 12
numeric CVs above 15%, two undefined signed-memory CVs, and six report-only
increase observations. No performance thresholds or release action are approved.

## Correctness findings

1. **High: equal-generation terminal callbacks were not exclusive.**
   `OfflineQueueManager+InferenceLifecycle.claimInferenceGeneration` accepts the
   current generation; both result and transport-error handlers could therefore
   suspend and retire the same owner. The Simulator regression
   `duplicateTerminalCallbacksCannotRetireSuspendedResultOwner` failed six
   assertions before the fix. Result and error handlers now reserve the existing
   completion-generation slot before suspension and clear only their own slot.
2. **High: an ignored duplicate could release another callback's Auth lease.**
   Both terminal routers unconditionally finished the task-keyed account lease.
   A duplicate could release it while the accepted owner was still persisting.
   The routers now reserve task ownership before their first suspension. Only
   the owner releases that lease. Each delegate response copy has a unique
   temporary filename so a duplicate cannot overwrite the original response. The
   reviewer approved this repair and its router-level regression seam.
3. **Confirmed benchmark configuration failure:** four manual measurement
   benchmarks called `stopMeasuring()` without `.manuallyStop`. Xcode 27
   rejected the queue-commit and process-launch runs. Both affected files now
   specify manual start and stop. The independent reviewer approved the
   correction.
4. **Confirmed source-evidence gap:** source edits during a run were not
   detected. The audit now checks HEAD, tracked bytes, status, and untracked
   contents before and after each phase, blocks on changes or unreadable
   identity, and fingerprints workload files for baseline compatibility.
5. **Retracted reporter concern:** the real Xcode 27 repeated-test tree contains
   one suite per class and repetitions under test cases. The existing suite
   matching logic is correct for this runtime.
6. **Retracted file-loss finding:** partial adoption cleanup deletes moved
   temporary media. The capture-staging contract and visual submission rejection
   branch explicitly require discard on rejected admission. The new test proves
   partial-destination cleanup under that policy, not source retryability.

7. **Full-target architecture failures, fixed:** the terminal ownership repair
   expanded the old one-line lease cleanup, invalidating a source-shape
   assertion; the new admission tests also exceeded their file's 600-line
   ceiling. The assertion now verifies ownership/cleanup before suspension, and
   the new cases moved to the existing disk-backed suite with shared-state
   serialization. All 16 affected focused tests and the complete target pass.
8. **P3 remaining tooling caveat:** the generic reporter represents CV as zero
   when the mean is zero, even if standard deviation is positive. Two final
   signed-memory series have mathematically undefined CVs. The baseline review
   and metadata explicitly correct their interpretation while preserving raw
   samples and SD. This does not block the provisional reference; the reporter
   must represent undefined CV correctly before any future stability/gating use.

## Requirement sufficiency

Runtime execution is now verified for the final candidate. Selected owner suites
are not equivalent to one complete Capture-to-Insight process test.

| Requirement                                                        | Coverage verdict               | Evidence or remaining gap                                                                                                                             |
| ------------------------------------------------------------------ | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture admission/cancellation and durable-before-response         | Partial                        | Existing owner tests plus new description admission → SQLite → synthetic finalization → queue retirement → Insight; visual encoding/dispatch bypassed |
| Live/queued completion, retries, timeout, generation fencing       | Partial                        | Owner tests and duplicate outer-lease/inner-generation regressions passed; complete transport composition remains partial                             |
| Insight media, dismissal, restoration                              | Partial                        | Binding/reopening integration plus five UI cases; no capture-derived full media pipeline                                                              |
| Relaunch/offline replay/background                                 | Partial                        | SQLite reopening and UI background/foreground; no killed-process URLSession replay                                                                    |
| Active sign-out                                                    | Partial                        | Real inference write drain with injected Auth effects; active transfer/queue/Insight composition missing                                              |
| Interrupted persistence/network                                    | Partial                        | Malformed response, partial-file cleanup, read-only save failure and writable retry; no save failure after every media copy                           |
| No duplicate records/effects/routes                                | Partial                        | Record finalization and terminal ownership covered; all real upload/publication/route effects are not counted in one composed test                    |
| Cold/warm launch and Insight timing                                | Measured, report-only          | Process-cold launch only; not first install/reboot                                                                                                    |
| Capture-to-stage, stage-to-dispatch, full result processing        | Missing                        | Queue commit and response mapping benchmarks measure narrower boundaries                                                                              |
| Peak image/audio/video memory, CPU/stalls, retained full-flow work | Partial                        | Image decode and UI CPU/memory measured; no exported hitch metrics, codec/device qualification, or sustained full-flow attribution                    |
| Large library/queue performance                                    | Measured, report-only          | 1,000-record workloads                                                                                                                                |
| Repeated baseline, variance, report-only comparison                | Provisional reference reviewed | Two batches, 48 series, 30 samples each; variance and undefined CVs disclosed; stable runner unproven                                                 |
| CI, retained evidence, documentation                               | Partial                        | Local audit/full target/tooling passed with retained evidence; hosted lane has not been dispatched                                                    |

The complete original audit is **not yet sufficient**. Passing local runtime
evidence establishes only the implemented workload and Simulator boundaries.
Physical capture, codecs, thermal pressure, actual OS background termination,
full-flow retained memory, and hosted-runner stability remain separate work.

## Diagnostic runtime evidence

The first run compiled successfully, then reproduced the terminal-owner bug in
one test (six assertions). Its UI bundle passed all five tests with zero skips.
Two audio-session warnings report synchronous activation/deactivation on the
main thread; these are observations, not test failures. The benchmark run
reproduced the manual-stop defect and was interrupted instead of continuing
known-invalid measurements. Optional Simulator diagnostic collectors stalled
result finalization and were terminated; the UI bundle nevertheless finalized as
passed.

Because sources were edited during the initial build, its recorded initial
fingerprint is not candidate provenance. The run is diagnostic only and must
never become a performance baseline. The new provenance checks enforce this
restriction for future runs.

## Isolated candidate boundary

Concurrent iOS/UI and web edits twice changed the shared tree during
compilation. Both successful compiles were rejected by the source-identity
guard, with all runtime phases blocked. Final execution uses the detached
checkout at `.artifacts/runtime-audit-validation/candidate`, based on
`c1a426cd425add1acc5bfb39e2cbc9069049846a` plus only this task's 14-file patch.
The patch SHA-256 is
`457f50b58990c32bed5828aa4b6eaed14db5cddd15da8b97d4e9ff4184130f45`. Dependency
downloads were cloned locally. Cleanup of the candidate managed Simulator cache
was blocked by another task’s active Xcode build; evidence and cache remain
retained, and no other task was interrupted. Evidence for this candidate does
not establish integration with the concurrent shared-tree changes.
