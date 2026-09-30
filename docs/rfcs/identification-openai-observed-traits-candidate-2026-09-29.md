# OpenAI observed-traits candidate

Date: 29 September 2026

Status: Offline request candidate implemented; provider behavior is unmeasured.
No live adapter, evaluator registration or production assignment selects it. The
later owner decision below replaces the proposed dedicated comparison with
focused regression checks and a small ordinary beta smoke check.

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
  trait. A zero-trait abstention policy remains separate work; this change does
  not alter that existing contract limitation or add a new placeholder.
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

## Validation decision update — 29 September 2026

The earlier plan proposed a dedicated control/candidate comparison. The owner
challenged its proportionality for this small beta wording change. The revised
plan uses targeted regression validation and a brief ordinary-app smoke check;
there is no new comparison runner, paired benchmark or statistical improvement
claim. This decision is specific to the two trait directions, with the same
model, evidence, output shape, explanation format and generation settings.

A prompt change can still affect individual identifications and score
distributions. The completed compatibility tests establish isolation, not model
accuracy. Accept the narrow beta change on that basis without claiming that it
has reduced hallucinations, improved accuracy or made identification faster.
Formal provider qualification and confidence calibration retain their separate
requirements.

Next implementation steps:

1. Integrate the wording into a separately versioned OpenAI photo prompt using
   the existing production request path. Preserve historical prompt identities,
   correct saved provenance and existing compatible-client/badge behavior. The
   evaluation-only identity above cannot itself become a production assignment.
2. Run the affected request, decoding, provenance and consumer regression checks
   plus normal CI. Preserve Gemini, full observation inputs, moderation, the
   explanation definition and trait-array bounds. Do not build an experiment
   controller for this change.
3. Following the normal beta release process, check a few ordinary scans: a
   clear biological photo, an unclear photo and a non-biological scene. Include
   a multiple-photo observation among those checks. Confirm successful
   processing, coherent traits, normal explanations, saving and reopening. Use
   existing approved test material; the assistant handles the checks where
   available. This is a functional smoke check, not an accuracy estimate. An
   observed regression is a reason to correct or revert the change.
4. Freeze the integrated prompt configuration and proceed to confidence
   calibration. Keep earlier scores tied to their original configuration rather
   than pooling changed-prompt results automatically. OpenAI audio follows the
   confidence work; further optimization candidates are deferred.

Existing comparison packets and budgets remain closed. No provider request or
production mutation runs as part of this documentation update. The normal
release authorization and deployment controls continue to apply.

## Reader-preparation release — 29 September 2026

The wording integration is implemented on the retained follow-up branch. The
prerequisite release deliberately retains `openai_identify_vision_v1` in the
production `openai_photo_v1` builder. Its app recognizes both that original
prompt and `openai_identify_vision_observed_traits_v1` with the same exact
model, schema, moderation, generation and policy checks. Existing display-only
0.95/0.60 bands remain provisional; adding this prompt identity does not
calibrate its scores or admit the evaluation-only binding.

This release also carries the earlier additive primary-resolution foundation.
That reserved producer remains inactive. Preserve its deployment order as well
as the prompt-reader order:

1. Review and validate the prerequisite branch against current `main`. Deploy
   its additive migrations and compatible Edge code through the canonical
   production workflow before distributing the capability-5 app. The production
   photo prompt remains the original version during this step.
2. Archive, upload and verify the updated beta app, including installation over
   the previous released build, saved observations and normal launch. This app
   advertises capability 5 and recognizes both photo prompt identities.
3. Release the separate wording integration, with a freshly generated backend
   fingerprint and normal candidate checks. It uses the existing production
   binding and schema; the evaluation-only identities above remain frozen.
4. Perform the ordinary beta smoke checks in the validation decision above, then
   freeze that configuration for confidence calibration. No new paired model
   comparison is required for this wording change.

The prerequisite branch and follow-up source are release preparation, not proof
of deployment or installed-app verification. Production deployment and native
upload/distribution remain separately authorized operations. See the
[primary-resolution sequence](identification-primary-resolution-contract-2026-09-29.md)
and [deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
for the existing migration, candidate validation and rollback controls.
