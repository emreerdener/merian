# iOS runtime audit

Source commit: `c1a426cd425add1acc5bfb39e2cbc9069049846a` Working tree dirty:
`True` Source fingerprint:
`d13da704f96053ddee8163e112008ba12863da51ee7c8af894c756e9a07cfc48`

Hardware-dependent measurements are report-only. Behavioral failures fail the
run.

- ui: passed;
- performance: passed;

## Measurements

| Metric                                                                                                                                                                                   |  n |        Mean |          SD |   CV % |         Min |         Max |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -: | ----------: | ----------: | -----: | ----------: | ----------: |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                        | 30 |      182558 |     22532.7 |  12.34 |      173767 |      300920 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                          | 30 |      684270 |     39960.1 |   5.84 |      675614 |      895789 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                           | 30 |   0.0580431 |  0.00718233 |  12.37 |   0.0549677 |   0.0954331 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                               | 30 |   0.0562716 |  0.00144268 |   2.56 |   0.0543798 |   0.0597459 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                   | 30 |     3.82293 |     8.25765 | 216.00 |           0 |      32.768 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                              | 30 |     33733.9 |        1134 |   3.36 |     32115.1 |     34556.4 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                       | 30 |     6451.31 |     126.661 |   1.96 |     6168.08 |     6664.34 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                         | 30 |     23360.3 |     74.4974 |   0.32 |     23187.5 |     23526.1 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                          | 30 |  0.00205518 | 3.98087e-05 |   1.94 |  0.00195673 |   0.0021263 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                              | 30 |  0.00170032 | 1.84482e-05 |   1.08 |  0.00166198 |  0.00173623 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                  | 30 |     1.09227 |     4.15675 | 380.56 |           0 |      16.384 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                             | 30 |     34615.9 |      27.036 |   0.08 |     34572.7 |     34654.7 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                     | 30 |      699535 |     13355.1 |   1.91 |      677189 |      734325 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                       | 30 | 3.62623e+06 |     856.395 |   0.02 | 3.62508e+06 |  3.6282e+06 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                        | 30 |    0.223288 |  0.00562986 |   2.52 |    0.212793 |    0.236048 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                            | 30 |    0.216712 |   0.0062202 |   2.87 |    0.207027 |     0.23372 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                | 30 |     11.4688 |     10.6702 |  93.04 |     -16.384 |      32.768 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                           | 30 |     88807.1 |     113.544 |   0.13 |     88607.2 |     88967.7 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                       | 30 |     3690.05 |     147.842 |   4.01 |     3495.26 |     4136.75 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                         | 30 |     9578.41 |     60.8372 |   0.64 |     9438.32 |     9684.34 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                          | 30 |  0.00117944 | 4.73431e-05 |   4.01 |  0.00111258 |   0.0013241 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                              | 30 | 0.000744922 | 3.62083e-05 |   4.86 | 0.000697123 | 0.000860057 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                  | 30 |     1.09227 |     4.15675 | 380.56 |           0 |      16.384 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                             | 30 |     36511.5 |     10.8281 |   0.03 |     36489.7 |     36538.8 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                              | 30 |      227405 |     1553.41 |   0.68 |      226017 |      233274 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                | 30 |      855293 |     1844.03 |   0.22 |      853233 |      862469 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                 | 30 |   0.0711551 |  0.00102774 |   1.44 |   0.0703129 |   0.0752783 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                     | 30 |   0.0695834 | 0.000951224 |   1.37 |   0.0687673 |   0.0733926 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                         | 30 |     2.73067 |     8.69447 | 318.40 |     -16.384 |      32.768 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                    | 30 |       37855 |     482.901 |   1.28 |     37505.5 |     38554.1 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                              | 30 |      107313 |      1136.2 |   1.06 |      105951 |      109327 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                | 30 |      413984 |     420.548 |   0.10 |      413237 |      414887 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                 | 30 |   0.0335658 | 0.000587508 |   1.75 |   0.0329367 |   0.0347949 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                     | 30 |   0.0331181 |  0.00051381 |   1.55 |   0.0325668 |   0.0341234 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                         | 30 |     -6.5536 |     33.4944 | 511.08 |    -180.224 |      16.384 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                    | 30 |     37011.2 |     149.611 |   0.40 |     36817.4 |     37161.4 |
| RuntimePerformanceTests/testProcessColdLaunch() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration / s | 30 |     5.26651 |    0.285265 |   5.42 |     4.90985 |      6.0352 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.cycles / kC                           | 30 | 1.47346e+06 |     41102.8 |   2.79 | 1.40729e+06 | 1.59874e+06 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.instructions_retired / kI             | 30 | 2.65482e+06 |     32344.9 |   1.22 | 2.61552e+06 | 2.70389e+06 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.time / s                              | 30 |    0.562692 |   0.0337355 |   6.00 |    0.502077 |    0.627918 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                    | 30 |     2.92361 |   0.0461285 |   1.58 |     2.88168 |     3.13835 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical / kB                      | 30 |     1231.53 |     555.859 |  45.14 |     688.128 |      3997.7 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical_absolute / kB             | 30 |     92100.4 |     5085.57 |   5.52 |     88541.8 |      100781 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical_peak / kB                 | 30 |     92854.6 |     5089.85 |   5.48 |     89279.1 |      101616 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.cycles / kC                                             | 30 |      343556 |     38648.3 |  11.25 |      304497 |      450169 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.instructions_retired / kI                               | 30 |      671849 |     59509.2 |   8.86 |      627309 |      829651 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.time / s                                                | 30 |    0.124554 |   0.0181426 |  14.57 |    0.103181 |    0.169674 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                                      | 30 |     1.24323 |   0.0156092 |   1.26 |     1.21986 |      1.2864 |

## Baseline comparison

- No baseline supplied; baseline pending.
- HIGH VARIANCE 216.0%: MediaPerformanceTests/testAudioVideoFileAdmission() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 380.6%: MediaPerformanceTests/testInferenceResponseMapping() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 93.0%: MediaPerformanceTests/testRepeatedBoundedImageDecode() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 380.6%: PersistencePerformanceTests/testDurableQueueCommit() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 318.4%:
  PersistencePerformanceTests/testLargeLibraryScalarHydration() | iPhone 18 Pro
  | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical | kB
- HIGH VARIANCE 511.1%:
  PersistencePerformanceTests/testLargeOfflineQueueProjection() | iPhone 18 Pro
  | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical | kB
- HIGH VARIANCE 45.1%:
  RuntimePerformanceTests/testRepeatedAudioInsightPresentation() | iPhone 18 Pro
  | Test Scheme Action |
  com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical | kB
- UNMEASURED Hitch:
  RuntimePerformanceTests/testRepeatedAudioInsightPresentation; no exported
  samples, not qualified.
