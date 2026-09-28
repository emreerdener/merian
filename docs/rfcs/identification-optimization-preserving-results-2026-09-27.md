# Identification optimization while preserving current results

Date: 27 September 2026\
Status: Planning only; provider infrastructure milestone verified before this
plan was started. Production remains Gemini.

## Decision

Improve identification speed, cost and reliability while retaining the current
explanation format and level of detail. Shortening OpenAI explanations is not a
selected optimization. We will first identify the remaining bottleneck, then
implement and measure one justified change at a time.

This is the current optimization plan. The
[earlier plan](./identification-provider-optimization-plan.md) remains the
record of implemented measurement and experiment controls. Its
[concise-explanation screen](./identification-openai-concise-screen-2026-09-26.md)
stays closed and inconclusive. We will not repair or repeat that experiment as a
prerequisite to this work.

## Initial infrastructure milestone is complete

[PR 87](https://github.com/emreerdener/merian/pull/87) merged at
`2f733e83ae24fa90d8a222cf6635905fda265720`.
[Production deployment 1819](https://github.com/emreerdener/merian/actions/runs/36363524196)
passed candidate validation, deployment and backend smoke checks. Its deployment
log confirms that the GitHub Production `NATUREBOOK_OPENAI_API_KEY` was
synchronized to Supabase project `qlarqavoqhkuwzmevrmf` and its stored digest
was verified; the optional synchronization was not skipped.

This closes the current infrastructure work. OpenAI dispatch remains disabled in
reviewed source and current assignments remain Gemini. Permission collection,
released-client compatibility, held-out qualification and deliberate OpenAI
activation remain separate follow-up work under the
[photo integration plan](./identification-openai-photo-integration-2026-09-27.md).
The iOS archive/upload and released-build upgrade check also remain separate.
None of these deferred release tasks is implicitly completed by this plan.

## What must stay the same

- Preserve the current result fields, explanation structure and detail,
  alternatives, uncertainty and safety behavior. Do not shorten output, lower
  output limits or stream an unvalidated identification to create a speed gain.
- Preserve the complete observation: optional description text, ordered image
  snapshots and accompanying audio when present. A five-second video supplies
  snapshots from each second, not native video. Unsupported evidence cannot be
  discarded to fit another provider.
- Keep app-controlled provider assignment, recipient permission, quota,
  moderation, durable saving and retry/replay protections. No speculative paid
  requests, automatic cross-provider fallback or reuse of a result merely
  because another photo looks similar.
- Retain historical benchmarks, inputs, profiles and claims. The existing
  no-description comparisons remain useful development evidence; they do not
  need repeating simply because optional text exists. Changing input preparation
  or model configuration still needs evidence for that particular change.

## Optimizations worth investigating

These are hypotheses, ordered by the amount of behavior they could change. They
are not a commitment to implement every row or a promise of faster results.

| Priority | Candidate                                      | Potential value and first check                                                                                                                                                                                                               |
| -------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1        | Remove repeated local preparation and lookups  | Avoid unnecessary encoding, schema preparation or data reads. Trace existing reuse before adding a cache; verify identical prepared requests and results.                                                                                     |
| 2        | Reduce remaining serial work                   | Overlap genuinely independent operations or move optional work off the response path when the current durability contract allows it. Identify an actual blocking span first; required moderation and persistence still finish before success. |
| 3        | Improve native prompt-cache reuse              | Keep stable instructions and schema consistent, with changing observation content separate. Measure actual cache hits, latency and net cost for each provider; stable prefixes already exist.                                                 |
| 4        | Simplify redundant input instructions          | Remove demonstrated duplication or conflicting instructions while preserving all evidence, result-format instructions and safety requirements. This changes the input prompt, not the requested explanation length.                           |
| 5        | Test media or model settings only if justified | If the remaining bottleneck is image processing or model computation, evaluate one preparation or native-setting change. Reduced image detail, resolution or reasoning can affect identification and require a separate quality comparison.   |

Fewer sequential calls and parallel independent work can help latency, but
reducing input tokens alone need not create a meaningful speed improvement.
[OpenAI latency guidance](https://developers.openai.com/api/docs/guides/latency-optimization)
provides the general mechanisms; our measured path determines which apply.

Provider-native caching also needs separate treatment. OpenAI documents prefix
reuse, while Gemini Generate Content distinguishes implicit reuse from explicit
cache objects with their own lifecycle and costs. We will measure the supported
behavior of our exact profiles, including cold requests, rather than assume
cache savings or add padding and paid warm-up requests.
[OpenAI caching](https://developers.openai.com/api/docs/guides/prompt-caching)
and
[Gemini Generate Content caching](https://ai.google.dev/gemini-api/docs/generate-content/caching)
are the implementation references. Explicit Gemini cache objects are a later
option only if measured reuse justifies their cost and complexity.

## Build on the existing implementation

The [AI owner map](../../services/supabase/functions/_shared/ai/README.md) owns
request construction, adapters and result policy. Shared optimizations should
benefit the common path where possible; Gemini and OpenAI retain separate,
versioned profiles and native settings.

The
[evaluation tooling contract](../../services/supabase/scripts/identification_evaluation/README.md#reusable-profiles-and-experiment-controls-optimization-slice-2)
currently admits fixed baseline profiles and the retained concise-specific v2/v3
experiments. It is not an arbitrary candidate runner. Any new hypothesis in
Slice 3 requires reviewed profile registration and the corresponding controller,
reporting and accounting support before live use. Existing secrets, packet edits
or a different experiment ID cannot supply that support.

The current OpenAI baseline already uses low reasoning effort and high image
detail. Both provider builders already separate system instructions from the
observation, and the shared identification schema is cached. The app already
[downsamples inference images](../../apps/ios/Merian/Core/Data/Images/MediaPreparationActor.swift)
under a central
[preparation policy](../../apps/ios/Merian/Core/Data/Images/Policies/ImagePreparationPolicy.swift).
The
[primary handler](../../services/supabase/functions/identify-multimodal/index.ts)
already combines dictionary hydration, parallelizes fallback lookups and
candidate enrichment, and backgrounds some optional writes. Audit the remaining
work rather than recreating these mechanisms.

Keep durable scan finalization on the required success path. Reuse within an
attempt must not reuse stale consent, assignment or account state across
attempts. A future cache must have explicit ownership, invalidation and bounded
retention; credentials or private observations do not belong in cache keys or
logs.

## Implementation slices

1. **Locate the bottleneck using existing evidence.** Read the completed
   comparisons and the existing
   [app measurements](../development-guides/21-identification-app-measurement.md).
   Map local preparation, provider time, remaining Edge work and first-render
   time to their owners. Mark coverage gaps and overlapping spans. Deliver a
   short ranked finding and select one candidate with a measurable acceptance
   target. This first slice needs no new provider calls or broad benchmark run.
   If evidence is insufficient, specify only the smallest missing measurement.
2. **Make one shared improvement if the audit supports it.** Prefer eliminating
   duplicate work while preserving prepared media and requests. Use focused
   parity, failure and concurrency checks plus the required affected-surface
   gates. If the code already handles the suspected inefficiency, record that
   finding and skip the change. A local speedup is not a claimed app speedup.
3. **Evaluate one provider-specific candidate if needed.** Use the existing
   controlled evaluator and separately version the changed cache policy, prompt,
   media preparation or native setting. Keep the frozen baseline intact and
   change one variable. Declare the bounded run and acceptance criteria before
   any paid calls; this document does not revive the old experiment's budget.
   Retain a candidate only when its measured benefit meets the target without a
   quality, safety or explanation-format regression.
4. **Close the optimization milestone and then plan OpenAI audio evaluation.**
   Record the adopted change or the decision to keep the baseline. Audio needs
   its own complete-input adapter and animal/environment-sound evaluation;
   transcription alone is not identification. Sampled-video qualification also
   remains a separate route. Neither is silently added to the photo benchmark.

## Evidence and stopping rules

Reuse the existing measurement, accounting and evaluation machinery. Keep
provider time, Edge time and app time distinct; detailed server spans overlap
and cannot be added together. Report sample counts and missing coverage. The
six-photo development comparison does not support a general app speed claim.

For a selected live candidate, compare matched cases and record source,
preparation, prompt/schema, model, profile and cache condition. Include cold
requests, retries, failures and unknown usage in the report. Preserve missing
costs as unknown; assess total attempt cost, including cache charges where
applicable. Report medians and use tail percentiles only with sufficient data,
without presenting small samples as population estimates.

Retain the existing formal quality and qualification requirements in the
[evaluation PRD](../product/04-identification-evaluation-prd.md) and
[SRD](./identification-evaluation-srd.md). A changed profile needs checks for
identity, supported rank, abstention, uncertainty, explanation grounding and
format, plus safety and result-contract behavior. Use the existing review tools
where appropriate; this plan adds no new owner practice exercise.

Stop after the selected bounded comparison. A failed, inconclusive or unhelpful
candidate leaves the baseline in place; it does not automatically start another
paid parameter sweep. Production adoption, permission collection and release
retain their separate gates. BioCLIP, custom-model training and family plans are
outside this milestone.
