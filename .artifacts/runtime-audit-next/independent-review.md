# Independent continuation review — 2026-09-18

Read-only review by the Merian contract auditor. This is source/tooling review,
not Simulator or release approval.

The reviewer identified four actionable gaps:

1. Baseline workload identity omitted app-side UI-test seeds. Added the complete
   `Merian/App/UITesting` directory and `TestExecutionCoordinator.swift` to the
   workload fingerprint; the regression failed before this correction. Product
   presentation/startup wiring remains comparable, so product changes do not
   silently force rebaselining.
2. Optional metric-family expectations were not validated during audit
   preflight. The wrapper now rejects nonlists, nonstrings and blank family
   names before building; retained evidence reports explicit preflight failure.
3. The iOS README linked the older strategy section rather than canonical guide
   18. The link now points directly to the current methodology.
4. Sequential duplicate execution alone did not cover concurrent admission. The
   test now suspends the first injected provider response and rejects a second
   admission for the same scan/generation before releasing completion. The
   reviewer confirmed production has exactly one `admit` → `executeVisual` path
   and no caller directly reusing an accepted session concurrently.

The reviewer independently ran the reporter (18 tests) and wrapper (25 tests)
with all passing after the tooling corrections. Swift runtime verification is
owned by the primary task and recorded separately in the final report.

A separate read-only explorer also noted that the still-image test cannot prove
video-upload idempotence or root navigation: the unused upload counter was
removed and the documentation explicitly identifies injected completion-effect
counters. The pre-existing global entitlement fixture setup/reset convention
remains a parallel-suite isolation limitation; no arbitrary parallel-execution
claim is made.
