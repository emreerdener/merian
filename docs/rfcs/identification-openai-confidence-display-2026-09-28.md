# OpenAI photo confidence display

Activation addendum, 30 September: the owner reported a released iOS build and
fresh device scan, then explicitly requested activation on production project
`qlarqavoqhkuwzmevrmf`. The production photo builder now selects the assessed
confidence prompt. The study and historical findings below are preserved;
0.95/0.60 and `openai_unqualified_v1` remain unchanged. Deployment and the
limits of independently captured reader evidence are tracked in the
[activation record](../release-evidence/openai-confidence-activation-2026-09-30.md).

Current extension, 30 September: the
[confidence assessment contract](identification-openai-confidence-assessment-2026-09-30.md)
adds a prepared OpenAI-only prompt and a third explicitly mapped native profile.
Original and observed-traits results retain 0.95/0.60. The revised profile also
retains 0.95/0.60 after the
[development assessment](identification-openai-confidence-results-2026-09-30.md)
found no eligible cutoff; this is fallback retention, not accuracy
qualification. `ConfidenceHeader` now describes a model-generated estimate
instead of claiming a precise score; its percentage heading and layout are
unchanged. The reader must be distributed and verified before backend
activation. The dated findings below remain historical evidence.

Date: 2026-09-28

Status: Implemented for native review; distribution remains a separate release
step. No provider, prompt, schema, persisted score or backend policy changes.

## Problem and decision

A successful OpenAI photo identification retained its numeric score and exact
execution provenance, but iOS only recognized Gemini confidence bands. Every
recognized OpenAI result therefore fell back to Needs review, regardless of the
score. The owner chose to keep the existing Strong / Possible / Weak labels and
add OpenAI-specific thresholds instead of introducing another badge label.

The exact shipped `openai_photo_v1` profile now uses:

| Label          | Raw model score        |
| -------------- | ---------------------- |
| Strong match   | `>= 0.95`              |
| Possible match | `>= 0.60` and `< 0.95` |
| Weak match     | `< 0.60`               |

These thresholds are the same for every plan tier because the shipped photo
execution profile is the same. Existing confirmed/overridden decisions and
analyzing states keep precedence. The existing zero-score visibility behavior is
retained. Gemini Flash and Pro keep their original thresholds.

## Evidence and limitations

The cutoffs come from the primary `confidence_score` description in the
[executable structured-output contract](../../services/supabase/functions/_shared/identify/contract.ts):
`>= 0.95` requires diagnostic morphology, `0.80–0.94` permits visually
confusable alternatives, `0.60–0.79` is probable, and `< 0.60` lacks diagnostic
detail. The
[OpenAI request builder](../../services/supabase/functions/_shared/ai/openaiRequest.ts)
sends that strict schema to the model. This supports a provisional UI
interpretation of the model's score; it does not establish measured accuracy.

There is a known source inconsistency: the accompanying shared instruction in
[identify/schema.ts](../../services/supabase/functions/_shared/identify/schema.ts)
uses `>= 0.90` for unambiguous diagnostic features. This display policy chooses
the stricter `0.95` structured-schema anchor. Reconciling the prompt text
belongs to the separate prompt-optimization work and would require its own
evaluation; this change preserves the evaluated prompt.

A read-only review of retained 25 September pilot outputs found four unique,
normalized, named photo results: scores `0.96`, `0.87`, `0.84`, and `0.87`. All
four agreed with their provisional reference identification. The display policy
would place one in Strong and three in Possible. Description-only inputs,
non-biological controls, unknown executions and repeated versions of the same
case were excluded from that count. No requests were repeated.

That sample is too small, has no Weak coverage, and has no independently
reviewed references for calibrating probabilities or selecting an accuracy
cutoff. Its evaluation profile is also distinct from the production moderation
binding. It is only a sanity check, not evidence that a Strong result is 95%
accurate. Original benchmark reports and their qualification status remain
unchanged; see the
[pilot record](identification-openai-photo-text-pilot-2026-09-25.md).

## Implementation boundary

[InferenceConfidencePolicy](../../apps/ios/Merian/Core/AI/Inference/Result/InferenceConfidencePolicy.swift)
adds `DisplayBands` and `displayBands`, separate from the existing qualified
`Bands` / `bands` interface. OpenAI display eligibility requires the full V2
production tuple: provider, model, binding, prompt, schema, confidence
reference, policy version, variant, operation, safety policy, timeout,
generation settings and absent diagnostic triggers. Unknown, damaged or changed
profiles keep Needs review until explicitly reviewed. Absence of provenance
retains legacy behavior.

Only the badge, explanation header and spectrum use display bands. OpenAI keeps
`openai_unqualified_v1` and its original numeric score. Candidate visibility,
review collections, sharing recommendations, score-based upgrade prompts,
perfect-scan rewards, automatic evidence gates, public confidence metrics and
benchmark Strong/diagnostic metrics retain their existing qualification rules. A
high display score does not grant any of those behaviors.

The explanation preserves the existing format and percentage header. It states
that the score is the AI's estimate, not a measured probability of a correct
identification. OpenAI uses Naturebook AI branding without a Flash/Pro chip or
plan-based accuracy claim. Gemini copy is unchanged. The raw score selects the
band; the existing header rounds the displayed percentage.

Live results, saved local records and restored owner history use the same stored
provenance. No re-identification, schema migration, new backend deployment or
production data rewrite is needed. An updated native build is needed to show the
new display policy, including for existing saved OpenAI results.

## Verification and release

`IdentificationResultProvenanceTests` covers threshold boundaries on both plan
tiers, changed/damaged profile fallback, confirmed/analyzing precedence, and
preservation through wire decoding, local persistence and reopening. It also
protects candidate review, sharing recommendations, score-based promotion and
rewards from accidentally adopting display-only bands. Existing confidence
presentation and feature architecture tests remain in the focused test gate.

Run the local focused iOS tests, source guardrails and Markdown checks, followed
by the normal complete pull-request iOS gate. Archive/upload and installed-build
verification follow the existing native release process. No paid benchmark is
required for this presentation change, and no empirical calibration claim is
introduced.

## Calibration priority — 2026-09-29

Historical priority before the later sequence update below: the owner's
direction was **no further comparisons unless they directly contribute to
resolving confidence thresholds**. The task at that checkpoint was to validate
or adjust Strong / Possible / Weak for the current production Sol photo profile,
retained for both Free and Pro. Preserve the current explanation format. Model
selection, prompt optimization and qualification of the explicit-primary
producer are deferred; they are not prerequisites for this calibration work.

The 0.95/0.60 display cutoffs above remain provisional. No cutoff or
`openai_unqualified_v1` policy changes merely because the model is more capable,
the plan tier changes, or a development comparison finishes. Calibration should
measure how scores correspond to correctness, including confident mistakes. It
does not require eliminating every identification error first.

Proceed using existing evidence:

1. Inventory retained scores, exact execution profiles, input cases and reviewed
   identity references. Establish whether the evaluation binding is equivalent
   to the current production binding before pooling results. Keep changed
   prompts, schemas, models and moderation bindings separate. Missing scores
   remain missing; do not reconstruct them from explanation ratings or rerun
   cases just to complete an inventory.
2. Deduplicate repeated observations and distinguish identity correctness from
   explanation quality. Preserve errors, abstentions and limited/unassessable
   references. Only assessable labels can support measured correctness; a
   reference gap is neither a correct nor an incorrect identification.
3. Examine coverage and errors across raw-score ranges, including the existing
   0.60 and 0.95 boundaries. Report sample counts, input/rank coverage and
   uncertainty with any proposed cutoff. Use separately reserved evidence for
   validation rather than reporting threshold-selection cases as independent
   confirmation. Keep badge display, calibrated-probability claims and automated
   acceptance/reward policies distinct.
4. If the retained evidence cannot resolve a cutoff, identify the precise gap
   and the smallest useful calibration collection. Any additional comparison
   must state the threshold question it answers and how its outcome would change
   the decision. General model ranking, latency, cost or prompt improvements are
   insufficient reasons for another run. Existing execution and budget controls
   still apply; this planning update does not start a paid request.

The
[completed explicit-primary comparison](identification-sol-primary-comparison-results-2026-09-29.md)
remains development evidence, with its results and limitations intact. Its new
candidate remains unqualified and inactive. The control's retained evidence may
be assessed for calibration eligibility; it must not automatically be treated as
a representative calibration set. Do not repeat that completed packet.

Completion means an evidence-backed recommendation to retain or change the
current display cutoffs, with the limits of that conclusion made explicit and
any required implementation verified. A new candidate or another comparison is
not itself completion of the confidence task.

## Retained-evidence audit — 2026-09-29

The
[offline evidence audit](identification-openai-confidence-evidence-audit-2026-09-29.md)
is complete. Eighteen Sol controls were verified against the current production
request, but they represent only six distinct photos. The fifteen named
biological outputs occupy Possible fourteen times and Weak once; none reaches
Strong. The only Weak identity reference is limited, and the repeated
development observations do not supply independent calibration evidence.

Retain 0.95/0.60 as provisional display cutoffs. The audit does not validate a
new boundary or qualify automatic confidence-based behavior. Older evaluation
bindings and changed-prompt candidates remain separate. No paid requests ran.

When calibration resumes, the next useful collection is a single-profile
confidence study with reliable identity/rank labels and coverage of the missing
score ranges. Its inputs, reliability objective, validation split and bounded
execution plan must be prepared for that purpose. A competing model or prompt
arm is unnecessary.

## Sequence update — optimization first

Later on 29 September, the owner explicitly chose to finish OpenAI optimization
before confidence calibration. This supersedes the earlier confidence-first
ordering, not the audit findings. The
[current optimization plan](./identification-optimization-preserving-results-2026-09-27.md#sequence-update--29-september-2026)
starts with the isolated observed-traits candidate while preserving the existing
explanation format. Calibration collection remains deferred until the retained
or optimized configuration is selected.

Keep the 0.95/0.60 display cutoffs provisional and keep `openai_unqualified_v1`.
Existing audit controls describe only their exact configuration; changed-prompt
results must not be pooled as if they used it. After optimization, use reviewed
identity/rank evidence, missing score-range coverage and separate validation
evidence for the selected profile. Closed comparisons and their unused budgets
remain closed.

## Observed-traits prompt integration — 2026-09-29

The updated native reader explicitly recognizes both production photo prompts:
`openai_identify_vision_v1` and `openai_identify_vision_observed_traits_v1`.
Every other profile check, the 0.95/0.60 provisional display cutoffs and
`openai_unqualified_v1` remain unchanged. Existing scans keep their recorded
prompt; unknown or altered profiles retain neutral review guidance. The update
does not qualify automatic verification, rewards, candidate suppression or
sharing recommendations.

After the existing additive backend and migration prerequisites are deployed,
distribute this reader before deploying this prompt revision. An older build can
decode the same result but displays Needs review for the unfamiliar prompt;
identification capabilities 4/5 do not distinguish these revisions. No database
migration or DTO shape change is required. The
[integration record](./identification-openai-observed-traits-candidate-2026-09-29.md#production-integration--29-september-2026)
owns release checks. Calibration must use the final configuration; the retained
control audit describes the original prompt and is not recalibrated by this
edit.
