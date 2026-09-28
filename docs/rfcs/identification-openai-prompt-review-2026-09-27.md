# OpenAI identification prompt and context review

Date: 27 September 2026\
Status: Offline review complete; one candidate specified and checked. Candidate
implementation and live evaluation remain pending. Production remains Gemini.

## Decision

Keep one set of identification requirements and the current explanation format,
with separately versioned provider instructions. Select a small OpenAI visual
prompt candidate that replaces four field-omission directions with explicit
`null` directions. This aligns the wording with OpenAI's existing strict schema.
The shared Gemini prompt, frozen OpenAI baseline and result contract stay
intact.

This is a clarity and consistency candidate. The completed matched comparison
had eight normalized OpenAI results and no normalization failures, so there is
no demonstrated failure-rate, speed, cost or identification-quality improvement.
Do not market this change as faster or more accurate.

This review completes the first deliverable in the
[current optimization plan](./identification-optimization-preserving-results-2026-09-27.md).
It does not close the optimization milestone or start OpenAI audio work. Review
source: `2bbacb8c895903052d1d60be9eac1fa69deba176`.

## Actual request and requirement map

The
[OpenAI builder](../../services/supabase/functions/_shared/ai/openaiRequest.ts)
selects the
[shared visual instruction](../../services/supabase/functions/_shared/identify/schema.ts)
when any image is present, or the
[description instruction](../../services/supabase/functions/identify-multimodal/instructions.ts)
for text-only input. It appends OpenAI guidance about nullable fields,
unqualified confidence and treating observation text as evidence. The strict
schema is projected from the
[executable model contract](../../services/supabase/functions/_shared/identify/contract.ts).
The dormant
[production photo binding](../../services/supabase/functions/_shared/ai/openaiPhoto.ts)
reuses that baseline request and adds its own moderation requirement.

| Requirement                                                                 | Current owner and representation                                                                                                                                | Candidate treatment                                                                                    |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| One intended primary subject; all images belong to one observation          | Visual instruction: holistic evaluation, composition, description, tentative focus hints and incidental biology                                                 | Preserve verbatim                                                                                      |
| Biological, dead/preserved, processed and geological distinctions           | Visual instruction: subject status, processed-material exclusions and geological exception                                                                      | Preserve classification and applicability conditions; translate only omission syntax                   |
| Observed structural traits and explanation detail                           | Contract: exactly three traits requested; `ai_reasoning` requests 1–3 sentences describing the supporting physical/visual evidence, bounded at 2,000 characters | Preserve schema description, bounds and prompt text; no concise instruction                            |
| Taxonomy and supported rank                                                 | Visual instruction: accepted names, genus fallback when species cannot be determined, no fabricated names                                                       | Preserve verbatim, including omission of author citations within a name                                |
| Uncertainty and alternatives                                                | Visual instruction plus candidate schema: uncertainty, morphology-based scoring and two alternatives for biological subjects                                    | Preserve instructions, thresholds, bounds and distinguishing features                                  |
| Confidence interpretation                                                   | Shared schema uses calibrated wording/anchors; OpenAI appendix and `openai_unqualified_v1` deny a calibrated-probability interpretation                         | Record wording debt separately; do not change numeric guidance or qualify confidence in this candidate |
| Invasive assessment, location limitations, ecology and organism annotations | Shared instruction, enums and field descriptions                                                                                                                | Preserve all meaning, including missing-location and unsupported-sex behavior                          |
| Pet layer and image quality                                                 | Visual instruction and nested schema                                                                                                                            | Preserve fields, ranges, applicability and supporting evidence                                         |
| Non-biological fields and absent values                                     | Shared prompt says omit; OpenAI schema requires all properties and permits null for domain-optional fields                                                      | Replace exactly four omission directions in OpenAI visual instructions                                 |
| Input facts and ordering                                                    | `buildMultimodalAIRequest` and the OpenAI evidence projection                                                                                                   | Preserve every supplied text item, media byte, item position, lineage and capture fact                 |
| Text-only identification                                                    | `DESCRIBE_SYSTEM_INSTRUCTION` plus the same OpenAI appendix/schema                                                                                              | No candidate change; the four selected omission directions occur in the visual instruction             |
| Model, generation and caching                                               | `gpt-6-sol`, low reasoning, high image detail, 8,192 output-token limit, baseline native cache behavior                                                         | Preserve all settings                                                                                  |
| Admission, recipient permission, moderation, retries and persistence        | Existing server-owned binding and handler/result policy                                                                                                         | No changes or new provider selection                                                                   |

The existing `ai_reasoning` description already sets the explanation format.
Duplicating or shortening it is unnecessary. Schema descriptions also repeat
traits, alternatives, image-quality ranges and some biological restrictions.
Those repetitions are not assumed to be waste: removing them would be a separate
behavioral candidate requiring its own evidence.

## Concrete candidate diff

The
[exact edit manifest](./identification-evaluation-evidence/2026-09-27-openai-prompt-review/prompt-edits.json)
records the source revision, baseline prompt/schema fingerprints and four exact
substring replacements. Its proposed prompt identity is
`openai_identify_vision_null_fields_v1`, with proposed evaluation profile
`openai_photo_null_fields_v1`. Both are placeholders for reviewed
implementation; this is an offline proposal, **not a registered evaluator
profile or production binding**.

Apply these replacements only to a new OpenAI visual-instruction projection.
Each source fragment must occur exactly once, and the baseline prompt and schema
fingerprints must match before generating a candidate.

```diff
-and omit `scientific_name`.
+and set `scientific_name` to null.

-Omit these for generic debris and manufactured/processed objects.
+Set these fields to null for generic debris and manufactured/processed objects.

-you MUST omit `scientific_name`.
+you MUST set `scientific_name` to null.

-All non-biological results MUST omit:
+All non-biological results MUST set the following fields to null:
```

The last replacement preserves the following complete field list: `is_invasive`,
`invasive_status_region`, `invasive_rationale`, `invasive_confidence`,
`ecology_type`, `life_stage`, `reproductive_condition`, `sex`, `sex_confidence`,
`sex_evidence`, `individual_count`, and `ecological_interactions`. The existing
empty `candidates` instruction remains unchanged.

All named fields allow null in the current OpenAI schema. The schema still
requires every property; the adapter still validates and normalizes through
`decodeOpenAIDraft`. Required-nullable fields retain null according to the
common contract. This is a wording change, not a change to response field
optionality or client decoding. OpenAI's
[Structured Outputs documentation](https://developers.openai.com/api/docs/guides/structured-outputs#all-fields-must-be-required)
describes required properties with nullable types for optional values.

Do not globally replace the word `omit`: the instruction to omit author
citations from scientific names is semantic and must remain.

Two other pre-existing wording tensions remain outside this candidate: the
dominant non-biological common-name instruction versus the geological-section
direction to omit names for manufactured objects, and calibrated confidence
wording versus OpenAI's unqualified interpretation. Resolving either could
change result meaning; this four-edit candidate does not resolve all prompt
ambiguity.

## Context review

1. **Supplied descriptions are already distinct.**
   [Native request construction](../../apps/ios/Merian/Core/AI/Inference/Request/InferenceLiveRequestService.swift)
   passes observation contexts through the payload builder;
   [the Edge provider input builder](../../services/supabase/functions/identify-multimodal/provider.ts)
   creates an `observation_context` item only for supplied nonblank text. There
   is no code-generated duplicate of that note to remove. A supplied note also
   affects required text coverage in OpenAI photo moderation; preserve it.
2. **Capture facts are independently supplied.**
   [Capture context formatting](../../services/supabase/functions/_shared/identify/context.ts)
   can include GPS, a location label and a device region. These are distinct
   facts, not interchangeable duplicates. Keep missing context distinct from
   supplied context, and do not infer missing facts from other fields.
3. **Plain-photo ordinal labels are a later hypothesis.**
   [Visual context](../../services/supabase/functions/identify-multimodal/capturedMedia.ts)
   includes per-photo ordinal descriptions even though the OpenAI input array is
   ordered. A later, separately gated photo-only candidate could investigate
   retaining the same-observation/order statement with fewer ordinal labels.
   That does not justify removing focus hints, frame/clip lineage or audio
   association. The current candidate preserves the entire context.
4. **Evaluation shares construction but has narrower context coverage.**
   [Prepared evaluation evidence](../../services/supabase/scripts/identification_evaluation/assets.ts)
   calls `buildMultimodalAIRequest`, while its validated context is restricted
   to device region and month. The existing no-description photo comparison
   remains useful; it does not establish behavior for every real telemetry or
   focus-hint combination. Synthetic parity checks can cover preservation
   without repeating paid benchmarks.

Sampled video contains image snapshots, but current OpenAI admission still
rejects video and audio representations. This review grants no new modality
support and never drops unsupported evidence to fit a photo profile.

## Cache review

Instructions and schema are already stable across observations within each
OpenAI prompt version. Dynamic observation evidence is separate from the
`instructions` field. The earlier pilot recorded three attempts with cached
input tokens and four with zero; cache-write usage was not retained there. The
matched comparison does not establish controlled cache comparability.

[OpenAI caching guidance](https://developers.openai.com/api/docs/guides/prompt-caching)
makes exact prompt-prefix reuse material. A shorter or differently worded prompt
can change reuse; stable code alone does not establish savings. Compare native
read/write usage and cold behavior before selecting an explicit cache strategy.
Do not add cache padding, paid warm-ups or new settings to this prompt
candidate.

The retained concise control/candidate use explicit cache mode without
breakpoints and are separate historical profiles. Their old allocations are
closed. A new candidate needs reviewed registration and experiment controls;
changing a packet identifier or reusing a secret cannot make it runnable.

## Measurable target and implementation boundary

The offline target is **four contradictory field-omission directions removed,
zero other native-request changes**. Preserve the complete response schema,
explanation description, evidence and all native settings. This target concerns
instruction consistency, not measured model performance.

Before admission into the live evaluator:

1. Implement a separately versioned OpenAI candidate from the frozen source
   prompt and exact manifest. Keep the existing profiles and Gemini builders
   unchanged. Verify that the only native payload difference is `instructions`;
   record the new prompt/policy/request fingerprints separately.
2. Add reviewed candidate registration, controller/reporting and accounting
   support for the selected hypothesis. The existing concise-only controller
   cannot execute this proposal. Preserve admission rejection of unregistered
   identities and the disabled production OpenAI gate.
3. Define one bounded matched OpenAI baseline/candidate comparison using the
   existing approved observations and review machinery. Keep input bytes, model,
   schema, generation and cache policy matched; record actual cache usage rather
   than assuming equivalent cache warmth. The assistant can perform the
   already-delegated explanation review; no new owner practice exercise is
   required.

Any later live acceptance must retain valid normalized results, supported
identity/rank, uncertainty, abstention, non-biological handling, explanation
grounding/detail and safety. No automatic promotion follows a small screen;
latency and cost remain descriptive unless comparability is established. If this
clarity candidate shows no worthwhile benefit or introduces regression, retain
the baseline. A paid run requires a new bounded allocation; this record does not
reopen an earlier budget.

## Offline verification

Reproduce these assertions from the repository root with the checked-in
[offline verifier](./identification-evaluation-evidence/2026-09-27-openai-prompt-review/verify.ts).
It reads only the edit manifest, constructs synthetic requests in memory and
prints content-free pass evidence. It imports the reviewed production builders
but never an adapter, executor, credential loader or network client.

```bash
deno run --frozen --no-prompt --cached-only --deny-env --deny-net \
  --config services/supabase/functions/deno.json \
  --allow-read=docs/rfcs/identification-evaluation-evidence/2026-09-27-openai-prompt-review/prompt-edits.json \
  docs/rfcs/identification-evaluation-evidence/2026-09-27-openai-prompt-review/verify.ts
```

Run at the reviewed source or a descendant retaining the same fingerprints.
`--cached-only` requires the repository's frozen dependencies to be available
locally; a missing dependency stops before verification.

Verification results are recorded below after running the exact manifest against
synthetic requests with network and environment access denied. No credentials,
user media, production response bodies or new model calls are needed. The
synthetic image bytes are structural fixtures, not a biological accuracy test.

- All four source fragments matched exactly once; reversing the replacements
  restored the baseline instruction byte for byte.
- Three synthetic visual requests passed: one photo, photo plus description, and
  two photos with description, visual context and capture context.
- Only `instructions` differed in each candidate request. Input order/content,
  schema, explanation definition, generation settings and source requests were
  preserved. The text-only baseline and shared Gemini prompt/schema were
  unchanged.
- All 14 fields named by the affected directions are required and nullable in
  the current OpenAI schema. A synthetic non-biological null-valued draft
  decoded successfully; deleting `scientific_name` was rejected.
- The proposed profile is rejected by the current profile guard and snapshot
  builder. No evaluator registration, production binding or provider call was
  added.
- Candidate prompt fingerprint:
  `8d8c5ab7f612555a0a275ade42de7615f327314c644502ab5d2217c1bab1f948`.
  Fingerprints use the existing `fingerprintJson` canonical representation.
  Baseline prompt and schema fingerprints are retained in the edit manifest.
- Visual instructions increased from 11,065 to 11,121 UTF-8 bytes. These are
  bytes, not token counts; there is no input-size saving claim.

Runtime implementation, live candidate execution and production qualification
are not completed by these checks.

## Evidence used

- [Existing OpenAI adapter and strict-output tests](../../services/supabase/functions/_shared/ai/openai_test.ts).
- [Matched Gemini/OpenAI results](./identification-gemini-openai-matched-results-2026-09-27.md),
  for the completed baseline and its limits.
- [Earlier optimization plan](./identification-provider-optimization-plan.md),
  for retained OpenAI token/cache observations.
- [Evaluation profile and controller contract](../../services/supabase/scripts/identification_evaluation/README.md#reusable-profiles-and-experiment-controls-optimization-slice-2),
  for fingerprinting and admission boundaries.
- [OpenAI prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering),
  for separating task instructions from supplied context; no model migration or
  generic prompt rewrite is selected.
