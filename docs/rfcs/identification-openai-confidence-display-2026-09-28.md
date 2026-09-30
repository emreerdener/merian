# OpenAI photo confidence display

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
