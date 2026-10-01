# OpenAI confidence assessment — development results

Activation addendum, 30 September: the owner reported a released iOS build and
fresh device scan, then explicitly requested activation on production project
`qlarqavoqhkuwzmevrmf`. The production photo builder now selects the assessed
confidence prompt. The study and historical findings below are preserved;
0.95/0.60 and `openai_unqualified_v1` remain unchanged. Deployment and the
limits of independently captured reader evidence are tracked in the
[activation record](../release-evidence/openai-confidence-activation-2026-09-30.md).

Date: 30 September 2026

Status: Development collection completed; no eligible cutoff. Held-out
collection was not started. Retain Strong at 0.95 and Possible at 0.60. No
deployment, distribution, automatic-verification qualification or
probability-calibration claim follows from this result.

## Decision

The
[frozen assessment contract](identification-openai-confidence-assessment-2026-09-30.md)
required at least 40 Strong named predictions with at least 95% observed
correctness in development before selecting one cutoff and testing it on the
held-out split. None of the 40 predeclared cutoffs from 0.61 through 1.00
passed. The best precision among cutoffs with at least 40 Strong predictions was
40/44 (90.9%) at 0.94. At 0.97, precision reached 23/24 (95.8%), but coverage
failed the minimum count. These are diagnostics, not alternative selected
cutoffs.

The runner recorded `no_development_cutoff` with `selectedCutoff: null` and
stopped after the 100 development observations. The 100 held-out observations
remain unattempted. This is the predeclared development stop, not a failed
held-out validation. Keeping 0.95 is the fallback policy; it does not qualify
0.95 as meeting the accuracy target.

## Collection and accounting

The fixed diagnostic mixture contained 20 clear observations, 20 lookalikes, 20
limited-evidence observations (10 genus-only and 10 reviewed unresolved), 20
cultivated plants and 20 nonbiological controls per split. Photos had no
description text; frozen context was empty/null. Model `gpt-6-sol`, low
reasoning, high image detail, the 8,192-token output ceiling and the revised
confidence prompt were unchanged throughout collection. The private reference
records use source-supported automated review; independent human validation is
not claimed.

All 100 development cases consumed one attempt each: 99 normalized results and
one invalid output. There were no refusals, operational failures or uncertain
executions. No case was retried, replaced or removed. Whole-study attempted
coverage is 100/200 (50.0%; 95% Wilson interval 43.1–56.9%); normalized-result
yield is 99/200 (49.5%; 42.6–56.4%) because the held-out half was deliberately
not dispatched. These intervals are reported mechanically for completeness; the
stop was protocol-driven, not a random sampling of successful dispatches. All
accuracy tables below use **development-only** denominators, not a pooled or
completed 200-case claim.

Conservative accounted cost is **$3.512790008**, within the approved **$20
cumulative cap**. Outstanding reservations are zero. The first v1 attempt was
reconciled against provider usage with a $0.03499 upper allowance; the
subsequent 99 v2 results retained numeric accounting evidence. These are
conservative accounting amounts, not invoice-exact charges. The original
manifest, first claim and first result remain byte-for-byte unchanged. The
original 200-attempt limit was never reset.

## Cutoff diagnostics

Every proportion below includes its numerator, denominator and two-sided 95%
Wilson interval. Zero denominators are not estimable. Scores were compared
before display rounding. Representative rows from the complete 40-cutoff
development search follow; no held-out score informed the search.

| Raw cutoff | Verified Strong correctness (95% interval) | Meets both rules? |
| ---------- | ------------------------------------------ | ----------------- |
| 0.61       | 55/72 (76.4%; 65.4–84.7%)                  | No                |
| 0.80       | 54/61 (88.5%; 78.2–94.3%)                  | No                |
| 0.90       | 48/54 (88.9%; 77.8–94.8%)                  | No                |
| 0.94       | 40/44 (90.9%; 78.8–96.4%)                  | No                |
| 0.95       | 33/37 (89.2%; 75.3–95.7%)                  | No                |
| 0.97       | 23/24 (95.8%; 79.8–99.3%)                  | No                |
| 0.98       | 14/14 (100.0%; 78.5–100.0%)                | No                |
| 0.99       | 5/5 (100.0%; 56.6–100.0%)                  | No                |
| 1.00       | 0/0; not estimable                         | No                |

At 0.95, the four outcomes without correctness credit comprise **three unmapped
identities and one mapped biological identification error**. All four correctly
classified the subject as biological. Do not describe all four as demonstrated
biological mistakes. Mapping failures remain in the denominator under the frozen
protocol; retrospective synonyms, inferred ranks or model adjudication cannot
turn them into credited answers in this study.

## Aggregate development results

Strong metrics in the following tables use the retained 0.95 cutoff.

| Metric                                                          | Result (95% Wilson interval) |
| --------------------------------------------------------------- | ---------------------------- |
| Named precision                                                 | 55/80 (68.8%; 57.9–77.8%)    |
| Strong precision                                                | 33/37 (89.2%; 75.3–95.7%)    |
| Strong outcomes without correctness credit                      | 4/37 (10.8%; 4.3–24.7%)      |
| Strong mapping failures                                         | 3/37 (8.1%; 2.8–21.3%)       |
| Mapped Strong errors                                            | 1/37 (2.7%; 0.5–13.8%)       |
| Strong coverage of scheduled development cases                  | 37/100 (37.0%; 28.2–46.8%)   |
| Biological named-answer coverage                                | 80/80 (100.0%; 95.4–100.0%)  |
| Correct named-answer yield on biological cases                  | 55/80 (68.8%; 57.9–77.8%)    |
| Subject accuracy, including technical outcomes                  | 98/100 (98.0%; 93.0–99.4%)   |
| Appropriate abstentions on reviewed unresolved biological cases | 0/10 (0.0%; 0.0–27.8%)       |
| Missed named answers by abstention                              | 0/70 (0.0%; 0.0–5.2%)        |
| False biological classifications on controls                    | 1/20 (5.0%; 0.9–23.6%)       |
| Unsupported specificity among named answers                     | 14/80 (17.5%; 10.7–27.3%)    |
| Mapping failures among named answers                            | 20/80 (25.0%; 16.8–35.5%)    |
| Mapped named errors                                             | 5/80 (6.2%; 2.7–13.8%)       |

The 25 named outcomes without credit comprise 20 mapping failures and five
mapped failures. Unsupported specificity overlaps those groups and must not be
added as another disjoint error total. Four mapped failures assert a species
where only a genus was supported; one is a mapped species mismatch. All ten
reviewed unresolved biological references received named assertions. The one
biological abstention occurred on a nonbiological control and was therefore not
appropriate. Of 20 controls, 18 were correctly rejected, one was incorrectly
classified as biological/unresolved, and one produced invalid output.

## Raw-score reliability

These bins describe the frozen identification-and-mapping decision, including
unverified mappings without correctness credit. They are not a biological error
rate with mapping failures removed, and do not calibrate an individual score.

| Raw-score bin | Mean model score | Verified named correctness (95% interval) |
| ------------- | ---------------- | ----------------------------------------- |
| [0.00, 0.60)  | 0.5088           | 0/8 (0.0%; 0.0–32.4%)                     |
| [0.60, 0.70)  | 0.6650           | 0/6 (0.0%; 0.0–39.0%)                     |
| [0.70, 0.80)  | 0.7480           | 1/5 (20.0%; 3.6–62.4%)                    |
| [0.80, 0.90)  | 0.8600           | 6/7 (85.7%; 48.7–97.4%)                   |
| [0.90, 0.95)  | 0.9259           | 15/17 (88.2%; 65.7–96.7%)                 |
| [0.95, 1.00]  | 0.9716           | 33/37 (89.2%; 75.3–95.7%)                 |

## Category and rank breakdowns

### Exclusive categories

| Category                 | Scheduled | Named precision (95% interval) | Strong precision (95% interval) | Mapping failures / named (95% interval) |
| ------------------------ | --------: | ------------------------------ | ------------------------------- | --------------------------------------- |
| Clear                    |        20 | 17/20 (85.0%; 64.0–94.8%)      | 10/13 (76.9%; 49.7–91.8%)       | 3/20 (15.0%; 5.2–36.0%)                 |
| Lookalikes               |        20 | 17/20 (85.0%; 64.0–94.8%)      | 8/9 (88.9%; 56.5–98.0%)         | 2/20 (10.0%; 2.8–30.1%)                 |
| Limited evidence         |        20 | 1/20 (5.0%; 0.9–23.6%)         | 0/0; not estimable              | 15/20 (75.0%; 53.1–88.8%)               |
| Indoor/cultivated plants |        20 | 20/20 (100.0%; 83.9–100.0%)    | 15/15 (100.0%; 79.6–100.0%)     | 0/20 (0.0%; 0.0–16.1%)                  |
| Nonbiological controls   |        20 | 0/0; not estimable             | 0/0; not estimable              | 0/0; not estimable                      |

The cultivated-plant subgroup returned 20/20 accepted answers, including 15/15
Strong answers. That is useful subgroup evidence, not grounds to select a
plant-only threshold retrospectively or claim general accuracy. This run has no
matched old-prompt arm, so it does not establish improvement over the released
prompt.

### Reference-supported rank

| Reference rank | Scheduled | Named precision (95% interval) | Strong precision (95% interval) |
| -------------- | --------: | ------------------------------ | ------------------------------- |
| genus          |        10 | 1/10 (10.0%; 1.8–40.4%)        | 0/0; not estimable              |
| species        |        60 | 54/60 (90.0%; 79.9–95.3%)      | 33/37 (89.2%; 75.3–95.7%)       |
| unresolved     |        30 | 0/10 (0.0%; 0.0–27.8%)         | 0/0; not estimable              |

The unresolved reference group includes ten biological cases and twenty
nonbiological controls; these remain separately visible in the category and
abstention metrics.

### Resolved returned rank

| Returned-rank group | Scheduled | Named precision (95% interval) | Strong precision (95% interval) |
| ------------------- | --------: | ------------------------------ | ------------------------------- |
| genus               |         1 | 1/1 (100.0%; 20.7–100.0%)      | 0/0; not estimable              |
| species             |        59 | 54/59 (91.5%; 81.6–96.3%)      | 33/34 (97.1%; 85.1–99.5%)       |
| unmapped            |        20 | 0/20 (0.0%; 0.0–16.1%)         | 0/3 (0.0%; 0.0–56.1%)           |
| ambiguous           |         0 | 0/0; not estimable             | 0/0; not estimable              |
| no_named_answer     |        20 | 0/0; not estimable             | 0/0; not estimable              |

All other rank groups have zero scheduled cases and not-estimable proportions in
the private report. Returned ranks came only from frozen taxonomy mappings.
Unmapped/ambiguous answers never gained a rank by name parsing or adjudication.

## Interpretation and release consequence

This run does not justify lowering the Strong cutoff. It separates three
follow-up concerns: taxonomy resolution, unsupported specificity on limited
evidence, and the single mapped error among high-scoring species answers. The
retained result projection does not contain raw returned scientific-name text;
an unmapped record therefore cannot establish whether the cause was a synonym, a
spelling variant or a different proposed taxon. Do not guess those causes or
retroactively credit the case.

The fixed mixture is intentionally diagnostic and is not an estimate of
production traffic. Sample sizes are small, Wilson intervals are broad, and the
references were reviewed through the disclosed automated method. No population
accuracy guarantee or calibrated individual percentage follows from these
results. No prompt retuning, threshold fishing, budget expansion, replacement
case or further paid collection is authorized by this outcome.

All three OpenAI display profiles keep 0.95/0.60. The prepared revised prompt
and explanatory-copy reader remain distinct from production activation. Existing
historical thresholds, saved scores, percentage headings and explanation layout
remain intact; `openai_unqualified_v1` still applies. Follow the
[reader-first release record](../release-evidence/openai-confidence-assessment-2026-09-30.md)
for owner-handled archive/upload and installed version/build verification before
any separately authorized backend activation.

## Retained evidence

The private `confidence-report.json` is the full versioned report, including all
category/rank metrics, zero groups, held-out unattempted outcomes and request
hashes. Original corpus/taxonomy/protocol/pricing/source freeze hashes and the
accounting continuation are recorded in the release evidence. Final file-byte
SHA-256 values:

| Artifact                       | SHA-256 of file bytes                                              |
| ------------------------------ | ------------------------------------------------------------------ |
| `confidence-report.json`       | `10e82d547acdf015df49ff100700dc5c77cf2817c80c038b0c33fffe8190e749` |
| `confidence-selection.json`    | `d1bc665dcd25b7cbfec8d4eb8aeb35376004a783f4699adac86758e5e4e4fcb7` |
| `confidence-continuation.json` | `0f9b94ecfc0893231c2f77f16ac35d9c772c90e275760ed9ce0105c4032fce47` |

File-byte hashes above intentionally differ from canonical JSON fingerprints
where formatting is normalized by the assessment. The report preserves both
original source identity and corrected execution identity. Independent read-only
audit confirmed the cutoff search, denominator accounting, summed costs,
continuation prefix, lack of held-out calls and preserved predecessor files.
Backend/tooling validation remains as recorded in the release evidence; this
results write-up did not change executable code or invoke additional models.
