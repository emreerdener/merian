# Naturebook Identification Evaluation Readiness — PRD

Document ID: NB-PRD-IDENTIFICATION-EVAL-001\
Version: 0.16\
Date: 23 September 2026\
Status: Slices 1–3 implemented; photo, description, first video and expanded
audio app checks completed; reviewed baseline pending\
Suggested owners: Product and Backend, with a biological reference reviewer\
Companion: [Evaluation Readiness SRD](../rfcs/identification-evaluation-srd.md)

Slices 1–3 now have offline contracts, validation, prepared synthetic media,
shared request/normalization rules, a guarded runner and reproducible reports,
described in the
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md).
The production handler and evaluation tooling use the same identification rules.
The
[Slice 4 collection packet](../development-guides/20-identification-evaluation-pilot.md)
now supplies a proposed 60-slot coverage plan and blank
intake/independent-review forms. The formal corpus remains at 0/60 development
and 0/240 held-out groups; full coverage and independent reference reviewers are
still needed. No paid direct-evaluator run has occurred; that evaluator remains
scripts-only.

Owner clarification on 22 September: this is a solo project without two
reference reviewers. The collection guide now supports both
[solo phone/computer checks](../development-guides/20-identification-evaluation-pilot.md#start-here-when-you-are-working-alone)
and an automated exploratory run with one to twelve observation groups. This
separately versioned mode preserves provisional or unknown references, measures
both existing Gemini profiles once per group, and reports reference agreement,
failures, timing and estimated cost. It can supply development feedback before
an independently reviewed accuracy baseline is available. Live execution retains
project/key readiness, eligible media, current pricing and explicit spend
controls. The direct evaluator has not run live. A later
[production-app checkpoint](../rfcs/identification-production-app-benchmark-2026-09-22.md)
used the owner's approved ordinary production charges for two photo submissions.
Both returned visible outcomes and app timings; one reference is provisional and
the other unverified. Exact model, provider-only timing and billed cost were not
observed. This operational evidence does not complete the reviewed baseline or
change the direct evaluator's controls.

Later
[live capture verification](../rfcs/identification-timing-capture-verification-2026-09-22.md)
completed both recorder windows and measured provider/Edge timing on one repeat,
preserving the other repeat's missing spans. The subsequent
[six-photo packet](../rfcs/identification-source-photo-pilot-2026-09-22.md)
passed offline preflight with five source-backed provisional species references
and one non-biological control. Its frozen app plan allows six sequential first
submissions through the ordinary workflow. Preparation made no new model calls;
automated eligibility review does not establish independent biological accuracy.

The
[six-photo app benchmark](../rfcs/identification-source-photo-app-benchmark-2026-09-22.md)
then completed all six first submissions and measurement windows. Five species
results agreed with provisional references and the control was non-biological.
Every response retained Gemini 2.5 Pro identity and valid provider/Edge timing.
This is the first expanded source-backed photo benchmark; it supplies no formal
accuracy, repeatability or provider-comparison qualification.

The subsequent
[two-description benchmark](../rfcs/identification-description-app-benchmark-2026-09-22.md)
retained one provisional genus agreement with a more specific species answer,
and one Strong biological answer on an ambiguous description of a non-biological
source. Both measurement windows completed. That build omitted Describe's
tap-to-render clock and had no controlled audio/video import path. Those limits
and the first mismatch remain in the frozen evidence; they do not establish
verified accuracy or justify a provider switch.

The subsequent implementation forwards Describe's tap clock and adds an
interactive Debug simulator replay path for reviewed audio and short video
files. Replay uses existing media preparation and manual Identify, including
normal admission, queueing and Gemini selection. The
[measurement guide](../development-guides/21-identification-app-measurement.md#controlled-audio-and-video-replay-in-the-simulator)
defines its limits. The
[controlled replay benchmark](../rfcs/identification-replay-app-benchmark-2026-09-22.md)
then verified Describe's first-render metric on one repeat and recorded the
first video result, each with a completed measurement window. Both agreed at
their provisional genus reference rank. The video's retained audio track is
digitally silent, so meaningful audio/video fusion remains untested.
Infrastructure tests and repeated inputs do not increase independent benchmark
coverage.

After the owner's listening review, the
[first audio benchmark](../rfcs/identification-audio-app-benchmark-2026-09-22.md)
completed the remaining planned submission and all six expected measurements. It
returned Wood Thrush with a Strong match against the source's provisional
Northern Cardinal label. Preserve that disagreement for independent reference
review; the listening confirmation establishes media eligibility, not species
accuracy. All three planned Describe/video/audio submissions are now recorded,
with no manual retries or provider change.

The
[audio reference review](../rfcs/identification-audio-reference-review-2026-09-22.md)
then verified the source link and reproduced the prepared clip exactly. One
local BirdNET diagnostic favored Pyrrhuloxia in the three complete windows,
leaving a source/model disagreement and unresolved species identity. Preserve
the case for development review without promoting any model answer to ground
truth. This added no app submissions, paid provider calls or formal reviewed
groups. Gemini remains unchanged.

The
[six-audio preparation](../rfcs/identification-audio-six-preparation-2026-09-22.md)
was followed by owner listening review, admission and canonical offline
preflight. The
[six-audio app benchmark](../rfcs/identification-audio-six-app-benchmark-2026-09-22.md)
retains one first result per clip: raven → American Crow, elk → Red Fox, and
tree frog → Snow Goose, all displayed as Strong matches. Stream, thunder and car
alarm each returned No wildlife detected. Animal references remain provisional;
these disagreements do not establish independently verified error rates. The
controls had source and owner confirmation of no audible animals. No retries,
provider changes or direct-evaluator dispatch occurred.

The
[audio-path verification](../rfcs/identification-audio-path-verification-2026-09-22.md)
then confirmed sample preservation through the tested native replay path and
exact processed-audio handoff to the provider boundary. Local reprocessing of
the six frozen clips documented trimming and conversion to 16 kHz. A synthetic
test demonstrated aliasing in the existing downsampler. Correct that processing
defect and validate the audio representation before comparing providers or
tuning confidence. This finding does not establish the cause of the species
disagreements or retrospectively attest historical request bytes/context.

## 1. Outcome

Establish a trustworthy baseline for how well Gemini identifies Naturebook
observations, how often it is uncertain or confidently wrong, and what each
identification costs and takes to complete. Make the same measurement reusable
when we consider a different model, provider, or identification approach.

The [provider-flexibility foundation](./03-identification-foundation-prd.md)
created the interface for future changes. This milestone supplies the evidence
for deciding whether a change is worthwhile. **Gemini remains the only live
provider, with the existing prompts, models, and confidence rules.**

The existing local adapter benchmark measures infrastructure overhead. Simulator
and contract tests establish working flows. Neither establishes biological
identification accuracy. This plan adds that missing measurement without
claiming to replace release verification.

## 2. Recommended scope

| Decision             | Recommendation                                                                                                                                                                                                                                                                  |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First models         | Evaluate the current Gemini Flash/free and Pro/Pro identification profiles separately. Preserve the complete settings of each profile.                                                                                                                                          |
| First path           | The primary `identify-multimodal` path across its real input combinations. Compatibility endpoints retain regression coverage; their different prompts are not represented by this baseline.                                                                                    |
| Starting dataset     | One to twelve eligible exploratory groups for the solo owner; the formal pilot remains 60 independently reviewed groups, ten per input group.                                                                                                                                   |
| Reference baseline   | Add 240 held-out observation groups, forty per input group: 300 total, including the pilot.                                                                                                                                                                                     |
| Scored result        | The model answer after the same contract validation and identification rules used by the backend, before dictionary hydration and persistence.                                                                                                                                  |
| Evaluation operation | A developer tool with an offline default and an explicitly requested, bounded Gemini run. No deployed evaluation endpoint or production observation export.                                                                                                                     |
| Next action          | Trace audio from the frozen replay file through app preparation and backend request construction before changing a model or confidence policy. Preserve the three Strong source disagreements; independent species review and meaningful paired audio/visual tests remain open. |

The numbers are a practical starting scope, not a guarantee that a small quality
difference can be established statistically. Report sample counts and
uncertainty; expand with fresh independently reviewed examples when evidence is
inconclusive. Balanced input groups provide diagnostic coverage, not an estimate
of the app's actual traffic mix.

## 3. What the examples cover

| Input group               | Development pilot | Held-out baseline | Evidence supplied                                                                                    |
| ------------------------- | ----------------: | ----------------: | ---------------------------------------------------------------------------------------------------- |
| Still photos              |                10 |                40 | One or more prepared images and permitted observation context.                                       |
| Descriptions              |                10 |                40 | Observable description plus the existing permitted capture context, including its no-telemetry form. |
| Audio                     |                10 |                40 | Prepared animal/environment WAV audio and permitted context.                                         |
| Sampled video frames      |                10 |                40 | Ordered snapshots, normally five from a five-second capture.                                         |
| Sampled frames with audio |                10 |                40 | The ordered snapshots and their included companion WAV audio together.                               |
| Still photos with audio   |                10 |                40 | The actual combined visual and acoustic evidence.                                                    |

Playback video is never an inference input. One observation remains one primary
call; five snapshots are not five independent examples or requests. All views,
crops, audio, and derived descriptions from one observation belong to the same
development or held-out group.

Include clear examples, difficult lookalikes, poor evidence, non-biological
subjects, and cases where a less specific answer or no identification is
appropriate. Include plants, fungi, invertebrates, and vertebrates where the
input is meaningful. Mixed-media examples must include disagreement or an
incidental organism, not just easy agreement between sound and image.

The reference answer must describe what the supplied evidence can support.
Knowing which species was photographed does not mean a blurry photo or generic
description can identify it. Reviewers may approve several answers, a broader
taxonomic rank, or an unresolved outcome.

## 4. Product requirements

| ID        | Requirement                                                                                                                                                                                                                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PRD-IE-01 | Use independently verified reference labels and record provenance, permitted evaluation use, and reviewer agreement. Gemini answers and user confirmations alone are not ground truth.                                                                                                                        |
| PRD-IE-02 | Keep the development examples separate from the held-out baseline; freeze the evidence, labels, and scoring rules before the baseline run.                                                                                                                                                                    |
| PRD-IE-03 | Preserve complete input evidence and existing Gemini behavior, including ordered frames, included audio, subject policy, confidence bands, and candidate suppression.                                                                                                                                         |
| PRD-IE-04 | Measure correctness, willingness to offer an answer, appropriate uncertainty, confidently wrong answers, and false biological identifications. Count failures explicitly.                                                                                                                                     |
| PRD-IE-05 | Measure provider/execution time and estimated usage cost separately from full app latency. Include missing usage and potentially charged failures in the report.                                                                                                                                              |
| PRD-IE-06 | Produce comparable, versioned results by model profile and input group, with counts and uncertainty. Never substitute an overall average for a failing input group.                                                                                                                                           |
| PRD-IE-07 | Keep live runs bounded, resumable without silently repeating uncertain calls, and separate from user allowances, production data, and deployed task assignment.                                                                                                                                               |
| PRD-IE-08 | Make a future comparison possible using the same evidence and report contract. Passing an evaluation does not activate a provider or satisfy its consent and release requirements.                                                                                                                            |
| PRD-IE-09 | Support a separate exploratory dataset with one eligibility reviewer and provisional or absent reference labels. Unknown references contribute to operational counts, never quality denominators. Cap a run at twelve development groups and twenty-four calls, with one call per existing profile per group. |

No personal data, raw coordinates, credentials, production response bodies, or
identifiable human media enter evaluation fixtures, prompts, logs, or reports.
Use purpose-collected or appropriately licensed material whose permission covers
sending it to the selected evaluation service. Keep approved real assets and
curation records outside Git in controlled storage. Repository examples are
synthetic. Evaluation permission does not grant future model-training rights.

## 5. What we will learn

The baseline report should answer:

1. Which input groups and biological groups does each current Gemini profile
   handle well, and where does it fail?
2. How often does it offer a useful correct answer, withhold an answer, or
   present a wrong answer with high confidence?
3. Are uncertain and non-biological observations handled appropriately?
4. What are the successful-call median and p95 times, failure rates, and
   estimated costs per attempt and correct offered answer?
5. Which follow-up has the clearest evidence: better evidence preparation,
   prompt or confidence work, a model/provider comparison, or more data?

These are measurements of the specified corpus and execution boundary. They do
not certify medical, edibility, handling, or other safety advice. Dictionary
content, full enrichment quality, hosted finalization, and device experience
keep their separate verification requirements.

## 6. Delivery in five slices

| Slice                             | Deliverable                                                                                                                                   | Completion condition                                                                                                                                         |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Define examples and scores     | Versioned case/report schemas, curation rubric, split rules, and a small synthetic fixture set. Begin collecting the 60 development examples. | Hand-worked expected scores are agreed; unapproved evidence, leaked labels, invalid media combinations, and duplicate split membership are rejected offline. |
| 2. Share the identification rules | Extract the existing post-provider normalization into a pure function used by the production route and evaluator.                             | Existing inputs produce the same normalized results and responses; Gemini, prompts, confidence, quotas, and persistence behavior remain unchanged.           |
| 3. Build the evaluator            | Offline fixture runner, deterministic scorer, reports, and guarded live runner.                                                               | Offline runs need no credentials or network; live limits, accounting, and resume behavior are proven with intercepted transport.                             |
| 4. Establish the Gemini baseline  | Run the approved pilot, resolve measurement defects, freeze the method, then run the held-out set and a small repeatability check.            | Report both profiles and every input group, including errors, uncertainty, cost gaps, and sample limitations.                                                |
| 5. Prepare the next decision      | Compare report versions using synthetic better/worse candidates, document the baseline, and prioritize one evidence-backed improvement.       | The comparison detects known regressions and rejects incompatible runs; no real second provider is required.                                                 |

Backend owns extraction, tooling, execution, and verification. Product owns the
coverage priorities and later trade-offs. A biological reference reviewer owns
label quality; Backend should not silently substitute a model-generated label
when reference expertise is unavailable. Curation can progress alongside the
first three slices and is likely the main scheduling dependency.

The exploratory runner is an implemented addition to Slice 3. Its separate
corpus, run-specification and report versions prevent provisional observations
from entering formal scores or paired qualification comparisons. Eligibility
review can be performed by the owner or an explicitly identified automated
reviewer; it establishes permitted, prepared evidence, not independent
biological truth. Missing references remain unverified. Reports state
measurement-only status, sample counts and untested input groups. They cannot
complete the formal baseline or qualify a provider switch. The two-reviewer rule
remains specific to the independently reviewed baseline.

## 7. Definition of done and later work

This milestone is complete when the reviewed corpus, repeatable tooling, frozen
Gemini baseline, and comparison procedure exist, with reproducible sanitized
reports and an explicit list of measurement limits. Gemini need not achieve an
invented accuracy target for us to complete honest measurement.

Before evaluating a real replacement, Product and Backend must freeze the exact
task/input assignment, tolerable quality and coverage changes, confidence and
failure limits, and desired cost or latency benefit. Choose those numerical
limits from the baseline and product priorities **before seeing candidate
results**. An inconclusive comparison means more evidence is needed, not
permission to switch.

OpenAI, BioCLIP, model training, automatic routing/failover, prompt
optimization, confidence recalibration, species-content evaluation, family
plans, and broad function-folder reorganization remain separate milestones.
Evaluation findings can justify one of them; this plan does not preselect the
answer. A real provider still follows the
[onboarding procedure](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).
