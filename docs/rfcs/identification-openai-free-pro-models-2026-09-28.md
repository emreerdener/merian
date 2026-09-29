# OpenAI photo models for Free and Pro

Date: 2026-09-28

Status: Slice 1 implementation and local verification complete. Closed Luna/Sol
profiles, the real 12-photo packet and the durable local controller are
prepared. The owner approved a $40 maximum for the same 18-call Naturebook
comparison on 28 September. Execution requires the credential-bound approval and
existing Naturebook key. The first live screen subsequently stopped after one
Luna call because an explanatory comparison lacked reference coverage; see the
[screen result](identification-luna-sol-photo-screen-results-2026-09-28.md). The
full comparison remains incomplete. The owner subsequently
approved preserving reference gaps as unassessable and continuing only the
seventeen unattempted assignments within the same combined 18-call/$40 limit.
The continuation completed the five remaining screening calls; all six primary
outcomes matched, but the mineral explanation failed the specificity criterion.
The protocol stopped before the twelve challenge calls, so no Sol control ran.
Slice 2's current decision is to retain Sol for both tiers; Luna qualification
and a comparative Free/Pro advantage are unestablished. Production assignments
are unchanged. The next
[Luna evidence-limit candidate](identification-luna-evidence-limits-candidate-2026-09-28.md)
is implemented as a separate prompt/profile and v3 local comparison plan. It
preserves the stopped results, uses unchanged Sol as control and has made no
paid requests. Its new bounded spending approval remains separate.

## Proposed tier assignment and current decision

The screening result does not yet support activating Luna. Retain the existing
Sol assignment while a later candidate addresses non-biological specificity and
receives its own bounded evaluation. The original target design below remains a
proposal.

Introduce separate, versioned OpenAI photo profiles selected by the backend's
existing Free/Pro admission decision. Evaluate Luna for Free and retain the
current Sol configuration for Pro:

| Role                               | Model        | Reasoning effort | Purpose                                                                                                 |
| ---------------------------------- | ------------ | ---------------- | ------------------------------------------------------------------------------------------------------- |
| Free candidate                     | `gpt-6-luna` | `low`            | Reduce everyday photo-identification cost while preserving useful results.                              |
| Pro, current control, and rollback | `gpt-6-sol`  | `low`            | Retain the production photo configuration already in use.                                               |
| Optional later Pro optimization    | `gpt-6-sol`  | `medium`         | Evaluate separately if more reasoning offers enough quality improvement to justify added time and cost. |

This is the simpler first release: qualify one new Free model while preserving
Pro's current execution settings. Model family alone does not prove a quality
gap on our observations; the comparison must record the actual differences. An
older Pro model remains a possible later cost experiment, outside the initial
shortlist. Naturebook Pro does not require OpenAI's latest flagship or its
separate `pro` reasoning mode.

Keep the current explanation format, detail, result fields, and Strong /
Possible / Weak labels. Pro should offer more capable analysis of difficult
observations, including appropriate uncertainty when the photograph cannot
support a species.

## Scope and existing foundation

The first release covers the existing `multimodal_photo_v1` input profile,
including optional notes already supported by that profile. The main evaluation
uses photos without descriptions, matching expected usage. Deterministic tests
must still cover optional notes and multiple-photo Pro eligibility.

Audio, video-frame collections, mixed media, description-only requests, Field
Chat, and enrichment retain their existing assignments. A video supplies sampled
images and any companion audio; its capture provenance and complete input
profile still require a separate qualification even when the visual evidence is
images.

The current
[OpenAI photo adapter](../../services/supabase/functions/_shared/ai/openaiPhoto.ts)
and
[request builder](../../services/supabase/functions/_shared/ai/openaiRequest.ts)
use `gpt-6-sol`, low reasoning, high image detail, an 8,192-token output limit,
and a 90-second timeout for both admitted tiers. The
[registry](../../services/supabase/functions/_shared/ai/registry.ts) recognizes
Free and Pro admission, but resolves both to that same photo configuration.

The provider foundation is reusable. Implementation must extend its closed,
reviewed profiles: changing one model string or adding a client model selector
would miss database constraints, moderation compatibility, immutable attempt
records, and native confidence presentation.

The
[confidence display work](identification-openai-confidence-display-2026-09-28.md)
in [PR #99](https://github.com/emreerdener/merian/pull/99) was still open when
this plan was prepared. Its native implementation recognizes the existing
complete photo profile. Merge and distribute the necessary reader support before
enabling new profiles that depend on it; this plan does not describe that
distribution as complete.

## Why these candidates

Official OpenAI model documentation was checked on 28 September 2026. Both
models support image input and structured output with the Responses API. The
following published standard token rates are useful for shortlisting; they are
not measured prices per identification.

| Model and source                                                       | Uncached input / million tokens | Cached input / million tokens | Output / million tokens |
| ---------------------------------------------------------------------- | ------------------------------- | ----------------------------- | ----------------------- |
| [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) | $0.10                           | $0.01                         | $0.50                   |
| [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)   | $2.00                           | $0.20                         | $10.00                  |

Luna is a useful cost candidate: its listed uncached input and output rates are
one twentieth of Sol's at these prices. This is a per-token comparison, not a
claim that identifications will cost one twentieth as much. Actual image token
usage, reasoning, and caching can differ. Keeping Sol-low for Pro preserves the
model and reasoning settings that are already used for every OpenAI photo scan.

Retain low effort and the existing output limit in this first release. More
reasoning can improve some decisions but also consumes billed output tokens and
may take longer. The output limit includes reasoning as well as the visible
response. Test Sol-medium only as a separately versioned optimization with a
specific quality goal; do not silently increase the limit or truncate the
explanation. See the
[OpenAI reasoning guide](https://developers.openai.com/api/docs/guides/reasoning).

Before freezing a run, verify project access, supported request parameters,
returned model identity, native input/output moderation, and current
[deprecation notices](https://developers.openai.com/api/docs/deprecations). Use
a specific available snapshot when offered, and otherwise record the model ID,
execution date, and returned version information. Do not invent snapshot IDs or
silently follow a `latest` alias.

## Product and routing rules

1. **Select from server admission.** The backend determines the effective plan,
   then assigns the reviewed photo profile. No request parameter or app setting
   lets a customer choose the provider or model.
2. **Map the reserved database plan explicitly.** `free` selects the Free
   profile; `pro_paid` and `pro_complimentary` select the same Pro profile,
   including an already-admitted complimentary hold. Retained `pro_trial`
   reservations remain Pro-funded; new legacy-trial admissions are possible only
   while the existing rollout mode permits them. Replays retain their recorded
   execution profile. Use the reservation's `effective_plan`, never the current
   UI tier or subscription state. Follow the existing rollout mode and
   precedence in the
   [entitlement contract](../backend-and-data/18-complimentary-pro-scans.md);
   this work does not activate or change the complimentary offer.
3. **Preserve quota and retry semantics.** Keep Free limits, Pro eligibility,
   holds, and settlement unchanged. Select once per admitted attempt. An
   idempotent replay uses its original profile; a legitimately new metered
   attempt follows the existing admission policy and records its new profile.
4. **Preserve observation history.** Store the actual model, reasoning settings,
   prompt, schema, safety policy, and binding with each result. A subsequent
   subscription change does not reinterpret an earlier Free result as Pro.
5. **Use one generation per normal attempt.** This milestone does not add an
   automatic second-model call, automatic paid escalation, or silent provider
   fallback. Existing explicit retry/reanalysis continues through its existing
   eligibility and admission controls.
6. **Keep the beta permission decision.** The existing deferral of
   OpenAI-specific collection/enforcement remains in place. General onboarding
   requirements and account authorization retain their current behavior.

## Shared instructions and model-specific settings

Keep one identification contract for taxonomy, evidence, abstention,
uncertainty, explanation structure, and response fields. Preserve the evaluated
production prompt and high-detail media preparation in the first comparison.

Add a versioned Luna execution profile for model ID, reasoning effort, output
cap, timeout, and supported API settings. Bind each exact profile to its
moderation and confidence policies. Reuse the original `openai_photo_v1` tuple
unchanged for Pro, existing records, and rollback. A later Sol-medium experiment
would have its own version; it is not part of the first activation.

Gemini continues to use its own adapter and provider-specific request settings.
Provider-specific wrappers may differ, while product expectations remain shared.
The existing explicit-null and concise-explanation experiments remain historical
or separately evaluated candidates. Combining them with a model change would
prevent us from attributing the result to the new model configuration.

Native moderation must continue to cover the input and output of the same
production request. Verify the current `omni-moderation-2024-09-26` policy with
each selected model and account; general model support does not prove that exact
combination works. See the
[moderation guide](https://developers.openai.com/api/docs/guides/moderation).

## Confidence and presentation

A more capable Pro configuration can produce a better-supported identification
and a higher confidence result. Use the score and exact execution profile from
that analysis to choose the badge.

Extend native recognition to each selected complete profile and review its
Strong / Possible / Weak display policy. The current schema-anchored 0.95/0.60
cutoffs are the initial provisional reference. Different Pro cutoffs require
support from the new profile's evidence and score meaning; Gemini's cutoffs are
not a substitute for that review. A small model-selection pilot can support a
provisional display decision without establishing calibrated probabilities.

Keep display policy separate from reward eligibility, automatic acceptance,
public confidence metrics, and benchmark calibration. Preserve
`openai_unqualified_v1` until a separate qualification supports changing those
uses. Unknown or damaged profiles retain the existing fallback. A purchase alone
does not change the stored score or badge.

Product copy may distinguish standard and Pro analysis once the execution is
actually different. Keep provider/model version details in provenance and
support information, and preserve the current explanation layout.

## Bounded comparison using existing evidence

Reuse the
[27 September matched benchmark](identification-gemini-openai-matched-results-2026-09-27.md).
It contains six photo cases per provider: five biological references and one
non-biological control. Both providers matched those provisional references; the
OpenAI provider-call median was 7.10 seconds. That run used the evaluation
binding, without the production binding's inline moderation. Reuse its inputs,
references, and historical findings; it is not a measured production-profile
quality, cost, or latency control. The current `openai_photo_v1` Sol-low binding
remains the rollback destination based on its separate integration and rollout
record.

The [OpenAI changelog](https://developers.openai.com/api/docs/changelog) reports
a Sol/Luna image-encoding fix on 25 September. The 27 September benchmark
follows that published change, so the notice alone does not require repeating
it.

Prepare one small new comparison:

- Reuse the six approved photo inputs and their existing references.
- Add six reference-backed difficult or ambiguous photos before viewing
  candidate outputs. Include lookalikes, insufficient diagnostic detail,
  distracting backgrounds, and non-biological controls. Freeze acceptable
  species or higher ranks and abstentions in advance. Uncertain references
  cannot decide a winner.
- Run Luna-low once on each of the 12 cases. On the six new challenge cases,
  interleave the current Sol-low production binding as the Pro control. Both use
  the exact production input/output moderation configuration. This gives **18
  generation requests maximum**: 12 Luna calls and six Sol controls, with a
  revised, explicitly approved **$40 total ceiling**. Freeze and validate the
  actual worst-case cost before execution; stop before a request that cannot fit
  the remaining ceiling. Use the first frozen case as each profile's
  compatibility check, counting it toward the limit. No automatic reruns or
  replacement of failures with successful attempts.
- Interleave candidate calls on identical bytes and context. Record completion,
  taxonomic correctness at the justified rank, unsupported specificity,
  explanation support, moderation outcome, latency, usage, and total cost per
  usable result. Include reasoning, cache writes when applicable, and failed
  billable calls; missing billing evidence remains unknown.
- The assistant performs the evidence-based review and writes the report. Keep
  model identity hidden during qualitative scoring where practical. Record that
  review and reference limitations honestly; do not require the owner to score
  every explanation or invent a second human reviewer.

Screen Luna on the six existing cases first. Stop on a wrong identification,
actual explanation failure, unavailable or uncertain review, technical/safety
failure or unknown billing before spending on challenge cases. The approved
continuation permits only missing-reference ratings
(`not_assessable / insufficient_reference`) to proceed, preserving each gap in
the report rather than counting it as a quality pass. For the release decision:

- Luna must preserve the five biological matches and the non-biological control,
  complete schema and safety checks, and the current explanation quality. Sol's
  production configuration remains unchanged.
- Free should reduce measured cost by at least 50% against the six
  contemporaneous Sol-low controls on the challenge cases, using the same
  pricing basis. It must handle the non-biological controls and avoid
  unsupported Strong claims. Missing usage or price evidence leaves the cost
  target unverified.
- Compare the difficult-case decisions directly: correct identifications at the
  justified rank, appropriate abstentions, unsupported specificity, and Strong
  claims. Record where each model wins or loses. Material Free quality failures
  block switching Free to Luna. A tie supports a cost-saving Free option but
  does not demonstrate a Pro accuracy advantage; do not manufacture a difference
  through display thresholds. These are pilot selection rules, not population
  accuracy guarantees.
- Initial provider-call latency targets are a median of at most 8 seconds for
  Free and 15 seconds for Pro. Report all timings and the maximum as well; this
  sample does not establish a reliable tail-latency percentile or mobile
  end-to-end speed.

If Luna fails the quality or cost goals, retain Sol-low for both tiers and
document that outcome. If Luna passes, select it for Free while retaining
Sol-low for Pro. Sol-medium and older-model experiments require a separate,
bounded comparison; they do not extend this run automatically. Do not rerun
Gemini or repeat the whole earlier benchmark. The new controls support a small
paired comparison on challenge cases only; they do not establish a general
relative-speed claim or replace the historical benchmark.

The initial cost and latency targets are proposed engineering goals. A final
selection report must state whether they were met, total expected cost at
current scan limits, and any explicit product tradeoff before activation.

## Implementation checkpoint: 28 September

Implemented locally:

- Immutable `openai_photo_luna_low_v1` and `openai_photo_sol_low_v1` evaluation
  profiles, sharing the exact production photo payload and moderation decoder.
  The Sol control changes no production request settings.
- Exact model and full native moderation validation before accepting a draft;
  unsupported media/configuration changes reject before dispatch. Production
  registry, database admission and historical evaluator profiles stay closed.
- Offline `preflight-free-pro-photo`, binding all 12 cases, references, private
  explanation facts, pricing and source identity to an 18-assignment schedule.
  It performs no provider calls and always reports dispatch unauthorized.
- A dedicated local controller and existing hidden-key launcher integration,
  with immutable claims, whole-schedule reservation, six-case screen barrier,
  transient assistant review, content-free results and no repeat of interrupted
  attempts. A separate v2 plan and credential/source-bound approval are required
  before any live call. The owner approved the v2/$40 revision without changing
  the inputs, model profiles, call count or one-attempt limit.
- Regression coverage for request parity, model/safety failures, frozen inputs,
  retained reference controls, media containment and the cost ceiling.

The full-context reservation exposed a plan issue: at the reviewed global
Standard rates it totals $35.461008, so the proposed $5 cap cannot pass the
existing conservative method. The controller additionally reserves the 10%
regional premium, bringing its full reservation to $39.0071088. This is not
forecast spend. On 28 September, the owner explicitly approved a **$40 maximum**
for the same 18 calls in the Naturebook project. The private packet now uses
`photo_model_plan_v2` with that ceiling; the original v1/$5 proposal is
preserved privately for provenance. The approval does not authorize extra calls,
retries or production assignment changes. Do not infer token limits from image
byte counts. The
[provider guide](../development-guides/22-alternative-identification-provider.md#lunasol-photo-comparison-preparation)
records the implemented boundary and next preparation steps. The
[real packet preparation record](identification-luna-sol-photo-preparation-2026-09-28.md)
now records all twelve photos and the pre-output reference review. It passed the
offline preflight with zero provider calls. Local implementation and
verification are complete, and the spending decision is resolved. Slice 2 uses a
credential-bound approval for the reviewed clean revision and the existing
Naturebook key. The assistant performs the transient explanation reviews.

After the first reference-coverage stop, the owner approved a separate
continuation without changing those frozen inputs or the spending ceiling.
`photoModelContinuation.ts` and the distinct `--photo-model-continuation-live`
mode inherit the first completed call and its reservation, preserve the original
journal, and permit only seventeen new claims. Their private approval binds the
new clean source and original artifact digests. Tests cover inherited
accounting, reference-gap retention, original and sibling locking,
historical/current approval windows, tamper detection and no repeat of
interrupted or completed calls. The continuation does not qualify a model; Slice
2 still requires the combined results and selection record.

## Implementation slices

### Slice 1: versioned profiles and evaluation preparation

Extend the closed OpenAI profile types, request construction, moderation checks,
and evaluator contracts while production keeps its existing assignment. Preserve
old evaluation IDs and records. Prepare the approved-input manifest, challenge
references, price assumptions, and request/cost cap. Reuse the existing
credential delivery and
[evaluation infrastructure](../development-guides/22-alternative-identification-provider.md).

Exit: deterministic profile, capability, schema, and safety tests pass; the
exact comparison is ready to run. No production assignment changes are part of
this slice.

### Slice 2: one bounded comparison and a selection record

Execute the prepared comparison when authorized, complete the review, and select
profiles only if the stated goals are met. Record confidence-display decisions
and unresolved reference limitations alongside quality, cost, and timing.

Exit: a named configuration for each tier, or an explicit decision to retain the
current profile. A failed candidate does not expand the experiment
automatically.

### Slice 3: tier-aware admission and compatible readers

Add forward migrations for the Luna binding and attempt constraints without
activating it. Preserve the existing Sol binding for Pro. Preserve the
database's quota-policy `model` key; actual provider selection uses
`provider_model` and the versioned binding. Update registry, admission, result
validation, and provenance together. Update executable schemas and regenerate
the corresponding DTOs if the new closed profile tuples change those contracts.

Add native recognition and display policies for the selected tuples. Verify live
results, queued completion, explicit retries, restored history, historical Free
results after upgrading, included Pro admission, and rejected client-selected
models. Cover subscription/entitlement changes during an in-flight attempt.

Keep the existing V2 response shape if sufficient. Evaluate compatibility
against actual shipped readers: some readers deliberately fall back for
unfamiliar profiles. Distribute reader support first and use the established
protocol gate if required; do not assume protocol 4 alone recognizes every
future profile.

Exit: affected full backend/database and iOS gates pass, saved observations
remain readable, and the client rollout and independent assignment rollback are
ready.

### Slice 4: activate and observe

Use the
[deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md) for
the selected backend revision and compatible native build. Verify that all
admitted Pro plans retain Sol-low, then activate the Free Luna assignment and
perform a short, bounded check of ordinary beta traffic. Record
completion/errors, model identity, latency, and priced usage by profile. Do not
add duplicate shadow calls to customers' scans.

Free can return to the original Sol-low binding independently of Pro. A future
Pro profile change must retain the same independent rollback ability. Rollback
changes future admissions and preserves in-flight attempt snapshots and stored
results. Retain the existing beta permission behavior and unrelated Gemini
routes.

Exit: both intended assignments are verified on compatible clients, with a dated
release record and rollback evidence. Resume prompt optimization as a separate
measured change, then proceed to the separately scoped OpenAI audio evaluation.
