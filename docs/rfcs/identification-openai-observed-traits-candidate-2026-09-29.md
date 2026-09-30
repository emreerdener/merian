# OpenAI observed-traits candidate

Date: 29 September 2026

Status: Offline request candidate implemented; provider behavior is unmeasured.
No live adapter, evaluator registration or production assignment selects it.

## Decision and evidence

Resume the
[optimization plan](./identification-optimization-preserving-results-2026-09-27.md)
before calibrating OpenAI confidence thresholds. Preserve the current
explanation format. Keep the current Sol photo profile for both tiers while
evaluating one isolated instruction hypothesis.

The current visual instruction demands three structural observations and the
strict-schema description demands exactly three traits. The runtime contract
already accepts one through ten. Requiring a fixed number may encourage padding
when only one or two features are actually visible. The
[completed explicit-primary comparison](./identification-sol-primary-comparison-results-2026-09-29.md)
found a concrete anatomy-grounding failure, but it does not establish that trait
count caused that failure. This candidate tests that hypothesis; it is not a
demonstrated accuracy, latency, cost or confidence improvement.

Use `openai_photo_sol_low_v1` as the production-equivalent control. Do not layer
the change on the inactive rank or explicit-primary candidates: those also
change rank and alternative semantics. All completed experiments remain closed.

## Exact scope

The pure builder in
[`openaiObservedTraits.ts`](../../services/supabase/functions/_shared/ai/openaiObservedTraits.ts)
starts with the full current Sol photo request. It changes only:

1. The fixed-count instruction to request one to three distinct, directly
   supported physical or structural observations. One or two are sufficient; do
   not invent, repeat or infer unseen anatomy to reach three.
2. The `extracted_visual_traits` schema description to match that instruction.
3. The private schema name and candidate provenance used to distinguish the
   experiment from its control.

Material visibility limitations belong in the existing explanation, not as
substitute traits. The `ai_reasoning` definition, current 1–3-sentence format,
all remaining schema descriptions, required fields and bounds stay identical.
Complete photo bytes and order, optional notes and context, model, low
reasoning, high image detail, 8,192-token limit, inline moderation, automatic
cache behavior and confidence instructions stay identical. Gemini and all prior
OpenAI profiles are unchanged. Audio and sampled-video observations remain
unsupported by this photo candidate; no part of an unsupported observation is
silently discarded.

The selected offline acceptance target is **two fixed-count directions removed,
zero unplanned request differences and zero production-admission changes**.

## Limits that remain

- One to three is an instruction, not a new validator bound. Four through ten
  traits remain structurally valid. Empty arrays and more than ten remain
  invalid. No client or shared contract migration is introduced.
- A true zero-discernible-trait observation cannot be represented under the
  retained minimum of one. Do not invent a visibility placeholder to satisfy it.
  This narrow hypothesis covers observations with at least one directly visible
  trait; a zero-trait abstention policy requires separate design before any
  promotion decision.
- Instructions do not enforce biological truth. Compatibility tests cannot
  demonstrate that a model avoids hallucinations or handles unseen anatomy.
- Remaining rank, species-specificity, alternative-count and confidence-anchor
  tensions in the baseline are unchanged. This candidate does not qualify the
  explicit-primary producer or repair every grounding failure.

## Frozen identities

| Dimension                | Candidate                                                          |
| ------------------------ | ------------------------------------------------------------------ |
| Profile                  | `openai_photo_sol_observed_traits_low_v1`                          |
| Binding                  | `openai_observed_traits_evaluation_v1`                             |
| Model                    | `gpt-6-sol`                                                        |
| Prompt                   | `openai_identify_vision_observed_traits_v1`                        |
| Schema                   | `merian_openai_observed_traits_v1`                                 |
| Confidence               | `openai_unqualified_v1`                                            |
| Instructions SHA-256     | `f422b49ef1a0cd459f674f1d11d24da37f130c2b9202a421b90ede497b127f7e` |
| Full text-format SHA-256 | `8e3b788d78c7427fb391b78f39a8d2d79f1d40738344f1b34f335c38f7be4486` |
| Snapshot SHA-256         | `e966db489fb0167ba634d1ba9ba147c258673cb5eacd4d471f77a659ccf05230` |

Control instruction SHA-256:
`338754d17eb1abde90ad7d9ed66dd552043e0b56028b0265522857e979a86c09`. Control full
text-format SHA-256:
`e679315d0b431bbecd562f24542257acccac017e0bf4c88ea3664370d3a61871`. The existing
request fingerprint helpers and synthetic photo fixture define these hashes.
They do not contain user media or model responses.

## Validation

Run the focused suite without network or credential access:

```bash
deno test --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/ai/openaiObservedTraits_test.ts \
  services/supabase/functions/_shared/ai/openaiPhotoModels_test.ts \
  services/supabase/functions/_shared/ai/openaiSolPrimary_test.ts
```

The new tests cover full request parity for single-photo, optional-note and
multiple-photo inputs; unchanged explanation and schema bounds; frozen control
and candidate hashes; missing/duplicate instruction anchors and schema drift;
snapshot substitution; still-photo-only input; exclusion from production and
historical evaluators; and existing decoder acceptance of shorter arrays without
widening its contract. The old explicit-primary decoder rejects this legacy
shape. No separate decoder or transport is added. The existing candidate CI step
runs the new suite with network and environment access denied. The reviewed
AI-module inventory admits only this new pure builder and checks that it cannot
own transport or credentials.

Local verification checkpoint, 29 September: all 19 focused tests and all 47
restricted OpenAI CI tests passed. The complete Edge suite passed 2,230 tests
with eleven database integration tests skipped because no disposable database
was started. The full Supabase tooling suite, DTO contract gate, recursive
checks for all 103 function entrypoints, dependency/configuration validators,
Deno format/lint, changed-Markdown formatting and local documentation links
passed. Independent read-only review found no remaining issue after the CI
inventory and current-order documentation corrections. Hosted CI, database
execution, provider calls and deployment were not performed by this slice.

## Next decision and stopping rule

Before any paid test, prepare a separately versioned, bounded comparison against
the unchanged current Sol control. Declare the exact cases, reviewed visible
features, failure criteria, request limit and spend ceiling. Existing approved
budgets and closed packet commands do not authorize this new identity. The
current slice prepares the request only and has no dispatch capability.

Use existing reviewed photos where their evidence can support the question. Each
included case needs at least one assessable visible trait. Limited identity
references must remain limited and receive no false correctness credit. Do not
redo the broad Gemini/OpenAI comparison or add descriptions merely for coverage.

The main question is whether the candidate reduces unsupported visual claims.
Review traits and explanation together against visible evidence. Require no new
critical grounding, safety, subject-selection, assessable identity/rank or
explanation-format regression. A lower trait count by itself is not success.
Record latency and usage only as descriptive secondary measures. The assistant
performs the reviews; no owner calibration exercise is required.

Stop after the bounded comparison. Failure or an inconclusive result retains the
baseline; it does not authorize a parameter sweep. A promising small development
screen is still not production qualification. Once the configuration is
selected, resume the separate
[confidence task](./identification-openai-confidence-display-2026-09-28.md#sequence-update--optimization-first),
using only evidence compatible with that exact configuration. OpenAI audio and
Free/Pro model differentiation remain later work.
