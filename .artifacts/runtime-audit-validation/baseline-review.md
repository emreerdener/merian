# Provisional report-only baseline review — 2026-09-18

The independent Merian contract auditor approved the final batch as a
provisional numerical comparison reference. This does not establish runner
stability or approve any performance gate. The complete final unit target passed
all 4,042 tests with zero failures or skips.

Both batches contain the same 48 metric series with 30 raw samples per series
(three repetitions of ten). Hardware, Simulator/runtime, Xcode, host OS,
configuration, and workload fingerprints match. Only non-measured unit tests and
documentation changed between batches; application and benchmark sources are
identical.

- [First audit and raw exports](candidate/.artifacts/local-ios/audit-1577a4d430564ef99ca0c42893659185/summary.md)
- [Final audit and raw exports](candidate/.artifacts/local-ios/audit-c0de018eac044e7abaa46bd9a6e2168c/summary.md)
- [All 48 inter-run deltas and CVs](inter-run-deltas.json)

[Download the reviewed report-only baseline](reviewed-baseline.json). Its
metadata explicitly forbids gating and identifies the two undefined
signed-memory CVs.

## Timing samples

These are the defined XCTest workloads, including UI automation where present;
they are not a claim about the unmeasured complete capture pipeline.

| Workload                             | First mean (s) | Final mean (s) |  Change | First CV | Final CV |
| ------------------------------------ | -------------: | -------------: | ------: | -------: | -------: |
| testAudioVideoFileAdmission          |      0.0636174 |      0.0710976 | +11.76% |    8.29% |    5.75% |
| testInferenceResponseMapping         |     0.00181553 |     0.00186848 |  +2.92% |    3.69% |    3.13% |
| testRepeatedBoundedImageDecode       |       0.222409 |       0.235112 |  +5.71% |    1.87% |    3.25% |
| testDurableQueueCommit               |     0.00090988 |     0.00111846 | +22.92% |    9.24% |   16.44% |
| testLargeLibraryScalarHydration      |      0.0752159 |      0.0765096 |  +1.72% |    2.43% |    1.62% |
| testLargeOfflineQueueProjection      |      0.0362654 |      0.0363405 |  +0.21% |    1.65% |    1.52% |
| testProcessColdLaunch                |        5.55159 |        7.36025 | +32.58% |    3.75% |   27.79% |
| testRepeatedAudioInsightPresentation |         2.9931 |        2.95968 |  -1.12% |    7.58% |    1.24% |
| testWarmForeground                   |         1.2482 |        1.29628 |  +3.85% |    1.30% |    3.68% |

## Interpretation

The final batch has 12 series with CV above 15% (the first has eight). The
reporter emits six review-increase observations. Cold launch changes from 5.55
to 7.36 seconds (+32.58%, final CV 27.79%). Durable queue commit changes from
0.910 to 1.118 milliseconds (+22.92%, final CV 16.44%). These are measurements
of unchanged application/workload code across two local runs, not demonstrated
application regressions.

Near-zero or signed memory changes have large CVs and unstable percentage
deltas; they do not establish a leak, retained-memory bound, or improvement. CPU
results also vary. Do not choose the faster batch, remove outliers, pool away
run differences, or turn these numbers into pass/fail thresholds.

No hitch series was exported. Hitches/stalls, physical capture/codec/thermal
behavior, first-install/reboot launch, complete-flow retained memory, and
dedicated-runner stability remain unverified.

Final high-variance series:

- testAudioVideoFileAdmission / CPU.cycles: CV 22.87%.
- testAudioVideoFileAdmission / CPU.time: CV 22.83%.
- testAudioVideoFileAdmission / Memory.physical: CV 1241.52%.
- testInferenceResponseMapping / Memory.physical: CV 305.13%.
- testRepeatedBoundedImageDecode / Memory.physical: CV 327.53%.
- testDurableQueueCommit / Clock.time.monotonic: CV 16.44%.
- testDurableQueueCommit / Memory.physical: CV 259.31%.
- testProcessColdLaunch /
  ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration: CV
  27.79%.
- testRepeatedAudioInsightPresentation / Memory-app.merian.Merian.physical: CV
  131.53%.
- testWarmForeground / CPU-app.merian.Merian.cycles: CV 17.92%.
- testWarmForeground / CPU-app.merian.Merian.instructions_retired: CV 18.91%.
- testWarmForeground / CPU-app.merian.Merian.time: CV 18.84%.

## Undefined signed-memory CVs

The final library-hydration and offline-queue-projection `Memory.physical`
series have zero means and nonzero standard deviations. Their CVs are
mathematically undefined; the existing reporter's numeric zero is a placeholder
and must not be read as stability. Raw samples and standard deviations remain
intact. There are 12 series with numeric CV above 15%, plus these two
undefined-CV series. No remaining series is qualified as stable solely by
falling below that observation cutoff.

The independent reviewer considers this explicit correction sufficient for a
provisional raw reference. Changing the generic reporter to represent undefined
CV is a non-blocking P3 tooling follow-up and a prerequisite to any future use
of CV for performance qualification.

## Reuse restrictions

Use this reference only for report-only comparisons against matching environment
and workload fingerprints. Retain the raw samples and all differences. A stable
dedicated runner and reviewed repeated evidence are prerequisites to any future
gating policy. No threshold, regression finding, or release authorization is
created by this review.
