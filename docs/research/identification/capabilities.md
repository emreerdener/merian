# Task-to-model capability matrix

Generated from [capabilities.json](capabilities.json); edit that file, then run
`make generate-identification-research`. Reviewed through 2026-10-03.

[Research index](README.md) · [Qualification rules](benchmark-contract.md) ·
[Experiments](experiments.md)

This is a research decision ledger, not live routing. Retained baseline does not
mean benchmark-qualified. Scores apply only to their linked study, configuration
and dataset; do not rank across rows from different studies. Unknown
measurements remain unknown. Product assignment and deployment are not assessed
here. Qualification is not established unless a row links an explicit
qualification record.

## photo-identification

**Photo identification** (photo).

- Primary metric: Evidence-supported outcome per scheduled observation; separate
  named precision, yield and supported rank.
- Required coverage: Species, genus/family, unresolved biology, nonbiology,
  lookalikes and cultivated subjects; subject/near-duplicate clusters kept
  together.
- Qualification: Frozen paired held-out comparison; practical effect and
  uncertainty, category guardrails, mapping and technical failures;
  task-specific latency/cost ceilings.
- Next action: Retain low after the completed reasoning screen: medium failed
  quality advancement and Gemini tied low. Establish supported references for
  actual reported regressions; four library holds remain unresolved. Investigate
  visual-evidence sufficiency before confidence calibration. No new paid run or
  production change authorized.

| Configuration                                               | Decision              | Evidence                                                                                                                                                                                                                                                                       | Cost and latency                                                                                                                                        | Limits                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [sol-confidence-photo](#sol-confidence-photo)               | retained baseline     | 45/60 supported outcomes in the frozen October validation mixture; retained after neither challenger qualified. [photo-provider-decision](experiments.md#photo-provider-decision) (validation, closed)                                                                         | Mean provider time 6.874 s; conservative validation cost $2.244005514 for 60 attempts; not app latency or invoice cost.                                 | Assistant-reviewed diagnostic mixture; no general production accuracy, confidence or superiority guarantee.                                                                                                                                                                                                                                                             |
| [gemini-photo-pro](#gemini-photo-pro)                       | inconclusive          | 49/60 versus 45/60; paired gains/losses 4/0. Superiority criterion not met. [photo-provider-decision](experiments.md#photo-provider-decision) (validation, closed)                                                                                                             | Mean provider time 16.092 s; conservative validation cost $2.076105003 for 60 attempts; different accounting basis from invoice.                        | Paired difference +6.7 pp, simultaneous interval -6.9 to +19.1 pp; mapping-dependent gains, three for one species. No equivalence or automatic model switch.                                                                                                                                                                                                            |
| [sol-evidence-photo](#sol-evidence-photo)                   | did not qualify       | 47/60 versus 45/60; paired gains/losses 5/3; failed frozen validation advancement. [photo-provider-decision](experiments.md#photo-provider-decision) (validation, closed)                                                                                                      | Mean provider time 6.018 s; conservative validation cost $2.212358520 for 60 attempts.                                                                  | Paired difference +3.3 pp, simultaneous interval -14.8 to +20.8 pp; genus gains with species losses and no abstention gain.                                                                                                                                                                                                                                             |
| [luna-evidence-photo](#luna-evidence-photo)                 | did not qualify       | Mineral wording improved, but biological/specificity failures prevented promotion. [luna-evidence-candidate](experiments.md#luna-evidence-candidate) (development, closed)                                                                                                     | No comparable current-config cost/latency estimate in this matrix; see original study.                                                                  | Exposed small development challenge set; not a universal judgment on Luna.                                                                                                                                                                                                                                                                                              |
| [sol-medium-confidence-photo](#sol-medium-confidence-photo) | insufficient evidence | 2/3 reference matches versus low 1/3, through one mapping improvement; both misidentified the butterfly. Medium did not resolve the unreferenced owner-photo inconsistency. [sol-reasoning](experiments.md#sol-reasoning) (development, closed)                                | Six calls per effort; medium mean 11.092 s versus low 6.805 s. Gemini timing from a separate study is not a matched speed comparison.                   | Only three reference cases plus three repeats of one unreferenced image; no additional demonstrated biological error corrected, no independent human validation, no qualification.                                                                                                                                                                                      |
| [tradeoff-20261003-low](#tradeoff-20261003-low)             | retained baseline     | 10/20 supported, 2/2 library and 8/18 controls. Retained as the operational recommendation; no qualification conferred. [photo-reasoning-tradeoff](experiments.md#photo-reasoning-tradeoff) (development, closed)                                                              | Mean / median / p90 provider seconds 6.732 / 6.382 / 8.148; conservative cost $0.752785002 for 20 normalized calls. No app latency or invoice claim.    | Exposed development mixture, assistant references, two clear library plants and four excluded holds; no confirmed personal-regression cases. Medium versus either comparator -5 pp, descriptive simultaneous interval -30.8 to +22.4 pp. All arms 0/2 biological abstentions and seven unsupported-specificity cases. No fresh qualification or confidence calibration. |
| [tradeoff-20261003-medium](#tradeoff-20261003-medium)       | did not qualify       | 9/20 supported, 2/2 library and 7/18 controls; zero gains and one unmapped loss versus low. Speed gate passed but quality advancement failed; no demonstrated biological correction. [photo-reasoning-tradeoff](experiments.md#photo-reasoning-tradeoff) (development, closed) | Mean / median / p90 provider seconds 10.961 / 10.925 / 13.545; conservative cost $0.868285005 for 20 normalized calls. No app latency or invoice claim. | Exposed development mixture, assistant references, two clear library plants and four excluded holds; no confirmed personal-regression cases. Medium versus either comparator -5 pp, descriptive simultaneous interval -30.8 to +22.4 pp. All arms 0/2 biological abstentions and seven unsupported-specificity cases. No fresh qualification or confidence calibration. |
| [tradeoff-20261003-gemini](#tradeoff-20261003-gemini)       | inconclusive          | 10/20 supported, 2/2 library and 8/18 controls; one mapping-dependent gain and one loss versus low. No net supported improvement or superiority established. [photo-reasoning-tradeoff](experiments.md#photo-reasoning-tradeoff) (development, closed)                         | Mean / median / p90 provider seconds 15.542 / 15.440 / 17.492; conservative cost $0.714760001 for 20 normalized calls. No app latency or invoice claim. | Exposed development mixture, assistant references, two clear library plants and four excluded holds; no confirmed personal-regression cases. Medium versus either comparator -5 pp, descriptive simultaneous interval -30.8 to +22.4 pp. All arms 0/2 biological abstentions and seven unsupported-specificity cases. No fresh qualification or confidence calibration. |

## photo-evidence-sufficiency

**Recognizing insufficient visual evidence** (photo).

- Primary metric: Supported rank or appropriate biological abstention per
  scheduled observation; retain species answers when supported.
- Required coverage: Sharp but nondiagnostic images, missing views, occlusion,
  small subjects, genus/family references, biological and nonbiological
  controls.
- Qualification: Feature claims independently assessed against exact pixels; no
  hindsight relabeling; false abstention and unsupported specificity measured
  separately.
- Next action: Use the prepared 18-case exposed screen as development only; it
  has no model results. Follow its frozen hurdle before any new validation.

| Configuration                                 | Decision              | Evidence                                                                                                                                                                                                                                                                                              | Cost and latency                                                                        | Limits                                                                                             |
| --------------------------------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| [sol-confidence-photo](#sol-confidence-photo) | insufficient evidence | All six unresolved biological cases named in each study; aggregate species results do not establish evidence sufficiency. [photo-provider-decision](experiments.md#photo-provider-decision) (validation, closed); [photo-primary-october](experiments.md#photo-primary-october) (development, closed) | See linked study-specific accounting; do not pool their repeated observations.          | Original references later received separate prospective adjudication; historical scores unchanged. |
| [sol-primary-october](#sol-primary-october)   | did not qualify       | 11/20 versus 7/20 supported outcomes; no unresolved gain and one paired species loss; advancement failed. [photo-primary-october](experiments.md#photo-primary-october) (development, closed)                                                                                                         | Mean provider time 6.36 s and conservative candidate cost $0.783563002 for 20 attempts. | Selected exposed observations; development signal only.                                            |
| [sol-feature-photo](#sol-feature-photo)       | awaiting results      | Collector and private double-coding review implemented; 18 observations and 36 calls proposed. [photo-feature-workflow](experiments.md#photo-feature-workflow) (engineering, closed)                                                                                                                  | Zero provider attempts/charges in engineering record; model latency/cost unknown.       | Provisional exposed references; synthetic software passes are not model evidence.                  |

## photo-confidence

**Calibrated confidence for photo answers** (photo).

- Primary metric: Precision and coverage at prospectively selected thresholds,
  with uncertainty; calibration error only as a supplementary measure.
- Required coverage: Final selected configuration, every supported rank and
  subject state, high-score errors, abstentions, mapping gaps and technical
  failures.
- Qualification: Separate calibration and untouched validation sets; select
  thresholds on calibration only; freeze target precision, minimum coverage and
  interval rule.
- Next action: Select a worthwhile identification configuration first. Existing
  fallback thresholds carry no new calibration guarantee.

| Configuration                                 | Decision              | Evidence                                                                                                                                                      | Cost and latency                                              | Limits                                                                                       |
| --------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [sol-confidence-photo](#sol-confidence-photo) | insufficient evidence | No eligible development cutoff; untouched validation phase did not run. [confidence-development](experiments.md#confidence-development) (calibration, closed) | Original 100 development attempts; no new collection implied. | Fallback 0.95/0.60 is not calibrated assurance; later comparisons do not qualify thresholds. |

## photo-explanation

**Photo explanation grounding** (photo).

- Primary metric: Fraction of scheduled explanations with supported visual
  claims, consistent uncertainty and useful alternatives; unassessable
  references separate.
- Required coverage: Lookalikes, unsupported specificity, missing views, correct
  and incorrect identifications, insufficient-reference controls.
- Qualification: Blinded independent review with anchored rubric, agreement
  reporting and predeclared dispute policy; correctness alone does not qualify
  explanations.
- Next action: Strengthen diagnostic references and review coverage; reuse the
  private review machinery, preserving limits of assistant-led review.

| Configuration                             | Decision              | Evidence                                                                                                                                                                           | Cost and latency                                                                                  | Limits                                                                                               |
| ----------------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| [sol-rank-september](#sol-rank-september) | insufficient evidence | Two candidate challenge explanations contradicted visible evidence despite three broader-rank gains. [sol-rank-corrected](experiments.md#sol-rank-corrected) (development, closed) | 18 total study calls include screening and comparator; not 18 independent candidate observations. | Assistant-led, exposed review with reference gaps; no independent explanation-quality qualification. |

## audio-identification

**Audio identification** (audio).

- Primary metric: Evidence-supported audible caller identification or
  appropriate unresolved/nonbiological outcome per scheduled clip.
- Required coverage: Verified synchronized callers, near-confusable calls,
  multiple/background sources, silence, machinery and environmental sounds;
  source-recording clusters.
- Qualification: Audible reference adjudication before calls; fixed DSP/context
  and paired unseen clips; source label alone is insufficient.
- Next action: Resolve disputed audible references before another quality
  comparison; preserve the demonstrated DSP and confidence-semantic fixes as
  separate engineering evidence.

| Configuration                       | Decision              | Evidence                                                                                                                                                                                                                                                                | Cost and latency                                                                                     | Limits                                                                                    |
| ----------------------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| [gemini-audio-v2](#gemini-audio-v2) | insufficient evidence | Provisional agreements and unresolved source/caller disagreements; no audible species qualification. [audio-v2-regression](experiments.md#audio-v2-regression) (development, closed); [audio-visible-caller](experiments.md#audio-visible-caller) (development, closed) | App-submission timing/accounting belongs to each source record; no paired current-provider estimate. | Source labels and visible-caller review are not independent audible species adjudication. |

## description-identification

**Identification from descriptions** (text).

- Primary metric: Most specific identification supported by the supplied text
  per scheduled description.
- Required coverage: Species/genus-only descriptions, ambiguous traits,
  insufficient context and nonbiological controls; paraphrase clusters.
- Qualification: References limited to information in the model-visible text; no
  hidden image/source-label inference; paired unseen descriptions.
- Next action: Build reviewed description-only references and audit exposure;
  current mixed pilots do not qualify this task.

| Configuration                                                       | Decision              | Evidence                                                                                                                                                                                                                                            | Cost and latency                                                                                             | Limits                                                                                                                          |
| ------------------------------------------------------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| [gemini-description-video-legacy](#gemini-description-video-legacy) | insufficient evidence | Genus-supported description overclaimed species; exploratory repeated case only. [description-video-replay](experiments.md#description-video-replay) (development, closed)                                                                          | No representative task-level latency/cost estimate.                                                          | Mixed-study record does not establish a description benchmark or model-wide capability.                                         |
| [sol-description-september](#sol-description-september)             | insufficient evidence | Both providers overclaimed species on the genus-supported description. Sol correctly rejected the nonbiological description. [matched-gemini-openai](experiments.md#matched-gemini-openai) (development, closed)                                    | Description median provider time 6.87 s over only two inputs; no separately reported description-only cost.  | Two reused provisional description cases; no independent reference review, representative latency or general superiority claim. |
| [gemini-description-september](#gemini-description-september)       | insufficient evidence | Both providers overclaimed species on the genus-supported description. Gemini normalized the nonbiological description as biological with an unmapped identity. [matched-gemini-openai](experiments.md#matched-gemini-openai) (development, closed) | Description median provider time 17.17 s over only two inputs; no separately reported description-only cost. | Two reused provisional description cases; no independent reference review, representative latency or general superiority claim. |

## video-identification

**Video identification** (video).

- Primary metric: Supported outcome per scheduled source observation through a
  frozen frame/audio preparation pipeline.
- Required coverage: Changing views, subject selection, movement, poor frames
  and controls; all clips/frames of the same source stay in one split.
- Qualification: Evaluate the full declared pipeline; photo performance cannot
  qualify video or isolate model effect from preprocessing.
- Next action: Define approved representative video assets and
  source-cluster/reference rules before comparing models.

| Configuration                                                       | Decision              | Evidence                                                                                                                                                                                 | Cost and latency                                    | Limits                                                                    |
| ------------------------------------------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------- |
| [gemini-description-video-legacy](#gemini-description-video-legacy) | insufficient evidence | Exploratory video included an ambiguous nonbiological control receiving a biological response. [description-video-replay](experiments.md#description-video-replay) (development, closed) | No representative task-level latency/cost estimate. | A reused source and pipeline observation cannot establish video accuracy. |

## Configuration identities

These labels identify historical evaluated configurations, not interchangeable
model families. Exact frozen manifests own full request identities. A missing
prompt identity blocks future qualification until recovered or newly frozen.

### sol-confidence-photo

- Provider/model: openai / gpt-6-sol
- profile: not_applicable
- binding: openai_photo_confidence_evaluation_v1
- prompt: openai_identify_vision_confidence_v1
- schema: merian_openai_identify_v1
- preprocessing: Same prepared single-photo JPEGs within each study; high detail
  for OpenAI. No phone-pipeline accuracy claim.
- context: No reference labels or description hints; identical frozen study
  context.
- Settings/scope: Low reasoning; 8192 output tokens; inline moderation.
  Historical released configuration, not a live deployment attestation. The
  native snapshot has no profile field; its binding/prompt/schema identify the
  request.
- Evidence: [photo-provider-decision](experiments.md#photo-provider-decision),
  [photo-primary-october](experiments.md#photo-primary-october),
  [confidence-development](experiments.md#confidence-development)

### gemini-photo-pro

- Provider/model: google / gemini-2.5-pro
- profile: unknown in this register; recover from the frozen study before
  qualification
- binding: unknown in this register; recover from the frozen study before
  qualification
- prompt: identify_vision_v1
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: Same prepared JPEGs as Sol in the October comparison.
- context: No reference labels or description hints; identical frozen study
  context.
- Settings/scope: Temperature 0.1, seed 42, 8192 output and 5000 thinking
  tokens, 90 seconds. Preserved provider-native prompt/safety.
- Evidence: [photo-provider-decision](experiments.md#photo-provider-decision)

### sol-evidence-photo

- Provider/model: openai / gpt-6-sol
- profile: not_applicable
- binding: openai_photo_evidence_evaluation_v1
- prompt: openai_identify_vision_evidence_v1
- schema: merian_openai_identify_v1
- preprocessing: Same prepared single-photo JPEGs within each study; high detail
  for OpenAI. No phone-pipeline accuracy claim.
- context: No reference labels or description hints; identical frozen study
  context.
- Settings/scope: Confidence request plus evidence-limit instructions; low
  reasoning; same explanation and normalization. The native snapshot has no
  profile field; its binding/prompt/schema identify the request.
- Evidence: [photo-provider-decision](experiments.md#photo-provider-decision)

### sol-primary-october

- Provider/model: openai / gpt-6-sol
- profile: openai_photo_confidence_primary_low_v1
- binding: openai_photo_confidence_primary_evaluation_v1
- prompt: openai_identify_vision_confidence_primary_v1
- schema: merian_openai_confidence_primary_evaluation_v1
- preprocessing: Same prepared single-photo JPEGs within each study; high detail
  for OpenAI. No phone-pipeline accuracy claim.
- context: No reference labels or description hints; identical frozen study
  context.
- Settings/scope: Low reasoning; explicit primary state/rank schema; October
  confidence-derived candidate. Distinct from September primary profile.
- Evidence: [photo-primary-october](experiments.md#photo-primary-october),
  [photo-feature-workflow](experiments.md#photo-feature-workflow)

### sol-feature-photo

- Provider/model: openai / gpt-6-sol
- profile: openai_photo_feature_observation_low_v1
- binding: openai_photo_feature_observation_evaluation_v1
- prompt: openai_identify_vision_feature_observation_v1
- schema: merian_openai_feature_observation_evaluation_v1
- preprocessing: Same prepared single-photo JPEGs within each study; high detail
  for OpenAI. No phone-pipeline accuracy claim.
- context: No reference labels or description hints; identical frozen study
  context.
- Settings/scope: Primary candidate plus at most three private feature
  observations; offline implementation only.
- Evidence: [photo-feature-workflow](experiments.md#photo-feature-workflow)

### luna-evidence-photo

- Provider/model: openai / gpt-6-luna
- profile: openai_photo_luna_evidence_limits_low_v1
- binding: unknown in this register; recover from the frozen study before
  qualification
- prompt: unknown in this register; recover from the frozen study before
  qualification
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: unknown in this register; recover from the frozen study before
  qualification
- context: unknown in this register; recover from the frozen study before
  qualification
- Settings/scope: Historical evidence-limits profile. Recover complete identity
  from its frozen study before reuse; no inference from the current confidence
  prompt.
- Evidence: [luna-evidence-candidate](experiments.md#luna-evidence-candidate)

### sol-rank-september

- Provider/model: openai / gpt-6-sol
- profile: openai_photo_sol_rank_limits_low_v1
- binding: openai_sol_rank_evaluation_v1
- prompt: unknown in this register; recover from the frozen study before
  qualification
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: unknown in this register; recover from the frozen study before
  qualification
- context: unknown in this register; recover from the frozen study before
  qualification
- Settings/scope: Low reasoning and high image detail on the older photo prompt;
  corrected-reference development comparison, not the October evidence
  candidate.
- Evidence: [sol-rank-corrected](experiments.md#sol-rank-corrected)

### gemini-audio-v2

- Provider/model: google / gemini-2.5-pro
- profile: unknown in this register; recover from the frozen study before
  qualification
- binding: unknown in this register; recover from the frozen study before
  qualification
- prompt: unknown in this register; recover from the frozen study before
  qualification
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: unknown in this register; recover from the frozen study before
  qualification
- context: audio-minimal-v1; audio-only provider evidence.
- Settings/scope: Historical V2 fixed-context audio runs; full native identity
  stays in linked frozen records. No merging with ordinary-context or legacy-DSP
  results.
- Evidence: [audio-v2-regression](experiments.md#audio-v2-regression),
  [audio-visible-caller](experiments.md#audio-visible-caller)

### gemini-description-video-legacy

- Provider/model: google / gemini-2.5-pro
- profile: unknown in this register; recover from the frozen study before
  qualification
- binding: unknown in this register; recover from the frozen study before
  qualification
- prompt: unknown in this register; recover from the frozen study before
  qualification
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: unknown in this register; recover from the frozen study before
  qualification
- context: unknown in this register; recover from the frozen study before
  qualification
- Settings/scope: Historical app route in description/video replay; complete
  per-modality request identity has not been materialized into this register.
- Evidence: [description-video-replay](experiments.md#description-video-replay)

### sol-description-september

- Provider/model: openai / gpt-6-sol
- profile: unknown in this register; recover from the frozen study before
  qualification
- binding: unknown in this register; recover from the frozen study before
  qualification
- prompt: unknown in this register; recover from the frozen study before
  qualification
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: Frozen text descriptions only; no source images supplied.
- context: Same two descriptions within the September matched comparison.
- Settings/scope: Historical matched-comparison text configuration; full native
  request identity must be recovered from the frozen record. Distinct from the
  later photo configuration.
- Evidence: [matched-gemini-openai](experiments.md#matched-gemini-openai)

### gemini-description-september

- Provider/model: google / gemini-2.5-pro
- profile: unknown in this register; recover from the frozen study before
  qualification
- binding: unknown in this register; recover from the frozen study before
  qualification
- prompt: unknown in this register; recover from the frozen study before
  qualification
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: Frozen text descriptions only; no source images supplied.
- context: Same two descriptions within the September matched comparison.
- Settings/scope: Historical matched-comparison text configuration; full native
  request identity must be recovered from the frozen record. Distinct from the
  later photo configuration.
- Evidence: [matched-gemini-openai](experiments.md#matched-gemini-openai)

### sol-medium-confidence-photo

- Provider/model: openai / gpt-6-sol
- profile: not_applicable
- binding: openai_photo_sol_medium_reasoning_evaluation_v1
- prompt: openai_identify_vision_confidence_v1
- schema: unknown in this register; recover from the frozen study before
  qualification
- preprocessing: Same prepared photos as low in the September reasoning pilot;
  high image detail. Supplied photo resized to 1024-pixel long edge; no
  phone-pipeline claim.
- context: Photo-only development inputs; no reference facts or label hints.
- Settings/scope: Medium reasoning; 8192 output tokens; inline moderation;
  90-second deadline. Native reasoning snapshot has no profile field. Exact
  historical schema digest remains in the frozen private request evidence; not
  reconstructed from current source.
- Evidence: [sol-reasoning](experiments.md#sol-reasoning)

### tradeoff-20261003-low

- Provider/model: openai / gpt-6-sol
- profile: not_applicable
- binding: openai_photo_sol_low_reasoning_evaluation_v1
- prompt: openai_identify_vision_confidence_v1
- schema: merian_openai_identify_v1
- preprocessing: Same frozen single-photo bytes: 18 exposed controls plus two
  metadata-free library PNGs; one distinct subject per case. Prepared-image
  comparison, not exact historical camera/provider payloads.
- context: No description, location, month, owner guesses, reference labels or
  prior answers. Seed 20261002 balances arm order; source and native
  request/settings digests retained in the study manifest.
- Settings/scope: Low reasoning, high image detail, 8192 output tokens, inline
  moderation, 90-second deadline; native snapshot has no profile field. Low
  request parity with the confidence baseline verified; medium differs only in
  reasoning effort.
- Evidence: [photo-reasoning-tradeoff](experiments.md#photo-reasoning-tradeoff)

### tradeoff-20261003-medium

- Provider/model: openai / gpt-6-sol
- profile: not_applicable
- binding: openai_photo_sol_medium_reasoning_evaluation_v1
- prompt: openai_identify_vision_confidence_v1
- schema: merian_openai_identify_v1
- preprocessing: Same frozen single-photo bytes: 18 exposed controls plus two
  metadata-free library PNGs; one distinct subject per case. Prepared-image
  comparison, not exact historical camera/provider payloads.
- context: No description, location, month, owner guesses, reference labels or
  prior answers. Seed 20261002 balances arm order; source and native
  request/settings digests retained in the study manifest.
- Settings/scope: Medium reasoning, high image detail, 8192 output tokens,
  inline moderation, 90-second deadline; native snapshot has no profile field.
  Low request parity with the confidence baseline verified; medium differs only
  in reasoning effort.
- Evidence: [photo-reasoning-tradeoff](experiments.md#photo-reasoning-tradeoff)

### tradeoff-20261003-gemini

- Provider/model: google / gemini-2.5-pro
- profile: gemini_pro
- binding: not_applicable
- prompt: identify_vision_v1
- schema: merian_identify_v1
- preprocessing: Same frozen single-photo bytes: 18 exposed controls plus two
  metadata-free library PNGs; one distinct subject per case. Prepared-image
  comparison, not exact historical camera/provider payloads.
- context: No description, location, month, owner guesses, reference labels or
  prior answers. Seed 20261002 balances arm order; source and native
  request/settings digests retained in the study manifest.
- Settings/scope: Temperature 0.1, seed 42, 8192 output, 5000 thinking tokens;
  90-second deadline; preserved Gemini safety. Native assignment has profile and
  no separate binding field.
- Evidence: [photo-reasoning-tradeoff](experiments.md#photo-reasoning-tradeoff)
