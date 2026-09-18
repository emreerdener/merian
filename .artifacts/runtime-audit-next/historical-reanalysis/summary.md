> Historical sample reanalysis only, with current metric reporting expectations.
> No new runtime execution; original evidence is unchanged.

# iOS runtime audit

Source commit: `c1a426cd425add1acc5bfb39e2cbc9069049846a` Working tree dirty:
`True` Source fingerprint:
`1aa5f368f813d99eb0f783cea079e4c9b0010e7ce31a6c327d01e6b19b150c79`

Hardware-dependent measurements are report-only. Behavioral failures fail the
run.

- build: passed;
- acceptance: passed;
- ui: passed;
- performance: passed;

## Measurements

| Metric                                                                                                                                                                                   |  n |        Mean |          SD |      CV % |         Min |         Max |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -: | ----------: | ----------: | --------: | ----------: | ----------: |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                        | 30 |      237084 |     54229.7 |     22.87 |      199165 |      423318 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                          | 30 |      703814 |     76496.1 |     10.87 |      677090 |      974745 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                           | 30 |   0.0769719 |    0.017573 |     22.83 |   0.0641671 |    0.137068 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                               | 30 |   0.0710976 |  0.00408615 |      5.75 |   0.0637773 |   0.0804172 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                   | 30 |    0.546133 |     6.78037 |   1241.52 |     -16.384 |      16.384 |
| MediaPerformanceTests/testAudioVideoFileAdmission() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                              | 30 |     33610.4 |     1058.98 |      3.15 |     32115.1 |     34359.7 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                       | 30 |      7616.5 |     348.546 |      4.58 |     7107.97 |     8330.92 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                         | 30 |     23459.8 |     178.358 |      0.76 |     23308.7 |     24305.3 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                          | 30 |  0.00248028 | 0.000113379 |      4.57 |  0.00231256 |    0.002706 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                              | 30 |  0.00186848 | 5.84472e-05 |      3.13 |  0.00176337 |  0.00198776 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                  | 30 |      1.6384 |     4.99923 |    305.13 |           0 |      16.384 |
| MediaPerformanceTests/testInferenceResponseMapping() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                             | 30 |     34417.6 |     27.4607 |      0.08 |     34376.1 |     34441.7 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                     | 30 |      745743 |       13474 |      1.81 |      711395 |      763266 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                       | 30 | 3.62731e+06 |     1349.46 |      0.04 | 3.62555e+06 | 3.63013e+06 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                        | 30 |    0.240322 |  0.00658765 |      2.74 |    0.224251 |    0.248224 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                            | 30 |    0.235112 |  0.00763178 |      3.25 |    0.217982 |    0.249451 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                | 30 |     174.763 |     572.403 |    327.53 |     -49.152 |     2899.97 |
| MediaPerformanceTests/testRepeatedBoundedImageDecode() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                           | 30 |       91386 |     2333.71 |      2.55 |       88427 |       93719 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                                       | 30 |     5609.84 |     801.802 |     14.29 |     4181.99 |      7495.2 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                         | 30 |     9691.56 |     83.9444 |      0.87 |     9440.92 |     9823.64 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                          | 30 |  0.00180869 | 0.000263879 |     14.59 |  0.00135936 |  0.00243245 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                              | 30 |  0.00111846 | 0.000183898 |     16.44 | 0.000849971 |  0.00144045 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                                  | 30 |     2.18453 |      5.6647 |    259.31 |           0 |      16.384 |
| PersistencePerformanceTests/testDurableQueueCommit() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                             | 30 |     40929.2 |     18.9919 |      0.05 |       40897 |     40962.5 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                              | 30 |      246357 |      2663.3 |      1.08 |      242248 |      252968 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                | 30 |      854432 |     706.783 |      0.08 |      853247 |      856761 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                 | 30 |   0.0785438 |  0.00126461 |      1.61 |   0.0768132 |   0.0820196 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                     | 30 |   0.0765096 |  0.00123587 |      1.62 |   0.0749263 |   0.0802131 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                         | 30 |           0 |     7.45241 | undefined |     -16.384 |      16.384 |
| PersistencePerformanceTests/testLargeLibraryScalarHydration() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                    | 30 |     42092.5 |     116.528 |      0.28 |     42011.1 |       42306 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.cycles / kC                                              | 30 |      116591 |     1152.19 |      0.99 |      114994 |      119054 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.instructions_retired / kI                                | 30 |      416108 |     186.021 |      0.04 |      415759 |      416335 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU.time / s                                                 | 30 |   0.0368964 |  0.00053128 |      1.44 |   0.0360745 |   0.0380375 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                     | 30 |   0.0363405 | 0.000551389 |      1.52 |   0.0355026 |   0.0375042 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical / kB                                         | 30 |           0 |     6.08486 | undefined |     -16.384 |      16.384 |
| PersistencePerformanceTests/testLargeOfflineQueueProjection() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory.physical_peak / kB                                    | 30 |     41400.5 |      161.79 |      0.39 |     41273.8 |     41650.6 |
| RuntimePerformanceTests/testProcessColdLaunch() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration / s | 30 |     7.36025 |     2.04527 |     27.79 |     6.15664 |      17.599 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.cycles / kC                           | 30 |  1.8648e+06 |     92408.3 |      4.96 | 1.76638e+06 |  2.1362e+06 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.instructions_retired / kI             | 30 | 2.69431e+06 |     60003.7 |      2.23 | 2.63329e+06 | 2.87813e+06 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.time / s                              | 30 |    0.633942 |   0.0301433 |      4.75 |    0.587552 |    0.723243 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                    | 30 |     2.95968 |   0.0367815 |      1.24 |     2.91933 |     3.05699 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical / kB                      | 30 |     1736.16 |     2283.56 |    131.53 |     868.352 |     12550.2 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical_absolute / kB             | 30 |     98592.9 |     2012.95 |      2.04 |       92474 |      101158 |
| RuntimePerformanceTests/testRepeatedAudioInsightPresentation() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical_peak / kB                 | 30 |     99384.2 |     2008.39 |      2.02 |     93309.6 |      101829 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.cycles / kC                                             | 30 |      475161 |     85149.7 |     17.92 |      383184 |      693976 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.instructions_retired / kI                               | 30 |      729270 |      137883 |     18.91 |      629883 | 1.17927e+06 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_CPU-app.merian.Merian.time / s                                                | 30 |    0.156177 |   0.0294283 |     18.84 |    0.122936 |     0.23035 |
| RuntimePerformanceTests/testWarmForeground() / iPhone 18 Pro / Test Scheme Action / com.apple.dt.XCTMetric_Clock.time.monotonic / s                                                      | 30 |     1.29628 |   0.0476924 |      3.68 |     1.23425 |      1.4872 |

## Baseline comparison

- No baseline supplied; baseline pending.
- HIGH VARIANCE 22.9%: MediaPerformanceTests/testAudioVideoFileAdmission() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_CPU.cycles | kC
- HIGH VARIANCE 22.8%: MediaPerformanceTests/testAudioVideoFileAdmission() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_CPU.time | s
- HIGH VARIANCE 1241.5%: MediaPerformanceTests/testAudioVideoFileAdmission() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 305.1%: MediaPerformanceTests/testInferenceResponseMapping() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 327.5%: MediaPerformanceTests/testRepeatedBoundedImageDecode() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- HIGH VARIANCE 16.4%: PersistencePerformanceTests/testDurableQueueCommit() |
  iPhone 18 Pro | Test Scheme Action |
  com.apple.dt.XCTMetric_Clock.time.monotonic | s
- HIGH VARIANCE 259.3%: PersistencePerformanceTests/testDurableQueueCommit() |
  iPhone 18 Pro | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical |
  kB
- UNDEFINED CV (zero mean; inspect raw samples and SD):
  PersistencePerformanceTests/testLargeLibraryScalarHydration() | iPhone 18 Pro
  | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical | kB
- UNDEFINED CV (zero mean; inspect raw samples and SD):
  PersistencePerformanceTests/testLargeOfflineQueueProjection() | iPhone 18 Pro
  | Test Scheme Action | com.apple.dt.XCTMetric_Memory.physical | kB
- HIGH VARIANCE 27.8%: RuntimePerformanceTests/testProcessColdLaunch() | iPhone
  18 Pro | Test Scheme Action |
  com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration
  | s
- HIGH VARIANCE 131.5%:
  RuntimePerformanceTests/testRepeatedAudioInsightPresentation() | iPhone 18 Pro
  | Test Scheme Action |
  com.apple.dt.XCTMetric_Memory-app.merian.Merian.physical | kB
- HIGH VARIANCE 17.9%: RuntimePerformanceTests/testWarmForeground() | iPhone 18
  Pro | Test Scheme Action | com.apple.dt.XCTMetric_CPU-app.merian.Merian.cycles
  | kC
- HIGH VARIANCE 18.9%: RuntimePerformanceTests/testWarmForeground() | iPhone 18
  Pro | Test Scheme Action |
  com.apple.dt.XCTMetric_CPU-app.merian.Merian.instructions_retired | kI
- HIGH VARIANCE 18.8%: RuntimePerformanceTests/testWarmForeground() | iPhone 18
  Pro | Test Scheme Action | com.apple.dt.XCTMetric_CPU-app.merian.Merian.time |
  s
- UNMEASURED Hitch:
  RuntimePerformanceTests/testRepeatedAudioInsightPresentation; no exported
  samples, not qualified.
