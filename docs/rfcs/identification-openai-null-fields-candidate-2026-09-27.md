# OpenAI explicit-null prompt candidate

Date: 27 September 2026\
Status: Experiment closed inconclusive on 28 September before any candidate
request. Retain the original prompt; no production activation. The
implementation and original verification record below remain historical
evidence; see the closeout at the end of this document.

## Decision and scope

Implement the four exact replacements from the
[offline prompt review](./identification-openai-prompt-review-2026-09-27.md) as
`openai_photo_null_fields_v1`, using prompt
`openai_identify_vision_null_fields_v1`. It replaces four directions to omit
inapplicable fields with directions to return null, matching the existing strict
OpenAI schema. This removes a wording conflict; model accuracy, failure rate,
speed and cost benefits remain unmeasured.

The original `openai_photo_text_v1` reusable baseline still executes
`openai_gpt_6_sol`. Its descriptor, instructions, request construction and
schema are unchanged. Gemini and the closed concise-explanation profiles retain
their original behavior and hashes. The dormant production photo binding still
uses the original prompt, and production dispatch remains Gemini-only.

The complete evidence, explanations, alternatives, schema, normalization, model,
reasoning effort, image detail, output limit and native cache settings remain
fixed. Optional photo descriptions are preserved. Text-only, sampled-video and
audio observations cannot use this candidate, and no evidence is discarded to
make a request eligible.

## Implementation

[openaiNullFields.ts](../../services/supabase/functions/_shared/ai/openaiNullFields.ts)
owns the four replacements and frozen prompt/schema digests.
[openaiRequest.ts](../../services/supabase/functions/_shared/ai/openaiRequest.ts)
selects them only for the new evaluation snapshot. Missing or repeated source
fragments fail preparation. The reusable profile additionally checks the exact
candidate prompt and schema fingerprints before any claim.

Candidate prompt digest:
`8d8c5ab7f612555a0a275ade42de7615f327314c644502ab5d2217c1bab1f948`.

Unchanged schema digest:
`bda80368f8be0ef9424e22b7f7adfa1c7ecc5098ff68c9e52bc4c8f69182e52e`.

The canonical
[evaluator contract](../../services/supabase/scripts/identification_evaluation/README.md#openai-explicit-null-candidate)
owns the new v4 experiment, v3 run specification/manifest and v4 candidate
attempt. Baseline attempts remain v2. Historical versions reject the new
candidate, and standalone execution cannot bypass the controller.

## Bounded comparison to prepare next

Prepare a new packet using the **six existing approved photo observations**: one
unchanged OpenAI baseline run and one candidate run, six calls each, twelve
total. Preserve image bytes and existing context. This is a targeted comparison
of the new prompt against its OpenAI baseline; existing Gemini measurements are
retained without rerunning Gemini or the two text-only cases.

Before any paid request, bind the exact source, input digests, profile digests,
fresh reviewed rate card, account/key readiness, time window, two run budgets
and aggregate allocation. Both runs must fit their full conservative
reservations. There is no paid allocation in this implementation record, no
credential collection and no reuse of a closed experiment's remaining budget.

Prepare fact cards for each retained observation from the approved evidence and
available references. Include applicable decision reasons, supported-rank
limits, abstention and non-biological requirements. Do not invent facts to make
an explanation assessable. The already-delegated assistant reviews each bounded
result against those facts using the existing private view. The owner need not
repeat the practice exercise. Reviews are AI assessments without independent
human validation; they create no extra paid judging calls.

The acceptance rules are:

1. Offline parity must show exactly four wording changes and no other native
   request differences. The current explanation definition and schema remain
   identical.
2. All twelve attempts and their three-criterion explanation assessments must
   complete. Refusal, invalid output, unresolved reference coverage, missing
   review or unassessable claims cannot count as a successful screen.
3. Paired results must preserve supported identity/rank, subject handling and
   applicable abstention, with grounded, sufficiently specific explanations and
   honest uncertainty. New quality faults retain the baseline. Existing
   reference disagreements also prevent a passing screen.
4. A completed, supported screen can report only
   `no_observed_regression_in_six_photo_screen`. It is neither general accuracy
   evidence nor production qualification. The corpus does not cover every
   uncertainty, abstention, safety or context case; untested behavior remains
   unqualified.

The baseline native cache behavior is retained in both arms. Record cache reads
and writes as reported, without paid warm-ups, padding, explicit cache changes
or assuming equal warmth. Known conservative upper cost continues to control
spending. Missing rate-aware cost inputs remain unknown; missing budget-critical
usage stops with the full reservation retained.

The v4 report preserves per-run timing and cost observations while suppressing
latency/cost improvement percentages and any speed threshold. Cache
comparability remains `not_established`. A changed prompt and a small reused
corpus do not support a causal speed/cost claim.

## Verification and stopping point

Focused offline tests passed for native-request parity, unchanged baseline
fingerprints, strict null/missing-key decoding, unsupported input rejection,
version isolation, twelve-call live allocation, missing-usage and failed-review
stops, nonzero/unknown cache counters, interrupted-review recovery without
replay, private report regeneration and the separate CLI demonstration.
Independent read-only contract review found no actionable issue.

Local validation completed:

- Whole-tree Deno formatting and lint passed.
- Complete Edge suite: 2,163 tests passed, 9 ignored.
- Complete Supabase tooling: 455 standard tests and 66 isolated evaluator tests
  passed, together with the DTO contract gates and all 12 shell test files. The
  launcher tests use a local fake and real permission probes; zero API calls.
- All 102 function entrypoints passed type checks with their deploy-time
  configs; function dependency/config validation passed.
- Generated identification bundle identity was refreshed with the checked-in
  generator and passed its deterministic-current test.
- Changed-Markdown formatting, diff checks and 335 local documentation links
  passed. Independent review's accepted-input wording clarification was applied.

The required Supabase candidate workflow will supply disposable-database
evidence for the PR. No SQL or iOS source changed, so no local database replay
or iOS build was run for this slice. Production assignment, moderation and
release controls remain unchanged.

After validation, freeze one reviewable live packet and its allocation. Stop
after that bounded comparison. Keep the baseline if evidence is incomplete or
the candidate is unhelpful; no parameter sweep or automatic promotion follows.
Close this optimization decision before planning OpenAI audio. Permission
collection, production qualification/activation and iOS distribution remain
separate work.

## Experiment closeout — 28 September 2026

The final bounded run stopped during baseline explanation review: the available
review references could not assess all material claims. No candidate request
ran, so there is no paired quality, latency or cost result for this prompt
change. The result is **inconclusive**, not evidence of a regression or an
improvement. Keep `openai_photo_text_v1` and the original production prompt. Do
not resume unused assignments or automatically replace failed runs.

Private review reports retain the per-attempt evidence; no provider response
text is copied into this record. The owner chose to complete the
[photo rollout](./identification-openai-photo-rollout-2026-09-28.md) before any
further prompt optimization. The existing Gemini/OpenAI benchmark is unchanged.
