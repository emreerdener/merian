# Identification experiment register

Generated from [catalog.json](catalog.json); edit that source, then run
`make generate-identification-research`. Reviewed through 2026-10-01.

[Research index](README.md) · [Dataset families](datasets.md) ·
[Procedure](procedure.md)

Counts distinguish provider attempts from app submissions. Null means unknown,
not zero. Costs have different accounting bases and overlapping historical
comparators; do not sum this register or rank models across its datasets.

## exploratory-foundation

**Exploratory mechanics and two-photo app measurements** — 2026-09-22; mixed;
engineering; closed.

- Configuration: Synthetic evaluator plus existing Gemini production app path
- Data: [exploratory-photo-text](datasets.md#exploratory-photo-text)
- Attempts: unknown (unknown). Accounted USD: unknown. 24 synthetic cases are
  mechanics only; ordinary app submissions and reruns are documented separately,
  no complete provider ledger.
- Outcome: Synthetic 24/24 mechanics pass; partial two-photo app telemetry.
- Limits: Flower unverified; cat provisional; repeated timing runs overlap.
- Decision: Use as engineering evidence only.
- Production: No production change established by this study.
- Sources:
  [identification-exploratory-benchmark-2026-09-22.md](../../../docs/rfcs/identification-exploratory-benchmark-2026-09-22.md),
  [identification-production-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-production-app-benchmark-2026-09-22.md),
  [identification-measured-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-measured-app-benchmark-2026-09-22.md),
  [identification-recorder-repair-2026-09-22.md](../../../docs/rfcs/identification-recorder-repair-2026-09-22.md),
  [identification-timing-capture-verification-2026-09-22.md](../../../docs/rfcs/identification-timing-capture-verification-2026-09-22.md)

## source-photo-app

**Six-source-photo app baseline** — 2026-09-22; photo; development; closed.

- Configuration: Gemini 2.5 Pro, ordinary app context
- Data: [exploratory-photo-text](datasets.md#exploratory-photo-text)
- Attempts: 6 (app_submissions). Accounted USD: unknown. Per-result estimates
  reported; no verified total bill.
- Outcome: Five provisional biological agreements and a nonbiological mineral.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: Exploratory baseline only.
- Production: No production change established by this study.
- Sources:
  [identification-source-photo-pilot-2026-09-22.md](../../../docs/rfcs/identification-source-photo-pilot-2026-09-22.md),
  [identification-source-photo-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-source-photo-app-benchmark-2026-09-22.md)

## description-video-replay

**Description and video exploration** — 2026-09-22; mixed; development; closed.

- Configuration: Existing Gemini app route; description repeat and first video
- Data: [exploratory-photo-text](datasets.md#exploratory-photo-text)
- Attempts: 4 (app_submissions). Accounted USD: unknown. Two initial
  descriptions plus one repeated description and one video; shared
  cross-modality totals are not a study-only ledger.
- Outcome: Genus-supported description overclaimed species; ambiguous
  nonbiological control received biological response.
- Limits: Repeated description is one reused group; provisional references.
- Decision: No model or confidence qualification.
- Production: No production change established by this study.
- Sources:
  [identification-description-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-description-app-benchmark-2026-09-22.md),
  [identification-replay-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-replay-app-benchmark-2026-09-22.md)

## openai-photo-text-pilot

**First OpenAI photo/text pilot** — 2026-09-25; mixed; development; stopped.

- Configuration: gpt-6-sol evaluation adapter
- Data: [exploratory-photo-text](datasets.md#exploratory-photo-text)
- Attempts: 8 (provider_attempts). Accounted USD: 0.175790000. Known usage for
  seven calls only; one uncertain attempt retained its reservation. See original
  ledger for unresolved liability.
- Outcome: Seven normalized outputs; eighth attempt uncertain.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: Adapter demonstrated; no production assignment change.
- Production: No production change established by this study.
- Sources:
  [identification-openai-photo-text-pilot-2026-09-25.md](../../../docs/rfcs/identification-openai-photo-text-pilot-2026-09-25.md)

## concise-screen

**Concise-explanation screen** — 2026-09-26; photo; development; stopped.

- Configuration: OpenAI control; concise candidate never dispatched
- Data: [exploratory-photo-text](datasets.md#exploratory-photo-text)
- Attempts: 1 (provider_attempts). Accounted USD: 0.029460000. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports.
- Outcome: Stopped after control due insufficient explanation-reference
  coverage.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: Inconclusive; closed.
- Production: No production change established by this study.
- Sources:
  [identification-openai-concise-screen-2026-09-26.md](../../../docs/rfcs/identification-openai-concise-screen-2026-09-26.md)

## matched-gemini-openai

**Matched Gemini/OpenAI exploratory comparison** — 2026-09-27; mixed;
development; closed.

- Configuration: Gemini Pro versus gpt-6-sol; six photos and two descriptions
- Data: [exploratory-photo-text](datasets.md#exploratory-photo-text)
- Attempts: 16 (provider_attempts). Accounted USD: 0.478847500. Combined
  conservative estimate; Gemini cost method incomplete, not invoice.
- Outcome: Five provisional biological photo agreements and mineral rejection in
  each arm; OpenAI faster on selected inputs.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: Proceed to integration planning; no general provider superiority.
- Production: Platform deployment recorded separately; this experiment did not
  switch photo routing.
- Sources:
  [identification-gemini-openai-matched-comparison-2026-09-27.md](../../../docs/rfcs/identification-gemini-openai-matched-comparison-2026-09-27.md),
  [identification-gemini-openai-matched-results-2026-09-27.md](../../../docs/rfcs/identification-gemini-openai-matched-results-2026-09-27.md)

## luna-original-screen

**Original Luna screen and continuation** — 2026-09-28; photo; development;
stopped.

- Configuration: openai_photo_luna_low_v1; Sol challenge arm unattempted
- Data: [photo-difficult](datasets.md#photo-difficult)
- Attempts: 6 (provider_attempts). Accounted USD: 0.010719231. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. Historical controller held $1.7730504; spending bound differs from
  estimated usage.
- Outcome: Initial Bison screen stopped on a reference-coverage gap; its
  approved continuation reached a mineral specificity failure, leaving all 12
  challenge slots unattempted.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: No Luna promotion; original and continuation closed.
- Production: No production change established by this study.
- Sources:
  [identification-openai-free-pro-models-2026-09-28.md](../../../docs/rfcs/identification-openai-free-pro-models-2026-09-28.md),
  [identification-luna-sol-photo-preparation-2026-09-28.md](../../../docs/rfcs/identification-luna-sol-photo-preparation-2026-09-28.md),
  [identification-luna-sol-photo-screen-results-2026-09-28.md](../../../docs/rfcs/identification-luna-sol-photo-screen-results-2026-09-28.md)

## luna-evidence-candidate

**Separately approved Luna evidence-limit candidate** — 2026-09-28; photo;
development; closed.

- Configuration: openai_photo_luna_evidence_limits_low_v1 versus
  openai_photo_sol_low_v1
- Data: [photo-difficult](datasets.md#photo-difficult)
- Attempts: 18 (provider_attempts). Accounted USD: 0.223535414. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. Separate new 18-call study; excludes original six-call Luna screen.
- Outcome: Mineral wording improved; biological and specificity failures
  remained.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: Retain Sol for both tiers.
- Production: No production change established by this study.
- Sources:
  [identification-luna-evidence-limits-candidate-2026-09-28.md](../../../docs/rfcs/identification-luna-evidence-limits-candidate-2026-09-28.md),
  [identification-luna-sol-candidate-results-2026-09-28.md](../../../docs/rfcs/identification-luna-sol-candidate-results-2026-09-28.md)

## sol-rank-stopped

**First Sol rank screen and source adjudication** — 2026-09-29; photo;
development; stopped.

- Configuration: openai_photo_sol_rank_limits_low_v1
- Data: [photo-difficult](datasets.md#photo-difficult)
- Attempts: 1 (provider_attempts). Accounted USD: 0.031647001. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports.
- Outcome: Stopped screen; omitted publisher metadata made the failure
  interpretation inconclusive.
- Limits: Reference correction cannot retroactively turn the frozen run into a
  pass.
- Decision: Preserve stop; corrected-reference comparison is separate.
- Production: No production change established by this study.
- Sources:
  [identification-sol-rank-screen-results-2026-09-29.md](../../../docs/rfcs/identification-sol-rank-screen-results-2026-09-29.md)

## sol-rank-corrected

**Corrected-reference Sol rank comparison** — 2026-09-29; photo; development;
closed.

- Configuration: Sol rank-limits candidate versus unchanged Sol-low
- Data: [photo-difficult](datasets.md#photo-difficult)
- Attempts: 18 (provider_attempts). Accounted USD: 0.597531010. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. Excludes stopped predecessor.
- Outcome: Broader rank gains, but two candidate visual-grounding failures.
- Limits: Selected exposed development cases; provisional references; no
  population accuracy or calibration claim.
- Decision: Do not promote candidate.
- Production: No production change established by this study.
- Sources:
  [identification-photo-rank-consistency-2026-09-28.md](../../../docs/rfcs/identification-photo-rank-consistency-2026-09-28.md),
  [identification-sol-rank-comparison-results-2026-09-29.md](../../../docs/rfcs/identification-sol-rank-comparison-results-2026-09-29.md)

## sol-primary-september

**September explicit-primary Sol comparison** — 2026-09-29; photo; development;
closed.

- Configuration: openai_photo_sol_primary_low_v1 versus openai_photo_sol_low_v1
- Data: [photo-primary-september](datasets.md#photo-primary-september)
- Attempts: 18 (provider_attempts). Accounted USD: 0.614284005. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports.
- Outcome: All five states exercised; broader-rank improvements but fly
  visual-grounding failure.
- Limits: Assistant review, limited references and reused challenges; state
  coverage is not identification qualification.
- Decision: Retain current Sol; no candidate promotion.
- Production: No production change established by this study.
- Sources:
  [identification-sol-primary-comparison-preparation-2026-09-29.md](../../../docs/rfcs/identification-sol-primary-comparison-preparation-2026-09-29.md),
  [identification-sol-primary-comparison-results-2026-09-29.md](../../../docs/rfcs/identification-sol-primary-comparison-results-2026-09-29.md),
  [identification-primary-resolution-contract-2026-09-29.md](../../../docs/rfcs/identification-primary-resolution-contract-2026-09-29.md)

## confidence-development

**Confidence cutoff development assessment** — 2026-09-30; photo; calibration;
closed.

- Configuration: gpt-6-sol confidence photo profile; original 100/100 split
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 100 (provider_attempts). Accounted USD: 3.512790008. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. Includes original attempt plus bounded continuation; no held-out
  collection in this study.
- Outcome: 99 normalized and one invalid outcome; no eligible development
  cutoff.
- Limits: Source-grounded assistant review; no independent human validation.
  Later studies expose some original held-out cases.
- Decision: Keep 0.95/0.60 fallback; no calibrated guarantee.
- Production: Assessed prompt later activated via separate release record;
  thresholds not qualified.
- Sources:
  [identification-openai-confidence-assessment-2026-09-30.md](../../../docs/rfcs/identification-openai-confidence-assessment-2026-09-30.md),
  [identification-openai-confidence-results-2026-09-30.md](../../../docs/rfcs/identification-openai-confidence-results-2026-09-30.md),
  [openai-confidence-activation-2026-09-30.md](../../../docs/release-evidence/openai-confidence-activation-2026-09-30.md),
  [openai-confidence-assessment-2026-09-30.md](../../../docs/release-evidence/openai-confidence-assessment-2026-09-30.md)

## sol-reasoning

**Sol low/medium reasoning pilot** — 2026-09-30; photo; development; closed.

- Configuration: gpt-6-sol low versus medium; confidence prompt
- Data: [reasoning-four-photo](datasets.md#reasoning-four-photo)
- Attempts: 12 (provider_attempts). Accounted USD: 0.468209501. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports.
- Outcome: Medium did not justify promotion or resolve disputed supplied-photo
  identification.
- Limits: Repeated supplied photo has no independent reference; three reference
  cases only.
- Decision: Retain low.
- Production: No production change established by this study.
- Sources:
  [identification-sol-reasoning-pilot-2026-09-30.md](../../../docs/rfcs/identification-sol-reasoning-pilot-2026-09-30.md)

## gemini-recheck

**Gemini photo recheck with historical Sol controls** — 2026-09-30; photo;
development; closed.

- Configuration: Preserved Gemini Pro versus historical Sol low/medium
- Data: [reasoning-four-photo](datasets.md#reasoning-four-photo)
- Attempts: 6 (provider_attempts). Accounted USD: 0.217860000. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. Six new Gemini calls only; report combined $0.686069501 includes
  preceding Sol pilot.
- Outcome: Gemini matched 2/3 references versus recorded Sol-low 1/3; one output
  unmapped.
- Limits: Historical controls and repeated owner photo; no provider-wide
  superiority.
- Decision: Inform next controlled comparison; no activation.
- Production: No production change established by this study.
- Sources:
  [identification-gemini-photo-recheck-2026-09-30.md](../../../docs/rfcs/identification-gemini-photo-recheck-2026-09-30.md)

## photo-provider-decision

**Bounded photo provider decision** — 2026-10-01; photo; validation; closed.

- Configuration: Released Sol-low, Sol evidence-limit candidate, preserved
  Gemini Pro
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 220 (provider_attempts). Accounted USD: 8.023640041. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. 40 development and 180 validation calls; zero outstanding
  reservations.
- Outcome: Validation supported outcomes: 45/60 released, 49/60 Gemini, 47/60
  candidate; neither met frozen superiority.
- Limits: Selected diagnostic mixture; 60 distinct validation observations;
  assistant-reviewed references.
- Decision: Retain released Sol-low; budget closed.
- Production: No production change established by this study.
- Sources:
  [identification-photo-provider-decision-2026-10-01.md](../../../docs/rfcs/identification-photo-provider-decision-2026-10-01.md)

## calibration-gap-audit

**Calibration and mapping gap audit** — 2026-10-01; photo; audit; closed.

- Configuration: Offline inspection of existing taxonomy, normalization and
  evidence
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 0 (none). Accounted USD: 0.000000000. No provider calls.
- Outcome: No demonstrated safe alias addition; explicit-resolution and
  content-free diagnostics prepared.
- Limits: Unmapped hashes cannot reveal missing identities; software tests are
  not quality evidence.
- Decision: Investigate evidence sufficiency; do not change thresholds.
- Production: No production change established by this study.
- Sources:
  [identification-calibration-gap-audit-2026-10-01.md](../../../docs/rfcs/identification-calibration-gap-audit-2026-10-01.md)

## photo-primary-october

**Current-baseline explicit-primary development screen** — 2026-10-01; photo;
development; closed.

- Configuration: openai_photo_confidence_primary_low_v1 versus current
  confidence baseline
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 40 (provider_attempts). Accounted USD: 1.541925002. Conservative
  usage-based estimate, not invoice reconciliation; do not sum overlapping
  reports. Zero reservations and retries; separate budget closed.
- Outcome: 11/20 versus 7/20; five paired wins/one loss, genus 4/5 versus 0/5;
  abstention 0/6 in both.
- Limits: Twenty deliberately exposed cases; no confirmatory inference.
- Decision: Failed frozen screen; retain released configuration.
- Production: No production change established by this study.
- Sources:
  [identification-photo-primary-screen-2026-10-01.md](../../../docs/rfcs/identification-photo-primary-screen-2026-10-01.md)

## audio-first

**First audio app replay** — 2026-09-22; audio; development; closed.

- Configuration: Gemini 2.5 Pro, ordinary app context
- Data: [audio-first](datasets.md#audio-first)
- Attempts: 1 (app_submissions). Accounted USD: 0.029182500. Known
  primary-attempt estimates only; app submissions are not an attested complete
  provider-call ledger or total bill. Cross-modality $0.0933925 total must not
  be attributed to audio alone.
- Outcome: Strong mismatch against disputed source label.
- Limits: Independent review unresolved; no accuracy inference.
- Decision: Reference review required.
- Production: No production change established by this study.
- Sources:
  [identification-audio-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-audio-app-benchmark-2026-09-22.md),
  [identification-audio-reference-review-2026-09-22.md](../../../docs/rfcs/identification-audio-reference-review-2026-09-22.md)

## audio-six-baseline

**Six-audio exploratory baseline** — 2026-09-22; audio; development; closed.

- Configuration: Gemini 2.5 Pro ordinary app requests
- Data: [audio-six](datasets.md#audio-six)
- Attempts: 6 (app_submissions). Accounted USD: 0.148092500. Known
  primary-attempt estimates only; app submissions are not an attested complete
  provider-call ledger or total bill.
- Outcome: Three animal/source-label disagreements; three nonbiological controls
  rejected.
- Limits: Source labels and/or owner review; not independent biological
  validation.
- Decision: Exploratory regression baseline only.
- Production: No production change established by this study.
- Sources:
  [identification-audio-six-preparation-2026-09-22.md](../../../docs/rfcs/identification-audio-six-preparation-2026-09-22.md),
  [identification-audio-six-app-benchmark-2026-09-22.md](../../../docs/rfcs/identification-audio-six-app-benchmark-2026-09-22.md)

## audio-dsp-fix

**Audio path investigation and DSP correction** — 2026-09-23; audio;
engineering; closed.

- Configuration: Linear resampling/full windows to sinc resampling/partial-tail
  measurement
- Data: [audio-six](datasets.md#audio-six)
- Attempts: 0 (none). Accounted USD: 0.000000000. Offline trace and synthetic
  signal checks; deployment is separate from paid quality collection.
- Outcome: Demonstrated aliasing/tail defects corrected.
- Limits: Does not explain species errors or prove model quality.
- Decision: Retain deterministic processing correction.
- Production: Production deployment recorded 23 September.
- Sources:
  [identification-audio-path-verification-2026-09-22.md](../../../docs/rfcs/identification-audio-path-verification-2026-09-22.md),
  [identification-audio-preprocessing-fix-2026-09-23.md](../../../docs/rfcs/identification-audio-preprocessing-fix-2026-09-23.md),
  [identification-audio-preprocessing-deployment-2026-09-23.md](../../../docs/release-evidence/identification-audio-preprocessing-deployment-2026-09-23.md)

## audio-dsp-pairs

**Fixed-context DSP paired comparison** — 2026-09-23; audio; development;
closed.

- Configuration: Legacy/current processing, Gemini 2.5 Pro, audio-minimal-v1
- Data: [audio-six](datasets.md#audio-six)
- Attempts: 12 (app_submissions). Accounted USD: 0.295230000. Known
  primary-attempt estimates only; app submissions are not an attested complete
  provider-call ledger or total bill. Two execution segments; first stopped
  after seven slots, documented continuation completed the same study.
- Outcome: Controls rejected; animal/source disagreements remain unresolved.
- Limits: Six units, combined DSP changes; neither component effect isolated.
- Decision: Keep current processing; no accuracy/calibration claim.
- Production: Temporary comparison assignment removed; ordinary current
  processor preserved.
- Sources:
  [identification-audio-processing-comparison-2026-09-23.md](../../../docs/rfcs/identification-audio-processing-comparison-2026-09-23.md),
  [identification-audio-processing-comparison-completed-2026-09-23.md](../../../docs/rfcs/identification-audio-processing-comparison-completed-2026-09-23.md),
  [identification-audio-comparison-assignment-2026-09-23.md](../../../docs/rfcs/identification-audio-comparison-assignment-2026-09-23.md),
  [identification-audio-comparison-provenance-2026-09-23.md](../../../docs/rfcs/identification-audio-comparison-provenance-2026-09-23.md),
  [identification-audio-comparison-app-integration-2026-09-23.md](../../../docs/rfcs/identification-audio-comparison-app-integration-2026-09-23.md)

## audio-expanded-baseline

**Expanded ordinary-context audio baseline** — 2026-09-24; audio; development;
closed.

- Configuration: Gemini 2.5 Pro, ordinary context
- Data: [audio-expanded](datasets.md#audio-expanded)
- Attempts: 6 (app_submissions). Accounted USD: 0.142955000. Known
  primary-attempt estimates only; app submissions are not an attested complete
  provider-call ledger or total bill.
- Outcome: Two animal provisional agreements, two disagreements; rain falsely
  biological, chainsaw rejected.
- Limits: Source labels and/or owner review; not independent biological
  validation.
- Decision: Investigate rain/reference and confidence semantics.
- Production: No production change established by this study.
- Sources:
  [identification-audio-reference-expansion-2026-09-24.md](../../../docs/rfcs/identification-audio-reference-expansion-2026-09-24.md),
  [identification-audio-expansion-app-benchmark-2026-09-24.md](../../../docs/rfcs/identification-audio-expansion-app-benchmark-2026-09-24.md)

## audio-confidence-v2

**Rain diagnostic and confidence V2 implementation** — 2026-09-24; audio;
engineering; closed.

- Configuration: Audio V2 subject versus species confidence semantics
- Data: [audio-expanded](datasets.md#audio-expanded)
- Attempts: 0 (none). Accounted USD: 0.000000000. Diagnostic/implementation
  only; follow-up app calls belong to separate regression entry.
- Outcome: Found semantic mismatch between source-classification confidence and
  species Strong badge.
- Limits: Model scores remain uncalibrated; rain error cause not established.
- Decision: Separate confidence meanings.
- Production: Production V2 deployment recorded 24 September.
- Sources:
  [identification-audio-rain-diagnostic-2026-09-24.md](../../../docs/rfcs/identification-audio-rain-diagnostic-2026-09-24.md),
  [identification-audio-confidence-v2-2026-09-24.md](../../../docs/rfcs/identification-audio-confidence-v2-2026-09-24.md),
  [identification-audio-confidence-v2-deployment-2026-09-24.md](../../../docs/release-evidence/identification-audio-confidence-v2-deployment-2026-09-24.md)

## audio-v2-regression

**Audio V2 fixed-context regression and reference review** — 2026-09-24; audio;
development; closed.

- Configuration: Gemini 2.5 Pro V2, audio-minimal-v1
- Data: [audio-expanded](datasets.md#audio-expanded)
- Attempts: 6 (app_submissions). Accounted USD: 0.150650000. Known
  primary-attempt estimates only; app submissions are not an attested complete
  provider-call ledger or total bill.
- Outcome: Two provisional animal agreements, two source disagreements; controls
  retained; no numeric confidence observed.
- Limits: Different context from prior run; disputed references excluded from
  future species decisions.
- Decision: Regression evidence only; no causal quality/calibration claim.
- Production: Uses separately deployed V2.
- Sources:
  [identification-audio-confidence-v2-app-benchmark-2026-09-24.md](../../../docs/rfcs/identification-audio-confidence-v2-app-benchmark-2026-09-24.md),
  [identification-audio-disputed-reference-review-2026-09-24.md](../../../docs/rfcs/identification-audio-disputed-reference-review-2026-09-24.md)

## audio-visible-caller

**Two visible-caller audio observations** — 2026-09-24; audio; development;
closed.

- Configuration: Gemini 2.5 Pro V2, fixed context, audio-only provider evidence
- Data: [audio-visible](datasets.md#audio-visible)
- Attempts: 2 (app_submissions). Accounted USD: 0.054697500. Known
  primary-attempt estimates only; app submissions are not an attested complete
  provider-call ledger or total bill.
- Outcome: Pika/source disagreement; rooster mapped to accepted taxon.
- Limits: Caller synchronization/species not independently adjudicated.
- Decision: No accuracy/calibration qualification.
- Production: No production change established by this study.
- Sources:
  [identification-audio-visible-caller-preparation-2026-09-24.md](../../../docs/rfcs/identification-audio-visible-caller-preparation-2026-09-24.md),
  [identification-audio-visible-caller-app-benchmark-2026-09-24.md](../../../docs/rfcs/identification-audio-visible-caller-app-benchmark-2026-09-24.md)

## audio-uncertainty-design

**Species-evidence audio prompt comparison design** — 2026-09-24; audio;
development; prepared.

- Configuration: V2 control versus identify_audio_uncertainty_experiment_v1
- Data: [audio-uncertainty-proposal](datasets.md#audio-uncertainty-proposal)
- Attempts: 0 (none). Accounted USD: 0.000000000. 36 planned slots are not
  executed calls; no paid execution established by reviewed records.
- Outcome: Offline preparation and integration checks; no model results.
- Limits: Six clips x two arms x three repeats; repeats are clustered.
- Decision: Requires reviewed release/freeze and execution authorization if
  resumed.
- Production: No experiment deployment or execution established.
- Sources:
  [identification-audio-uncertainty-comparison-plan-2026-09-24.md](../../../docs/rfcs/identification-audio-uncertainty-comparison-plan-2026-09-24.md),
  [design.json](../../../docs/rfcs/identification-experiment-plans/2026-09-24-audio-uncertainty/design.json)

## photo-answerability-audit

**Exact-image answerability and exposure audit** — 2026-10-01; photo; audit;
closed.

- Configuration: Read-only review of 20 exposed explicit-primary-screen images
  and existing evidence; no new model configuration
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 0 (none). Accounted USD: 0.000000000. Offline analysis; zero
  provider calls, charges or reservations. Earlier paid budgets remain closed.
- Outcome: 20 exact image hashes verified; two species-reference holds, six
  unresolved-rank review holds, and per-image visibility-note corrections.
- Limits: Outcome-aware assistant review, not independent human validation.
  Original scores unchanged; reviewed dispositions are not replacement accepted
  answers.
- Decision: Resolve reference/rank holds before another paid screen. Conditional
  two-arm feature-observation experiment proposed, not implemented or
  authorized. Retain released Sol-low.
- Production: No runtime, threshold or deployment change.
- Sources:
  [identification-answerability-audit-2026-10-01.md](../../../docs/rfcs/identification-answerability-audit-2026-10-01.md),
  [answerability-review-2026-10-01.json](../../../docs/research/identification/answerability-review-2026-10-01.json)

## photo-reference-adjudication

**Versioned photo reference and rank adjudication** — 2026-10-01; photo; audit;
closed.

- Configuration: Exact-image reference overlay and three verified GBIF family
  additions; no new model run
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 0 (none). Accounted USD: 0.000000000. Offline reference review; zero
  identification provider calls, charges or reservations. Public taxonomy lookup
  only.
- Outcome: 18 accepted provisional development references: five species, six
  genus, three family, two unresolved biological and two nonbiological; two
  explicit reference holds.
- Limits: Assistant review, primary outcome-aware, no independent human
  validation. Original scores and answer keys preserved; not a runnable or
  authorized collection packet.
- Decision: Use the versioned 18-case frame for offline candidate preparation;
  conditional 36-attempt development design requires an unresolved-case gain as
  well as broader-rank benefit. No paid authorization.
- Production: No application behavior, confidence threshold or deployment
  change.
- Sources:
  [identification-reference-adjudication-2026-10-01.md](../../../docs/rfcs/identification-reference-adjudication-2026-10-01.md),
  [answerability-adjudication-2026-10-01.json](../../../docs/research/identification/answerability-adjudication-2026-10-01.json)

## photo-feature-offline-preparation

**Photo diagnostic-feature candidate offline preparation** — 2026-10-01; photo;
engineering; closed.

- Configuration: Explicit-primary Sol-low comparator; bounded diagnostic-feature
  request and transient review contract prototype. No live dispatcher.
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 0 (none). Accounted USD: 0.000000000. Offline implementation and
  preparation only; closed study budgets are not reused.
- Outcome: Prepared 18-case reference/taxonomy/input bindings and 36 proposed
  arm assignments; software validation only.
- Limits: Assistant-reviewed exposed references; two holds excluded; no paid
  collector, integrated reviewer assignment/adjudication or new biological
  results.
- Decision: Complete execution/review integration and a new authorized freeze
  before a paid screen. Keep released configuration.
- Production: No production configuration change.
- Sources:
  [identification-photo-feature-preparation-2026-10-01.md](../../../docs/rfcs/identification-photo-feature-preparation-2026-10-01.md)

## photo-feature-workflow

**Photo feature collection and review implementation** — 2026-10-01; photo;
engineering; closed.

- Configuration: Explicit-primary comparator and bounded diagnostic-feature
  candidate; 36-slot collector, private double coding and paired advancement
  report.
- Data: [confidence-photo-v2](datasets.md#confidence-photo-v2)
- Attempts: 0 (none). Accounted USD: 0.000000000. Offline validation only;
  synthetic providers and judgments. No new provider charges or reservations.
- Outcome: Implemented immutable attempt accounting, transient review,
  image/card/result-bound categorical receipts and frozen development hurdle.
- Limits: Exposed provisional assistant-reviewed references; browser slots do
  not establish independent humans; conservative disagreement rejection replaces
  proposed adjudication. No accuracy result.
- Decision: Prepare isolated source and current pricing, actual reviewers and
  new spending authorization before paid execution. Keep released configuration.
- Production: No production configuration or deployment change.
- Sources:
  [identification-photo-feature-workflow-2026-10-01.md](../../../docs/rfcs/identification-photo-feature-workflow-2026-10-01.md)

## Supporting records

These links preserve plans, implementation, contracts and release context. They
are not additional paid studies and are not summed with the entries above.

- [Identification bottleneck audit — Slice 1](../../../docs/rfcs/identification-bottleneck-audit-2026-09-27.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification metrics in Field Chat and exports — 26 September 2026](../../../docs/rfcs/identification-chat-export-metrics-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification client result provenance — 26 September 2026](../../../docs/rfcs/identification-client-result-provenance-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Naturebook Identification Evaluation Readiness — SRD](../../../docs/rfcs/identification-evaluation-srd.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Fixed-context audio replay](../../../docs/rfcs/identification-fixed-context-replay-2026-09-23.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [AI provider flexibility — Slice 1 baseline](../../../docs/rfcs/identification-foundation-baseline.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Naturebook AI Provider Flexibility — SRD](../../../docs/rfcs/identification-foundation-srd.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [AI provider flexibility — local verification and release preparation](../../../docs/rfcs/identification-foundation-verification.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Native identification recipient preflight — 26 September 2026](../../../docs/rfcs/identification-native-recipient-preflight-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI photo confidence display](../../../docs/rfcs/identification-openai-confidence-display-2026-09-28.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI confidence thresholds: retained-evidence audit](../../../docs/rfcs/identification-openai-confidence-evidence-audit-2026-09-29.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI explicit-null prompt candidate](../../../docs/rfcs/identification-openai-null-fields-candidate-2026-09-27.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI observed-traits candidate](../../../docs/rfcs/identification-openai-observed-traits-candidate-2026-09-29.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI photo integration](../../../docs/rfcs/identification-openai-photo-integration-2026-09-27.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI photo rollout](../../../docs/rfcs/identification-openai-photo-rollout-2026-09-28.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI identification prompt and context review](../../../docs/rfcs/identification-openai-prompt-review-2026-09-27.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification optimization while preserving current results](../../../docs/rfcs/identification-optimization-preserving-results-2026-09-27.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification client compatibility — 26 September 2026](../../../docs/rfcs/identification-provider-client-compatibility-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Provider-flexibility implementation review](../../../docs/rfcs/identification-provider-flexibility-review-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [App-controlled identification input routing — 26 September 2026](../../../docs/rfcs/identification-provider-input-routing-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Independent OpenAI consent infrastructure](../../../docs/rfcs/identification-provider-openai-consent-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification provider optimization plan](../../../docs/rfcs/identification-provider-optimization-plan.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Provider-bound identification admission](../../../docs/rfcs/identification-provider-production-admission-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Durable identification result provenance](../../../docs/rfcs/identification-provider-result-provenance-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification provider usage attribution](../../../docs/rfcs/identification-provider-usage-attribution-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification public metric compatibility — 26 September 2026](../../../docs/rfcs/identification-public-metric-compatibility-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Identification recipient preflight — 26 September 2026](../../../docs/rfcs/identification-recipient-preflight-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [Shared species-content qualification](../../../docs/rfcs/identification-shared-content-qualification-2026-09-26.md)
  — Supporting plan, contract, audit or implementation history; not an
  additional paid study entry.
- [OpenAI beta still-photo activation](../../../docs/release-evidence/openai-beta-photo-activation-2026-09-28.md)
  — Release or foundational evidence; no independent accuracy result.
- [Task benchmark qualification and model assignment](../../../docs/research/identification/benchmark-contract.md)
  — Current prospective qualification contract for the generated capability
  matrix; no new experiment, paid authorization or routing change.
