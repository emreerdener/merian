# Runtime audit verification follow-up

The requested CV correction and foreground visual acceptance case were already
present when this verification began. All ten owned file hashes match
`../runtime-audit-next/candidate-files.json`. No production or test
implementation was rewritten by this follow-up.

Independent read-only reviewers `visual_flow_trace` and
`runtime_contract_review` examined the flow and reporting. Their verdicts:

| Requirement                                      | Verdict                  | Evidence and boundary                                                                                                                                         |
| ------------------------------------------------ | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Zero-mean CV cannot appear stable                | Sufficient               | Exact zero mean, including all-zero measurements, produces JSON null, Markdown undefined, and an explicit observation. Legacy CV placeholders are recomputed. |
| Near-zero CV remains visible                     | Sufficient for reporting | Nonzero means retain numeric CV; high variation remains explicit. This does not qualify runner stability.                                                     |
| Missing hitch measurements                       | Sufficient for reporting | Requested but absent Hitch metrics are explicitly UNMEASURED.                                                                                                 |
| Durable visual admission before dispatch         | Covered                  | Real JPEG, queue and job persistence are checked before the controlled provider response.                                                                     |
| Persistence, queue retirement, media and Insight | Covered locally          | Live result and queue services produce one completed record, retire the queue, preserve image bytes, and reopen Insight with the same record.                 |
| Duplicate visual admission/execution             | Covered                  | Admission while the first request is suspended and repeated execution do not redispatch or duplicate completion effects.                                      |
| Background terminal callbacks/Auth               | Separate coverage only   | The foreground composition does not enter URLSession terminal routing or acquire its Auth lease.                                                              |
| Complete camera-to-root-UI flow                  | Partial                  | Entry is queue admission; camera/Capture workspace assembly and root navigation are outside the composition. Completion effects use injected counters.        |
| Process interruption                             | Partial                  | Disk-backed tests exercise persistence boundaries; an OS kill and relaunch is not established.                                                                |
| Integrated green milestone                       | Not established          | The retained full unit run has three Explore architecture failures.                                                                                           |

The retained snapshot's source identity matches its successful build and
437-test acceptance run. New UI/performance retries use its existing managed
build products and preserve before/after source identity. Results are recorded
separately here; the historical audit is not overwritten. Shared-checkout
production changes after snapshot capture are not validated by this evidence.

See `../runtime-audit-next/report.md` for the complete retained candidate and
known architecture failures. Performance remains report-only.

## Verified evidence

- Fresh portable tooling gate: `make test-ios-ci-tooling` passed; raw output is
  `tooling.log`. Reporter regression tests separately passed 18/18.
- Retained focused run: 26 passed, zero failed/skipped. This includes the new
  visual composition and sign-out lease-drain cases.
- Retained acceptance run: 437 passed, zero failed/skipped.
- Fresh UI retry: five passed, zero failed/skipped. The source identity matched
  the retained build before and after execution. See `ui/summary.json`,
  `ui/tests.json`, and `ui-evidence.json`.
- The optional post-test Simulator diagnostic collector was terminated after all
  UI tests completed; Xcode subsequently exited successfully and the finalized
  XCResult passed exact-selector validation. See `diagnostic-intervention.txt`.
  Diagnostic completeness is limited by this intervention; neither the test
  runner nor Xcode was terminated.
- Retained full unit run: 4,066 passed, three failed, zero skipped. The failures
  are endpoint ownership inventory, Explore model inventory, and the oversized
  Explore detail view. They require a new reviewed integration candidate after
  reconciliation with the concurrent Explore implementation.

The source identity fence verifies the frozen candidate, not arbitrary later
shared-checkout changes. Repeating the unchanged full unit suite would not
resolve its already-recorded deterministic architecture failures.

## Final measurement result

The fresh performance retry passed all nine selected tests, each repeated three
times, with zero failures or skipped tests. Exact-selector extraction succeeded.
Source identity stayed unchanged. Forty-eight exported metric series each
contain thirty samples. Seven numeric coefficients of variation exceed 15%; no
series in this particular batch has a zero mean. Requested Hitch measurements
remain UNMEASURED. Cold launch averaged 5.2665 seconds, with 5.42% CV across the
thirty samples.

The older provisional baseline differs in environment label and workload
fingerprint. No candidate-versus-baseline delta is asserted, and that reviewed
baseline is preserved unchanged. This run is an additional report-only
reference, not proof of stable runner behavior or full integration
qualification. See `summary.md` and `audit.json` for all raw sample summaries
and observations; `performance/metrics.json` retains the XCResult metric export.
The new report records only its two fresh phases, rather than falsely claiming a
newly executed four-phase audit.

The optional post-test diagnostic collector was also terminated after benchmark
completion. Xcode exited successfully and the finalized result export passed
validation. Both interventions are recorded in `diagnostic-intervention.txt`.

The scoped CV and foreground-flow work has reviewed passing runtime evidence.
The broader integrated milestone remains open because the retained complete unit
target has three architecture failures and the complete camera/background
transport boundaries listed above remain partial.

## Cache retention

Managed cache cleanup was attempted after the results were finalized. The
repository wrapper refused because another `xcodebuild` process had started. No
safety guard was bypassed and no competing build was stopped. The candidate's
approximately 7.4 GiB cache remains; rerun
`make ios-clean-build-cache ARGS=--apply` from `../runtime-audit-next/candidate`
when builds are idle. Result bundles and reports live outside `.build` and are
retained independently. See `cache-cleanup.log`.

## Independent final evidence verdict

`runtime_contract_review` independently checked the finalized UI and benchmark
exports, exact case results, sample counts, source identity against the prior
build and acceptance run, variance observations, and diagnostic interventions.
Verdict: approve retention as a report-only measurement reference; reject stable
baseline promotion and performance gating. One fresh thirty-sample batch and
separate phase retries do not satisfy repeated matching-environment stability or
a complete successful audit. The overall integration milestone remains partial.
