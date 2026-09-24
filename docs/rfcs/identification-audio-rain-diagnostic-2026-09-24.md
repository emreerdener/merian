# Rain-control diagnostic and audio confidence plan

Date: 24 September 2026 (America/Chicago; evidence timestamps are UTC)\
Status: offline investigation complete; confidence correction proposed, not
implemented

The investigation found a **confidence-contract mismatch**, but did not
establish the cause of the rain identification. The audio provider schema asks
for confidence in the selected sound-source classification. A resolved animal's
score then feeds the app's species **Strong match** label. Being confident that
an animal is present and being confident in its species are different claims.

Fresh source verification found no file/preparation mix-up for rain, robin or
pig frog. Offline reproduction of the current backend processor preserved the
complete rain recording. These findings narrow the investigation; they do not
attest the historical request bytes or prove which decision Gemini made
internally.

The
[original six-audio benchmark](./identification-audio-expansion-app-benchmark-2026-09-24.md)
and its first outcomes remain unchanged. This investigation made **zero new app
submissions and zero provider calls**. The
[diagnostic record](./identification-evaluation-evidence/2026-09-24-audio-rain-diagnostic/diagnostic.json)
retains source, processing and code bindings. Gemini assignment, prompts,
thresholds, production configuration and historical records were not changed.

## Source and processing findings

The current NPS pages describe the exact recordings as
[rain](https://www.nps.gov/subjects/sound/sounds-rain.htm),
[American Robin](https://www.nps.gov/subjects/sound/sounds-american-robin.htm)
and [Pig Frog](https://www.nps.gov/subjects/sound/sounds-pigfrog.htm). Each page
still links the original MP3. A fresh download and the original preparation
recipe reproduce the MP3 hash, complete prepared WAV and PCM samples exactly.
The prepared and admitted assets agree, as do the retained simulator-inbox
staging records. All 93 files in the earlier preparation and completed-run
freezes remain unchanged.

NPS labels/transcripts are evidence from one source, not independent biological
reviews. The rain control retains the owner's pre-prediction listening review;
animal labels remain provisional. No species reference was promoted or changed
after seeing a model answer. No assistant listening review is claimed.

The diagnostic passed all six original prepared WAVs directly into the
checked-in backend processing helpers, with network and environment access
denied:

| Case    | Recording | Prepared duration | Current processed duration |
| ------- | --------- | ----------------: | -------------------------: |
| `c0019` | Robin     |        3.526531 s |                 2.300000 s |
| `c0020` | Geese     |        3.239184 s |                 3.140000 s |
| `c0021` | Coyote    |        9.926531 s |                 5.260000 s |
| `c0022` | Pig frog  |        2.089796 s |                 1.620000 s |
| `c0023` | Rain      |        4.963265 s |                 4.963250 s |
| `c0024` | Chainsaw  |        5.407347 s |                 5.380000 s |

For rain, all 249 twenty-millisecond analysis windows fall below the existing
0.008 RMS trimming threshold. In that case, `trimSilence` retains the whole
input: **all 218,880 source samples remain**, then conversion produces 79,412
samples at 16 kHz. The tiny duration difference is resampling length rounding.
Source RMS is approximately -51.97 dBFS; processed RMS is -52.50 dBFS. Neither
clips nor contains only zeros. No signal-level gain normalization is applied.
The current processed WAV hash is
`12d57d18a270203f3765cddc3312666892c7c1e5169ce451b24eca0a1d005bbb`.

This rules out trimming away this prepared rain clip in this local reproduction.
The other reductions follow the existing silence-window rule; they do not prove
that biological cues were retained or removed. Quietness alone does not
establish whether a sound is biological. This audit does not propose an
amplitude rejection threshold or a processing change.

Twelve current/legacy requests were prepared offline using the existing
comparison helper. Their hashes, settings and matching within-pair non-audio
projections are retained; none was dispatched. These new preparations use
synthetic fixed context. They do not recreate the original app's live context,
iOS re-encoding or exact provider payload, and they are not another live
processing comparison.

## Contract finding

The trace covers installed app source `fdfb142b6fcb96e6ae8f3c46a561015064c93cd2`
and backend source baseline `6b961a4e702fc06ec91cad624790cd36b52f2f2c`. The
inspected files have no relevant drift at diagnostic checkout `dfb1408e9`;
unrelated working-tree edits are outside this inspection. The prior observed
backend bundle was
`a5939b36fd43dcf1fbfb7f5ee01875d3888a313e66af8756e79fb04f19694b2c`. No new
hosted deployment inspection is claimed.

1. [`merianAudioModelContract`](../../services/supabase/functions/_shared/identify/contract.ts)
   defines `confidence_score` as confidence in the audio subject classification.
   The shared
   [audio instruction](../../services/supabase/functions/_shared/identify/audioSubjectPolicy.ts)
   similarly separates animal presence from uncertainty about species, but does
   not clearly assign a distinct meaning to the numeric score for a named
   animal.
2. [`SpeciesData` mapping](../../apps/ios/Merian/Core/AI/Models/SpeciesData+EdgeResponse.swift)
   copies the returned score. The
   [badge presentation](../../apps/ios/Merian/Features/Insights/IdentificationReview/Confidence/Models/ConfidenceReviewPresentation.swift)
   labels it Strong at the
   [Pro threshold of 0.85](../../apps/ios/Merian/Core/AI/Inference/Result/InferenceConfidencePolicy.swift).
   That mapping is not a second acoustic check or a calibrated probability.
3. The instruction already assigns weather and indeterminate sound to
   `no_confident_biological_source`. The structured normalizer turns that state
   into non-biological **No Wildlife Detected**, clearing taxonomy even when the
   provider supplies a conflicting name. No inspected branch turns that state
   into a named animal.

The rain result remains a disagreement with a source/owner-reviewed control. Its
numerical confidence, raw discriminator and actual inference bytes were not
recorded, so this audit cannot assign its cause to the score mismatch, live
context, native preparation or the provider. Fixing the score contract alone
does not establish that Gemini will reject rain correctly.

## Recommended next implementation slice

**Clarify audio confidence using the existing result states and field.** The
present UI does not require a second numeric presence score. Keep source
detection in the private discriminator and define the public score according to
the returned identity:

| Result state                   | Meaning of `confidence_score`                                                                | Existing presentation to preserve                                                            |
| ------------------------------ | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Identified non-human animal    | Confidence in the returned taxon from diagnostic acoustic evidence, not just animal presence | Existing species-match bands                                                                 |
| Unidentified non-human animal  | Confidence in non-human animal presence; taxonomy remains unresolved                         | Unidentified Wildlife; no species-match badge                                                |
| Human only                     | Confidence in the returned Human identity                                                    | Current Human presentation, including its existing confidence badge; no sex/gender inference |
| No confident biological source | Confidence in that source-classification decision, not species identity                      | No wildlife detected; no species-match badge                                                 |

Human needs an explicit definition: it is currently a resolved biological
identity and does **not** share unresolved-wildlife badge suppression. Preserve
that behavior in this slice. Separate presence and taxon numeric fields become
useful only if a future product or model needs to expose or independently
calibrate both estimates.

Implementation should:

1. Align the shared audio instruction, executable audio schema and both primary
   and compatibility bioacoustic prompts. Require unresolved wildlife when
   presence is clear but taxonomy is unsupported; prevent location/season or
   generic animal-presence certainty from inflating confidence in a particular
   taxon. Do not introduce unsupported numerical calibration claims.
2. Version the changed private audio prompt/schema/confidence references and
   update registry bindings, request snapshots and evaluator expectations
   together. Keep current Gemini models, generation settings and numeric
   thresholds. Mixed image/audio requests use their separate blended contract;
   this slice must not silently modify that contract or claim to repair its
   known visual wording gap.
3. Retain the public JSON shape and generated DTO compatibility. Regenerate and
   inspect the Identify DTO block even if its expected diff is empty. Preserve
   stored/replayed scores and earlier benchmark evidence; old numbers cannot be
   retroactively recalibrated or relabelled as new-contract results.
4. Add focused contract and consumer regressions for resolved animals,
   confidently present but unresolved wildlife, Human and weather/mechanical
   controls. A high presence score must not create a species badge for
   unresolved wildlife. A non-biological discriminator must clear a conflicting
   animal name. Candidate filtering must cover both sides of the primary 0.99
   cutoff and preserve the separate compatibility `/audio-spec` cutoff. Sharing,
   history and replay must retain their existing state guards. Before relying on
   conditional presence scores, prove that unresolved, Human and non-biological
   results cannot earn automatic Field trip credit solely because their score is
   high. That is an integration prerequisite, not a claim that an invalid credit
   was observed.

The canonical owners for that future change are the
[API audio subject contract](../backend-and-data/05-api-contracts.md#the-json-response-schema-from-gemini-back-to-swift),
[audio feature contract](../features-and-hardware/12-audio-listen-mode.md),
[AI architecture](../system-architecture/04-ai-engineering.md), shared provider
README, the two route READMEs and the native AI/Insight Content READMEs. This
report records the finding and proposal; it does not supersede those implemented
contracts.

Before another live comparison, freeze a new plan with exact inputs, model,
source identity, context, order, attempt count and stop conditions. Use the
existing `audio-minimal-v1` replay profile to make context comparable, retain
every outcome, and include both reviewed controls and provisional animal
examples. The original ordinary-context results remain descriptive history, not
a controlled baseline for that future change. Use the already authorized
ordinary-app billing path; deployment still requires its separately named
operation and target. Do not reactivate the consumed twelve-slot processing
experiment.

The next acceptance decision is whether the contract means what the app presents
and whether a bounded live comparison shows regressions. A prompt/fixture pass
is not proof of acoustic accuracy or confidence calibration. Species scoring
still requires independently established references; formal progress remains
**0/60 development and 0/240 held-out groups**.

## Verification and retention

The offline source and processing checks passed. The existing audio policy,
schema/parser and WAV suites passed **38 tests**, with network and environment
access denied. Those tests verify mechanics with synthetic inputs; they do not
test Gemini's recognition of the rain recording. Private diagnostic artifacts
are retained through 24 October 2026 with directory mode 0700 and file mode
0600; their freeze and source-file bindings are in the diagnostic record.
Temporary downloads/decodes were removed, and no additional media derivative was
retained.

No runtime implementation changed. Full backend/native suites, physical-device
capture and hosted operations were not run for this diagnostic. The proposed
implementation will need the complete affected surface gates and independent
cross-surface review before release preparation.

The diagnostic itself passed an independent read-only review. Markdown
formatting, 184 local link targets, JSON/privacy-key checks, public/private
record equality, all seven new frozen files and 22 inspected code hashes passed
verification.

## Implementation follow-up

The separately authorized implementation is recorded in
[audio confidence V2](./identification-audio-confidence-v2-2026-09-24.md). The
diagnostic evidence and original benchmark results above remain unchanged.
