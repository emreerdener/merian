# Matched Gemini/OpenAI comparison — completed

Recorded 27 September 2026. All sixteen assigned first attempts completed, with
sixteen normalized results, no refusals, failed requests, unknown execution,
unattempted cases, remaining reservations, retries or controller stop. Existing
benchmarks are unchanged. Production identification remains Gemini.

## Result and recommendation

OpenAI is a promising photo-provider candidate. Both configurations agreed with
all five provisional biological photo references and correctly classified the
mineral photo as non-biological. OpenAI was faster on every matched photo in
this run, with a 7.10-second median versus 15.81 seconds for Gemini (55.1%
lower). Advance OpenAI to
[photo-only integration and qualification planning](./identification-openai-photo-integration-2026-09-27.md).
This small, previously used development corpus does not authorize a production
switch or establish general accuracy; no additional paid run was started.

| Measure                                           |                Gemini 2.5 Pro |              OpenAI gpt-6-sol |
| ------------------------------------------------- | ----------------------------: | ----------------------------: |
| Requests / normalized results                     |                         8 / 8 |                         8 / 8 |
| Photo requests / normalized results               |                         6 / 6 |                         6 / 6 |
| Biological photo reference agreement              |                         5 / 5 |                         5 / 5 |
| Mineral photo control                             | Correct non-biological result | Correct non-biological result |
| Photo median provider time                        |                       15.81 s |                        7.10 s |
| Description median provider time                  |                       17.17 s |                        6.87 s |
| Normalization median, all cases                   |                       2.45 ms |                       1.06 ms |
| Rate-aware usage estimate, all eight              |     Incomplete: usage_missing |                    $0.1080852 |
| Conservative usage-accounting estimate, all eight |                    $0.2728825 |                    $0.2059650 |

The combined conservative usage-accounting estimate is **$0.4788475**, below
$0.48 and the approved $66 reservation ceiling. These figures are estimates
under the frozen rate cards, not provider invoices. Gemini's more detailed cost
report is incomplete for all eight cases because required usage fields are
missing. Its zero `knownEstimatedUsd` is not zero spending. The public report
does not expose which individual Gemini usage fields were omitted. The
experiment retains known conservative estimates with no unresolved allocation. A
percentage cost saving is unavailable and must not be inferred by mixing the two
accounting methods.

## Per-case results

| Case  | Evidence                   | Gemini                                            | OpenAI                                            | Gemini time | OpenAI time |
| ----- | -------------------------- | ------------------------------------------------- | ------------------------------------------------- | ----------: | ----------: |
| c0001 | Bison photo                | Agrees with provisional species reference         | Agrees with provisional species reference         |     17.24 s |      7.13 s |
| c0002 | Bald eagle photo           | Agrees with provisional species reference         | Agrees with provisional species reference         |     15.94 s |      5.91 s |
| c0003 | Monarch photo              | Agrees with provisional species reference         | Agrees with provisional species reference         |     16.31 s |      6.99 s |
| c0004 | Sunflower photo            | Agrees with provisional species reference         | Agrees with provisional species reference         |     14.47 s |      7.06 s |
| c0007 | Saguaro photo              | Agrees with provisional species reference         | Agrees with provisional species reference         |     15.67 s |      8.66 s |
| c0008 | Quartz photo control       | Correct non-biological result                     | Correct non-biological result                     |     11.36 s |      8.89 s |
| c0009 | Amanita description        | A. muscaria species claim exceeds genus reference | A. muscaria species claim exceeds genus reference |     15.13 s |      8.02 s |
| c0010 | Basalt description control | Normalized as biological; unmapped identity       | Correct non-biological result                     |     19.21 s |      5.72 s |

Both configurations made a species-level Amanita muscaria claim where the
reviewed description supports only the Amanita genus. This is unsupported
specificity, not proof that the species is biologically wrong. Gemini's
normalized basalt-description result was biological with an unmapped identity;
OpenAI returned non-biological. Raw provider prose is not retained, so this
comparison does not isolate the model from prompt or normalization behavior.

## Scope and interpretation

- Six identical sanitized images and two frozen descriptions, once per provider.
  No image descriptions were added. Gemini Pro is the comparator, not Flash.
- Gemini ran first, then OpenAI, using each existing complete profile. OpenAI
  retained low reasoning effort and high image detail. No provider failover or
  extra judge calls were made.
- Provider timing covers request execution; normalization is measured
  separately. These figures exclude phone capture, upload, admission, hydration,
  persistence, rendering, and GitHub validation. All six matched photos were
  faster on OpenAI; the median matched reduction was 8.36 seconds.
- Reference labels remain provisional, with zero independent reference
  reviewers. These reused development cases add no held-out qualification
  evidence.
- Cache comparability is not established. Different profile configurations,
  provider blocks, caches and rate cards prevent a causal speed/cost claim or
  statistical significance. The observed timing difference is descriptive.
- Explanation quality, audio, sampled video frames, combined media, enrichment,
  Field Chat, mobile end-to-end behavior and confidence calibration are untested
  by this comparison. OpenAI confidence scores do not inherit Gemini thresholds.
- Preserve the 22 October 2026 retention deadline for exported case material.
  The R2 experiment claim remains permanent duplicate-execution evidence.

## Execution evidence

- Experiment: `matched-gemini-openai-20260927-v1`.
- Reviewed source: `1b3661706afc057825d7b4657f1b9935de857d44`.
- Bundle SHA-256:
  `515413c0833c8d371c79a55590d57610a41425c8d73a5b550927378866237b6a`; 6,002,404
  bytes.
- Summary SHA-256:
  `7b87991b78b792251afa7a23ae72157b19de4da238b0c044ba449f6e47df0eec`.
- Window: 27 September 2026, 15:35:18.416–17:35:18.416 UTC.
- Approval: project owner authorized merge of PR #81, normal deployment to
  `qlarqavoqhkuwzmevrmf`, and exactly sixteen first attempts with a maximum $66
  allocation ($23 Gemini, $43 OpenAI).
- [Merged PR #81](https://github.com/emreerdener/merian/pull/81).
- [Production deployment](https://github.com/emreerdener/merian/actions/runs/36329750998):
  success; database already current; no Edge Function runtime changes required;
  production smoke and Ghost merge health checks passed.
- [Hosted preflight](https://github.com/emreerdener/merian/actions/runs/36330931635):
  success, zero provider requests and no storage claim.
- [Comparison run #2, attempt 1](https://github.com/emreerdener/merian/actions/runs/36331102475):
  success; complete candidate validation, both private credential bindings,
  conditional R2 claim/readback, both provider phases and summary publication.
- [Public machine-readable summary](https://media.merian.app/benchmarks/identification/results/matched-gemini-openai-20260927-v1/36331102475-1.json).
- Actions artifact: `identification-comparison-36331102475-attempt-1`, ID
  `10936105936`; archive SHA-256
  `92922e6ac3045253be54b67735be7872f257596aa61d03d2b6bd7be7a94d7a71`.

The public JSON was downloaded and its experiment, bundle and source identities
verified before this report was written. The canonical report marks
`productionQualified: false`. API credentials and account configuration remain
in GitHub; none was read back for local analysis.
