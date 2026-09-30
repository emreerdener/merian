# Luna evidence-limit candidate versus Sol: photo results

Date: 28 September 2026, America/Chicago

Status: The approved comparison completed all eighteen requests and assistant
reviews: six Luna screening calls followed by six contemporary Luna/Sol pairs.
The mineral candidate passed its targeted evidence-limit checks and was faster
and cheaper on these paired inputs. Material biological identification and
specificity failures remain. **Retain the current Sol photo assignment for both
Free and Pro.** This completes the bounded experiment and selection report; it
does not qualify Luna or activate a new production profile.

## Scope and evidence

The
[candidate plan](identification-luna-evidence-limits-candidate-2026-09-28.md)
changed two Luna instruction lines while preserving the current explanation
format, schema, media, native moderation and low-reasoning settings. The control
was unchanged `openai_photo_sol_low_v1`; the candidate was
`openai_photo_luna_evidence_limits_low_v1`. Both returned their requested model
IDs, `gpt-6-sol` and `gpt-6-luna`, with Standard service tier.

The owner separately approved eighteen maximum requests and a $40 ceiling in the
Naturebook project, then entered the existing credential into the hidden
launcher. The run used clean source `42bc72c8f71a431afcbc05368f64ffe5f39b40c9`,
implementation digest
`3b4aa81017f14c6f2d63ee7288d8be67919515c51c00772bba13600e0dfffe9c`, plan digest
`ba4d877d35dc6312d0f5fde34eb354997a14ab5ddc01fe1a618e1e75989eb522`, and run
digest `3edf88d369fd8597b2b0c6a2d729f4dbb49f0989ebfaf1559c31fd5289a05395`. The
journal began at `2026-09-29T02:31:27.270Z`.

The private packet `2026-09-28-luna-evidence-limits-photo-v1` retains the
immutable `photo-model-run/` journal and derived
`photo-model-candidate-outcome-summary.json`. The summary contains bounded
predictions, enum ratings, measurements and artifact hashes; it contains no key,
provider prose or review-page export. Original and continuation journals remain
unchanged. No retry, replacement request or production mutation occurred.

All eighteen requests completed schema, normalization, model identity, native
moderation and billing checks. Controller state is `complete: true`, with no
terminal stop. Collection completion is separate from model qualification:
`explanationEvidenceComplete` and `productionActivationAuthorized` are both
false.

## Screening outcome

The five biological screening identifications matched their provisional
species-level references. The mineral was correctly non-biological. All six
decision-evidence and uncertainty ratings passed; grounding passed on the eagle
and mineral, with unresolved reference gaps on the other four cases.

The mineral result used a broad specimen name and treated more specific mineral
identities as tentative. It did not claim that appearance established chemistry.
This passes the criterion that stopped the original Luna screen. The new
screening median was 5.902 seconds and its six-call usage-based cost upper bound
was $0.010946106. These reused development examples do not establish held-out
accuracy or isolate prompt causality from model-run variability.

## Six paired challenges

The assistant reviewed each output against the same photograph and frozen facts.
This table summarizes the transient review; it does not rewrite saved
predictions or add factual references after observing the outputs.

| Case                     | Luna candidate                                                                                                     | Unchanged Sol control                                                                                                                         |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Viceroy (`c0101`)        | Chose monarch and contradicted the visible hindwing band.                                                          | Identified viceroy using the band; the saved taxonomy mapping is ambiguous, as described below. An alternative-species reference gap remains. |
| Hoverfly (`c0102`)       | Recognized a hoverfly but selected a genus beyond the supported family rank.                                       | Chose a wasp and described contradicted visual evidence. Its species choice also exceeded the supported rank.                                 |
| Treefrog (`c0103`)       | Chose a different treefrog genus at species level, with an unsupported claim about an unseen diagnostic feature.   | Recognized the gray-treefrog group but selected a species despite acknowledging that the pair could not be separated.                         |
| Lichen (`c0104`)         | Selected a species where only the genus was supported.                                                             | Selected a species where only the genus was supported.                                                                                        |
| Pine bark (`c0105`)      | Selected a pine species despite missing distinguishing needles, cones and locality.                                | Selected a different pine species with the same evidence limitation.                                                                          |
| Dendritic rock (`c0106`) | Correctly non-biological, with a broad rock description and explicit composition limits; all three ratings passed. | Correctly non-biological, but the result name assigned chemical composition that the supplied evidence did not establish.                     |

Both profiles supplied specific decision reasons on all six challenges. That
criterion measures whether a reason is supplied; a pass cannot cancel a wrong
identification, a grounding failure or unsupported specificity.

| Challenge review count                               | Luna, out of 6 | Sol, out of 6 |
| ---------------------------------------------------- | -------------- | ------------- |
| Results with at least one actual explanation failure | 5              | 5             |
| Grounding failures                                   | 2              | 1             |
| Unsupported-specificity ratings                      | 4              | 5             |
| Results with a reference gap                         | 3              | 5             |
| Results passing all three explanation criteria       | 1              | 0             |

Counts overlap: a result can have both a reference gap and an observed failure.
Missing comparison references stay unassessable, not failed or passed. No
general accuracy ranking follows from these six deliberately difficult cases.
Luna's better mineral wording and Sol's viceroy result are specific observed
strengths; neither establishes a universal Free/Pro quality advantage.

## Timing and cost on identical challenge inputs

| Measurement                                | Luna candidate  | Sol control      |
| ------------------------------------------ | --------------- | ---------------- |
| Completed challenge calls                  | 6               | 6                |
| Median provider duration                   | 6.878 s         | 9.507 s          |
| Minimum / maximum provider duration        | 5.845 / 7.741 s | 7.654 / 13.075 s |
| Median local normalization duration        | 2.140 ms        | 2.914 ms         |
| Input tokens                               | 29,442          | 28,572           |
| Output tokens, including reasoning         | 4,270           | 2,656            |
| Reasoning tokens, already included above   | 1,592           | 724              |
| Cached / cache-write input tokens          | 24,306 / 5,118  | 19,530 / 9,024   |
| Usage-based cost upper bound, six calls    | $0.011619306    | $0.200970002     |
| Mean usage-based cost upper bound per call | $0.001936551    | $0.033495000     |

Luna was faster in all six pairs. The ratio of provider medians was **1.38**;
Luna's median duration was **27.7% shorter**. This measures the provider call,
including its native moderation configuration, not camera preparation, upload,
backend orchestration, UI rendering or time spent reviewing these results. It
does not substantiate a mobile marketing speed claim or a comparison with
Gemini.

Using the same frozen conservative pricing method, Luna's paired usage-cost
upper bound was **94.2% lower**. The method applies the reviewed ceiling tariff
and 10% regional premium without assuming cache discounts. These are comparable
usage-based upper estimates, not invoice totals or a measured 94.2% billing
reduction. The eighteen-call total was **$0.223535414**, including the screen.
The controller's $39.0071088 full-context reservation was a spending bound, not
the cost incurred.

For scale only, multiplying the paired means by 1,000 gives approximately $1.94
for Luna and $33.50 for Sol under this same upper-estimate method. This is not
an account or monthly cost forecast: production input mix, cache behavior and
invoice pricing were not measured. No change to scan limits or billing follows
from this failed selection candidate.

The pilot's median latency targets of eight seconds for Free and fifteen for Pro
were met on these challenge calls. The modeled cost reduction exceeds the 50%
target, but an actual invoice saving and cost per quality-qualified usable
result are not established. Material Free quality failures block activation
under the predeclared selection rule.

## Taxonomy and review limitations

Three named challenge predictions per profile have a null taxonomy mapping in
the retained machine journal. Null does not mean a wrong identification or a
valid abstention. The canonical name for viceroy occurs twice in the frozen
catalog, under `col-6qb84` and `species-limenitis-archippus`. The resolver
therefore marks the displayed correct Sol identification ambiguous. Other
displayed names were outside this finite catalog. The result journal does not
retain their original names or distinguish unmapped from ambiguous cases.

Do not report the machine's zero exact named matches as zero accuracy, silently
change those predictions, or enlarge the frozen catalog to improve these scores.
The table above records the assistant's contemporaneous review separately. A
future packet needs an offline catalog audit that merges canonical identity
duplicates, updates its reference IDs consistently, and retains mapping
disposition in bounded result records. This preparation needs no new model
calls.

The reviewer was the assistant, with explicit owner delegation. There was no
independent human adjudication or model blinding. Inputs and rank limits were
frozen before the candidate outputs; the screen was reused, the challenge had
one attempt per profile, and twelve of eighteen outputs had reference gaps.
Model-reported scores in this small pilot do not establish calibrated confidence
or new badge thresholds. No challenge score reached the provisional 0.95 Strong
cutoff; several lower-score results still made unsupported specific claims.

## Decision and next scoped work

Keep Sol for both tiers, preserve the current explanation format and existing
badge labels, and close this paid experiment. The candidate improves the
observed mineral behavior but does not pass the Free model selection rule. These
results also identify limitations in the current Sol control; retaining it is
continuity, not a claim that it passed every difficult case.

The next useful implementation is an offline plan for consistent biological rank
limits: when visible evidence supports only family or genus, the displayed
primary name and explanation should both stay at that rank. A disclaimer should
not accompany a more specific, unsupported primary name. Keep provider-specific
candidate versions separate so this can be evaluated for Luna and Sol without
silently changing either production profile. Preserve explanation length and
structure. Address the catalog collision and missing mapping disposition in the
same preparation milestone; do not reinterpret this completed run.

Another paid comparison, Sol-medium experiment or production activation needs
its own bounded scope and authorization. The remaining approved ceiling is not
permission for additional calls. Audio evaluation remains a subsequent
milestone.

## Verification

After the launcher released its lock, the audit acquired the original,
continuation and candidate locks and verified all eighteen claims, results and
reviews with the checked-in parsers and scoring helpers. It recomputed request,
assignment, result/review, fact/rubric and approval/source bindings, checked
each claim against the approved window, and recomputed every cost and
reservation. The sixteen copied input/media files and all twenty-four previous
journal artifacts retained their byte hashes. The summary includes hashes for
all fifty-six current journal artifacts. The audit made no network requests and
recovered no credential.

The candidate implementation's full deterministic gates are retained in the
[candidate record](identification-luna-evidence-limits-candidate-2026-09-28.md#verification).
This reporting change edits Markdown only. Changed Markdown formatting, the
recursive functions/scripts formatting gate, local document links and diff
whitespace checks are the relevant verification; runtime, database and iOS
suites are not repeated for these results documents.
