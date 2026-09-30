# AI provider boundary

All four identification routes (`identify-multimodal`, `identify-describe`,
`identify`, and `audio-spec`) and the biological overview, lookalike, and
group-tag helpers use this boundary. Their user enrichment and claimed
public-job callers retain separate admission paths. The beta catalog selects
OpenAI only for still-photo identification; audio, video snapshots, mixed
observations, text-only, legacy routes and enrichment remain Gemini. See the
[slice tracker](../../../../../docs/rfcs/identification-foundation-srd.md#implementation-slices).

## Ownership

- `contracts.ts` defines SDK-independent task input, authority, immutable
  attempt configuration, usage, and outcomes. Primary identification accepts
  ordered text, images, and prepared WAV audio with positional source lineage;
  legacy image, audio, and description routes retain their own input variants.
  Content requests carry a scientific name plus locale or taxonomy as
  appropriate. `service_job` supports claimed public-fact work and is rejected
  for identification. These types carry existing admission decisions; they do
  not authenticate callers or validate job claims.
- `identificationInput.ts` validates and classifies the complete normalized
  observation before reservation. It distinguishes compatibility variants and
  primary text, photo, audio, photo/audio and sampled-video representations. The
  registry recomputes the profile before preparation; changed or missing
  assignment evidence cannot dispatch. This classifier never chooses a provider.
- `admission.ts` defines the closed identification assignment returned by the
  service-only `reserve_identification_quota` RPC. The four identification
  callers require its database-owned provider, binding, input profile and
  recipient permission; missing or unknown assignment metadata cannot authorize
  fresh work. Durable quota-attempt snapshots preserve each metered generation.
  The additive caller-bound recipient preflight is advisory. Edge accepts an
  optional denial-only recipient expectation and uses a ten-argument admission
  overload to stop fresh work if assignment changed. Identification capability 4
  or 5 selects the eleven-argument overload independently of entitlement
  protocol 3. Native source advertises 5; binding minima remain 0 or 4. Native
  preparation now validates that result, preserves the expectation across
  retries and rechecks the applicable local permission before dispatch. The beta
  catalog assigns still photos to OpenAI and other profiles to Gemini; the
  [beta correction](../../../../../docs/incidents/2026-09-beta-openai-consent-gate.md)
  defers OpenAI-specific permission collection and enforcement. See the
  [admission contract](../../../../../docs/backend-and-data/05-api-contracts.md#provider-bound-identification-reservations).
- `registry.ts` independently checks that identification assignment and resolves
  `gemini_baseline_v1` or the exact `openai_photo_v1` from the database-selected
  execution model and, where applicable, the admitted tier. It checks task,
  complete representation, operation, recipient permission and reservation
  metadata before commitment. No client field, environment variable, provider
  name, or URL can select another adapter.
- `contentRegistry.ts` binds the three content tasks to their existing quota
  operations and generation settings. User authority carries its admitted model,
  permission, and reservation. Service authority carries a claimed job, matching
  public-fact task, bounded attempt, and the fixed Flash model; its permission
  and user quota policy version are null.
- `production.ts` composes the registry with Gemini or the enabled OpenAI
  still-photo adapter. The database assignment, input profile, recipient
  authorization and client minimum remain authoritative. Deploy this enabled
  composition before changing photo assignments; preparation failure still
  refunds unused quota. Tests inject their deterministic adapter through
  internal handler injection and the shared executor; its implementation is
  confined to a test file.
- `multimodalResultPolicy.ts` independently qualifies primary result handling
  before quota commitment. It derives the normalization threshold from the
  admitted snapshot and exposes Gemini safety signals only for a matching
  supported profile. The exact OpenAI photo profile uses unqualified confidence
  and requires its own allowed native moderation before promotion. Unknown
  policies, including OpenAI evaluation snapshots, cannot invoke or reach
  durable media promotion. Adapter registration alone cannot qualify confidence
  or safety; see the
  [photo integration plan](../../../../../docs/rfcs/identification-openai-photo-integration-2026-09-27.md).
- `execution.ts` permits one invocation per prepared attempt and records its
  duration. It owns no quota, persistence, retry, failover, or cancellation
  based on a disconnected foreground request.
- `geminiRequest.ts` assembles native parameters without SDK runtime imports or
  environment access, allowing offline evaluation to share exact prompts,
  schemas and settings. `gemini.ts` wraps that projection with existing content
  parameters and decodes text, JSON, finish reasons, model version, usage, and
  the safety probabilities consumed by the existing moderation policy. It reuses
  `../gemini.ts` for credentials and the existing 90-second HTTP deadline. SDK
  setup is checked before commitment; schema/instructions are captured during
  preparation. Existing schema projections remain in
  `identify-describe/schema.ts` and `../identify/schema.ts`. Primary audio,
  text, and blended instructions live in `identify-multimodal/instructions.ts`;
  the existing vision instruction remains in `../identify/schema.ts`. The
  distinct legacy audio instruction lives in `audio-spec/instructions.ts`.
  `geminiContent.ts` owns the unchanged content prompts, schemas, locale, and
  normalized taxonomy projection. `../biology.ts` retains domain-result
  normalization and existing usage/analytics ownership.

The handler owns current consent/entitlement admission, the lease and durable
ledger, commitment immediately before invocation, domain and wire validation,
and required persistence. Completed work replays before provider preparation.
Unknown provider execution remains charged and follows existing retry admission;
unknown scan persistence retains its existing recovery ownership. Preparation
failure refunds unused quota. Refusals and malformed/truncated output retain
their distinct terminal/retryable responses.

## Durable identification provenance

`provenance.ts` projects the admitted execution snapshot into a closed,
versioned value saved with the scan by all four identification producers. It
records the requested model, binding, prompt/schema/confidence references,
policy version, variant, operation, thresholds, safety profile, timeout and
generation settings. V1 preserves Gemini's five generation fields and explicit
nulls. V2 records OpenAI `max_output_tokens`, `reasoning_effort` and
`image_detail`, without manufacturing Gemini settings. It never serializes model
output, returned model text, observation context, media, owner/attempt
identifiers or timing.

Migration `20260926160249_persist_identification_result_provenance.sql`
atomically copies each new scan's value into its exact owner/scan ingestion job.
Both values are immutable. A duplicate insert preserves the original result; a
separately admitted retry resolves its own snapshot before it can produce a new
durable result. The existing recovery RPC cannot supply provenance from its
client JSON: an insert trigger restores only an existing server backup. Missing
historical evidence stays null, including recovery of a result that never
reached the scan-insert transaction.

These fixed configuration facts intentionally share the scan's existing Data API
visibility. They are not private operational telemetry. The backup follows
existing ingestion-job ownership and retention. Fresh Identify envelopes expose
that same value through optional `data.identification_provenance`;
reconstruction uses the immutable scan column and stored envelopes preserve
their original value or omission. Generated native DTOs retain required null
settings, and V52 local storage preserves the metadata for profile-aware
confidence presentation. See the
[server record](../../../../../docs/rfcs/identification-provider-result-provenance-2026-09-26.md)
and
[client record](../../../../../docs/rfcs/identification-client-result-provenance-2026-09-26.md)
for rollout order, compatibility and remaining activation work.

Migration `20260927165545_accept_openai_identification_provenance_v2.sql`
extends only the pure bounded validator. V1, recovery/immutability triggers,
privileges and existing rows remain unchanged. Generated Swift decodes by
version, rejects cross-version settings and preserves both versions in the
existing opaque V52 storage. V2 receives no Gemini confidence or metric bands.
Future admission must require a client protocol that can decode V2 before any
OpenAI production result is emitted.

## Alternative-provider evaluation

`openaiRequest.ts` and `openai.ts` implement an evaluation-only `gpt-6-sol`
photo/text binding through the same generic single-invocation interface. The
beta catalog selects the separate `openai_photo_v1` user-request binding for
still photos and retains Gemini for other complete-input profiles. The pure
request builder derives strict JSON from the common Identify contract; the
bounded REST adapter accepts only an explicit evaluator-supplied credential.
Scripts select it only through `identification_evaluation/providers.ts`.
Unsupported audio/snapshots reject the whole observation. OpenAI confidence is
unqualified and never inherits Gemini bands. The production composition can
dispatch only the exact admitted photo binding; evaluation profiles never
acquire production authority. See the
[alternative-provider guide](../../../../../docs/development-guides/22-alternative-identification-provider.md)
for permissions, pricing/usage mapping, offline demo and live comparison scope.

`openaiNullFields.ts` owns the separately versioned evaluation-only
`openai_photo_null_fields_v1` visual prompt. Four exact omission directions
become explicit null directions; baseline/Gemini prompts, schema, evidence,
explanation detail and native settings stay unchanged. Missing or repeated
source fragments reject preparation, and the reusable evaluator additionally
checks the frozen prompt/schema digests. Text-only, video and audio observations
are unsupported. The
[v4 experiment contract](../../../scripts/identification_evaluation/README.md#openai-explicit-null-candidate)
compares this candidate with the unchanged OpenAI baseline; it does not select a
production adapter or alter the photo binding.

`openaiPhoto.ts` separately prepares the production `openai_photo_v1` profile.
Its prompt `openai_identify_vision_observed_traits_v1` requests one to three
directly supported traits. The same owner projects only that instruction and the
trait schema description; the schema name `merian_openai_identify_v1`, 1–10
array bounds, explanation format and all other request settings stay fixed.
`createOpenAIPhotoAdapter` reuses the bounded transport, adding pinned inline
input/output moderation to one request and releasing a draft only after its
native safety policy allows it. Moderation rejection remains a refusal even if
generated JSON is invalid. Missing evidence cannot become Gemini safety ratings.
The registry, capability-aware admission and media-promotion path support this
exact binding. Beta catalog rows select it only for still photos; other profiles
remain Gemini. The source composition must be deployed before catalog
activation. Saved usage retains native output/cache-write counts and reported
cached tokens, without a Gemini tariff; see the
[safety contract](../../../../../docs/development-guides/10-safety-and-moderation.md#openai-photo-policy).

`openaiPhotoModels.ts` adds two closed evaluation configurations,
`openai_photo_luna_low_v1` and `openai_photo_sol_low_v1`. Their request builder
reconstructs the frozen original photo payload directly from `openaiRequest.ts`
with native moderation and changes only the model. Its original
`openai_identify_vision_v1` instructions and hashes do not follow later
production prompt revisions. The evaluation adapter shares production moderation
decoding, rejects a returned model mismatch, and cannot enter the registry,
production result policy or old evaluation profiles. Native request preparation
supports the production photo shape, including optional notes and multiple
images; the first comparison selects no-description photos. The
[preparation procedure](../../../../../docs/development-guides/22-alternative-identification-provider.md#lunasol-photo-comparison-preparation)
owns its offline packet preparation, separately approved durable local runner,
assistant review and spending limits.

`openaiLunaEvidenceLimits.ts` adds one separately versioned Luna candidate,
`openai_photo_luna_evidence_limits_low_v1`. Its pure request projection changes
only the geological evidence-limit and non-biological specificity instructions.
The two original model profiles, shared prompt and production Sol request remain
unchanged. Candidate preparation rejects prompt-anchor drift; the pinned prompt
hash and same-schema tests retain its identity. Only the separate v3 local
comparison and candidate approval admit execution. Native moderation, exact
model checks, generation settings and production exclusion remain in place.

`openaiSolRank.ts` owns the isolated Sol biological-rank candidate. It replaces
conflicting biological instructions and four schema descriptions while retaining
the strict JSON shape, explanation format, generation and moderation settings.
`createOpenAISolRankEvaluationAdapter` uses the same bounded transport, exact
Sol identity and native moderation decoder. Only the separately versioned Sol
local comparison admits this binding; historical evaluators, the production
catalog and production result policy reject it. See the
[rank-consistency plan](../../../../../docs/rfcs/identification-photo-rank-consistency-2026-09-28.md)
for assistant review, v2 mapping records, spending and interruption controls.

## Isolated explicit-primary Sol candidate

`openaiSolPrimary.ts`, `openaiSolPrimaryInstructions.ts` and
`openaiSolPrimaryContract.ts` prepare the separate
`openai_photo_sol_primary_low_v1` candidate. Its strict private output requires
species/genus/family/unresolved/non-biological resolution and explicit species
rank on up to two alternatives. `openaiSolPrimaryNormalization.ts` builds an
in-memory primary snapshot after existing normalization and deterministic
subject demotion. It does not emit durable provenance or select a species row.
Its contract, normalization and transport suites run in the candidate workflow
with network and environment access denied. The separate
`createOpenAISolPrimaryEvaluationAdapter` reuses the bounded transport while
selecting the explicit-primary decoder; legacy adapters keep their existing
decoder. Exact Sol identity, native moderation, deadline, response ceiling and
single invocation remain required. Historical schemas, prompts and production
admission remain unchanged. The
[candidate checkpoint](../../../../../docs/rfcs/identification-primary-resolution-contract-2026-09-29.md#isolated-explicit-primary-candidate--2026-09-29)
owns its exact identities, tests and remaining qualification work.

The separate offline
[`prepare_sol_primary_candidate.ts`](../../../scripts/prepare_sol_primary_candidate.ts)
builder binds both request projections to reviewed private evidence without
invoking either provider. Its
[packet checkpoint](../../../../../docs/rfcs/identification-sol-primary-comparison-preparation-2026-09-29.md)
records five resolution states, pet/lookalike controls and limited references.
Source review, candidate/control request hashes and proposed scheduling do not
qualify a runtime binding or confidence policy. The separate
[`evaluate_sol_primary.ts`](../../../scripts/evaluate_sol_primary.ts) controller
now binds a fresh eighteen-call plan, private packet, exact clean source,
credential fingerprint and bounded approval. Its new records preserve primary
resolution and finite-catalog mapping without storing names or explanations.
Limited references can permit screen continuation but earn no quality pass;
review failures and unmapped/ambiguous identities still stop screening. See the
[runner checkpoint](../../../../../docs/rfcs/identification-sol-primary-comparison-preparation-2026-09-29.md#bounded-runner-implementation--2026-09-29).

The first separately approved eighteen-request comparison is
[complete](../../../../../docs/rfcs/identification-sol-primary-comparison-results-2026-09-29.md).
Useful rank behavior did not resolve a concrete visual-grounding failure, so the
candidate remains excluded from production. Retain the current Sol photo profile
for both tiers; this completed packet does not qualify confidence thresholds or
authorize another run.

## Observed-traits production prompt and frozen candidate

The separate `openaiPhotoConfidence.ts` prepares
`openai_identify_vision_confidence_v1` from this production request, replacing
only confidence instructions and its schema description while retaining the
observed-traits improvements. `createOpenAIConfidenceEvaluationAdapter` uses the
same one-shot transport, identification decoder and moderation. Its accounting
projection additionally rejects explicitly malformed or contradictory
cache-write counts, preserving the distinction from an omitted optional
breakdown; historical production adapters are unchanged. The evaluation-only
binding is rejected by production admission/result policy; the active production
selector continues to use observed-traits. The native reader recognizes the
prepared prompt with its own provisional 0.95/0.60 mapping. See the
[confidence assessment](../../../../../docs/rfcs/identification-openai-confidence-assessment-2026-09-30.md)
for fixed study rules, installed-reader evidence and later activation.
Historical builders and Gemini remain unchanged.

`openaiObservedTraits.ts` prepares `openai_photo_sol_observed_traits_low_v1`
from the frozen original Sol photo request. It changes only the fixed-count
visual-trait instruction, its schema description and private candidate identity.
Request one to three supported observations; material visibility limits remain
in the existing explanation. All other prompt directions, strict fields/bounds,
complete inputs, generation and moderation settings stay unchanged. The common
decoder already accepts shorter arrays; there is no new decoder, transport,
evaluator registration or production binding.

`openaiObservedTraits_test.ts` freezes candidate/control hashes, proves full
request parity outside that delta, rejects source/snapshot drift and unsupported
inputs, and exercises unchanged 1–10 array bounds. One to three is an
instruction, not a stricter validator. A zero-discernible-trait case still needs
a separate policy; do not fill the list with a visibility placeholder. The
[candidate record](../../../../../docs/rfcs/identification-openai-observed-traits-candidate-2026-09-29.md)
owns the hypothesis, evidence limits and targeted beta validation plan.
Production now reuses the two pure projections from `openaiPhoto.ts` with its
own admitted binding and unchanged schema name. The frozen candidate identity
remains evaluation-only; its text-format hash differs because its name differs.
Native display policy recognizes both original and revised production prompts.
After existing additive backend/migration prerequisites are deployed, distribute
that reader before deploying this prompt revision; older readers can still
decode the result but show Needs review for the unfamiliar prompt. Ordinary beta
smoke scans follow release. No dedicated comparison runner is planned, and these
offline tests do not establish model improvement or confidence calibration.

## Scoped audio prompt authority

The default-off 36-slot prompt lane adds the internal
`UserRequestAuthority.audioPromptComparison` discriminator. Only the validated
route assignment supplies A/B; the registry rejects mismatched task, tier,
attempt, video flags or audio/context shape. A retains `identify_audio_v2`; B
uses `identify_audio_uncertainty_experiment_v1` from the route-private candidate
instruction. The native builder changes only the resolved system instruction;
model, schema, DSP, confidence thresholds and generation settings remain fixed.
This discriminator is not copied from caller JSON and grants no quota or
provider authority. The
[prompt contract](../../../../../docs/backend-and-data/05-api-contracts.md#server-owned-audio-prompt-comparison)
owns its deployment/activation boundary. Normal and historical DSP claims omit
it and retain their existing projection.

## Preserved description profile

| Admitted model     | Output tokens | Thinking tokens | Shared options                     |
| ------------------ | ------------- | --------------- | ---------------------------------- |
| `gemini-2.5-flash` | 2048          | 1024            | temperature 0.15, seed 42, topK 40 |
| `gemini-2.5-pro`   | 4096          | 3000            | temperature 0.15, seed 42, topK 40 |

The sole text part comes from the existing `buildObservationPrompt`. The system
instruction and `merianDescribeModelContract` projection are unchanged. Prompt,
schema, confidence, binding, model, and policy references are fixed for this
attempt. A newly admitted retry takes a new snapshot; configuration changes do
not themselves authorize another call.

## Preserved primary identification profiles

All primary modes keep temperature `0.1`, seed `42`, and 8192 output tokens. The
admitted Pro tier sets a thinking budget of 5000; Flash leaves it unspecified.
Neither tier adds `topK` or an explicit safety-settings override. The exact
model still comes from the quota reservation; tier controls thinking and
confidence-threshold settings independently of that model string.

| Evidence                       | Instruction                          | Provider schema     |
| ------------------------------ | ------------------------------------ | ------------------- |
| Images or video snapshots      | Existing vision instruction          | Main Identify       |
| Prepared WAV audio only        | Existing bioacoustic instruction     | Audio-only Identify |
| Images/snapshots and WAV audio | Existing blended instruction         | Main Identify       |
| Description only               | Existing main-route text instruction | Main Identify       |

Audio-only assignments bind `identify_audio_v2`, `merian_audio_v2`, and
`gemini_audio_v2`; compatibility audio binds `identify_audio_compat_v2`,
`merian_audio_v2`, and `gemini_audio_compat_v2`. The shared
`AUDIO_CONFIDENCE_DESCRIPTION` in the executable contract defines taxon
confidence for named animals, presence confidence for unresolved wildlife, Human
identity confidence, and non-biological source-classification confidence.
Numeric thresholds, models and generation settings retain their existing values.
Evaluator policy, prompt and schema digests distinguish these semantics from
historical V1 results.

The main text profile is distinct from the legacy description profile above.
`identify-multimodal/provider.ts` preserves observation text, visual-context
text, ordered images, ordered processed WAVs, and capture-context text in that
sequence. Descriptor indices preserve still/frame/clip and standalone/companion
relationships; unknown legacy lineage remains unknown. Accepted partial frame
sets remain valid. No native video, playback key, or storage URL enters the
provider request. Required storage and finalization still use their existing
owner-side inputs.

The adapter captures native invocation duration and completion time before
decoding. The main route uses those facts for the existing `provider` and
`gemini` timing spans, keeping quota commit separately measured. Executor
duration also includes response normalization. No client, duplicate-poll, or
provider timeout is replaced with a shared end-to-end deadline.

## Preserved image and audio compatibility profiles

| Route and model            | Output tokens | Thinking tokens | Other generation settings                  |
| -------------------------- | ------------- | --------------- | ------------------------------------------ |
| `identify`, Flash          | 4096          | 2048            | temperature 0.1, seed 42, topK 40          |
| `identify`, Pro            | 8192          | 5000            | temperature 0.1, seed 42, topK 40          |
| `audio-spec`, either model | 2048          | 2048            | temperature 0.1, seed 42; topK unspecified |

Legacy image input keeps capture context first, ordered images second, and an
optional trimmed description last. Its model determines generation settings and
the vision prompt's diagnostic threshold; the admitted tier independently
determines the response schema's threshold and downstream candidate policy. Only
this profile explicitly sets dangerous-content and sexually-explicit safety
thresholds to `BLOCK_ONLY_HIGH`; other categories keep provider defaults. The
handler still applies its existing safety-probability moderation policy before
media promotion and saving.

Legacy audio keeps capture context followed by one already processed WAV, its
own bioacoustic prompt, the shared private audio schema, and its 0.95 candidate
threshold. It adds no explicit safety override. Its quota operation remains
`scan_audio_identification`; the other identification routes use
`scan_identification`. These differences are preserved even when model and tier
are tested independently. All compatibility profiles retain the first-part text
fallback when the SDK text getter is empty; primary identification does not add
that fallback.

Staged compatibility requests retain their existing replay-intent handoff to
`identify-multimodal`. Inline bytes stay out of durable intents and require a
client retry. The adapter owns neither promotion nor replay: unknown writes
retain media and quota, and proven owner-row insertion remains the prerequisite
for the existing compatibility success after a finalization failure.

## Preserved species-content profiles

| Task               | User quota operation        | Output tokens |
| ------------------ | --------------------------- | ------------- |
| `species_overview` | `scan_overview_enrichment`  | 1500          |
| `lookalikes`       | `scan_lookalike_enrichment` | 300           |
| `group_tags`       | `scan_group_tag_enrichment` | 100           |

All three keep temperature `0.1`, thinking budget `0`, and no explicit seed,
`topK`, or safety override. User calls use the exact admitted Flash or Pro
model; public jobs use Flash. Content preserves its legacy SDK text getter and
JSON extraction, including usable JSON on a non-STOP finish. It adds neither
identification's finish-reason rejection nor its compatibility text fallback.

`enrich-scan` checks the requested scope's cache before admission, prepares
after reservation and before commitment, and waits for the cache write before
releasing same-scope waiters. A rejection observer contains failures when no
waiter exists; waiters still receive the original rejection and must pass
admission for a new attempt. `groupTagQuota.ts` retains its derived child
request ID, original scan linkage, and optional follow-up failure behavior.

`refresh-species-model-content` authenticates the service caller and claims jobs
before preparation. Preview exits without inference. The worker retains its
batch limit, concurrency of two, attempt/backoff policy, candidate verification,
completion RPCs, and provenance. It creates no user quota reservation and
records usage with a null owner. The registry checks supplied claim facts; it
does not replace the authenticated claim RPC or authorize private observation
work.

## Shared content qualification

`sharedContent.ts` owns the independent acceptance boundary for shared species
content. Enrichment, optional group tags and claimed public jobs use its
prepared execution wrapper before committing quota or invoking. The biology
helpers also check the snapshot. Only existing Gemini
task/binding/model/prompt/schema and exact generation profiles qualify; changed
or unknown fields are rejected. Overview remains English. Updating the
assignment registry alone cannot qualify an alternate profile for these
canonical writers.

Existing public dictionary content retains its baseline interpretation without
invalidation or an invented historical execution identity. Warm-isolate keys
include the baseline namespace, task, canonical species identity, input name,
locale and lookalike taxonomy dimensions. These keys are not durable provenance.
Private candidate storage and task-specific promotion remain necessary if
another content provider is introduced; see the
[shared-content record](../../../../../docs/rfcs/identification-shared-content-qualification-2026-09-26.md).

## Usage and diagnostics

Returned token counts retain Gemini's existing interpretation, including null
for missing counts; modality breakdown retains its existing meaning. New primary
scan ledger entries use saved execution model/provider references; absent legacy
provenance alone falls back to tier-derived Gemini attribution. Historical rows
remain unchanged. Legacy-writer pricing eligibility is Gemini-contract-specific
and unknown prices remain null. Admin aggregates expose priced/unpriced
coverage; see the
[accounting record](../../../../../docs/rfcs/identification-provider-usage-attribution-2026-09-26.md).
The image compatibility route retains cached-token counts; legacy audio keeps
its existing null cached-token scan field. Bounded execution/version fields are
added to the existing optional `ScanCompleted` telemetry for image/description,
`AudioScanCompleted` for legacy audio, and the successful primary
`multimodal/latency` event. The compatibility `ai_provider_duration_ms` field
measures native invocation only, excluding decoding. They contain no evidence,
owner/attempt identifiers, provider diagnostics, or credentials. This telemetry
adds no cross-retry configuration pin or new billing record. Successful scan
configuration is separately persisted as described above. Compatibility routes
retain their existing failed/uncertain-attempt gaps. The primary multimodal
route uses `identificationUsage.ts`: quota commit and a unique invocation
witness are atomic, usage reporting is awaited independently of scan
persistence, and a private reconciler records missing reports as
unknown/unpriced. Native OpenAI photo pricing freezes the effective tariff
before dispatch. See the
[accounting contract](../../../../../docs/backend-and-data/04-database-schema.md#primary-identification-attempt-accounting).
This accounting is independent of optional telemetry and never invokes a model
again.

Content adds `ai_task`, provider/binding/prompt/schema references, nullable user
policy version, context kind, returned model, native duration, and outcome to
existing helper analytics and `ai_usage_events.metadata`. These fields contain
no user/job/attempt identifiers or species/evidence payload. Overview/lookalike
callers retain their usage write; group tags retain the helper's single write.
Cached/tool/modality token totals remain compatible. Internal helper execution
metadata is excluded from public enrichment responses. Existing event timing and
failure accounting gaps remain; this is not a new complete billing ledger.

## Verification

`ai_test.ts` runs the real Gemini SDK with intercepted HTTP and no network
permission. It checks both legacy description profiles and ten primary evidence
cases on each tier, plus sixteen image/audio compatibility cases across model
and tier, registry rejection, immutable snapshots, prepared-input stability,
safety projection, outcomes, optional usage, a single call, and the 90-second
timeout. `identify-describe/provider.test.ts` and
`identify-multimodal/provider.test.ts` run real handlers and real
quota/ledger/persistence helpers with deterministic adapters and database
doubles. They cover consent, replay, setup/commit failures, charged provider
failure, policy rejection, invalid output, successful owner persistence, usage,
and uncertain writes. Primary tests also verify real media preprocessing,
metered service replay, and completion after foreground cancellation followed by
replay without another invocation. A held-provider case retires the owner after
commitment and proves the existing profile recheck prevents insertion/completion
without refunding or repeating the already dispatched call.

`compatibility_test.ts` runs the actual image/audio handlers with real
preprocessing, moderation, quota, ledger, and persistence helpers, a
deterministic adapter, and intercepted storage/DB dependencies. It checks
unused-quota refunds, charged failures, refusals, safe promotion, unsafe-image
rejection, usage, stored replay, staged replay-payload reconstruction, inline
redaction, ambiguous persistence, post-insert finalization failure, and optional
native duration telemetry for all compatibility routes.

`../biology_test.ts` intercepts real SDK requests for both content models and
all three tasks, preserving schemas, prompts, generation options, output
normalization, usage, legacy finish handling, and failure behavior.
`content_test.ts` uses actual enrichment handlers, quota helpers, and the public
worker with deterministic provider/DB dependencies. It covers admission,
setup/commit failures, charged failures, cache coalescing, user/service metadata
and usage attribution, preview, claim bounds, and worker concurrency.

These checks do not establish real database concurrency, hosted behavior, live
model quality, or full-flow latency. Deferred Gemini consumers retain their
existing paths.

The
[Slice 6 verification record](../../../../../docs/rfcs/identification-foundation-verification.md)
adds full disposable-database evidence and distinguishes the hosted/device gates
remaining at that checkpoint. The
[deployment record](../../../../../docs/release-evidence/provider-flexibility-deployment-2026-09-21.md)
adds the Gemini-only rollout and owner-reported manual verification.
`_tests/aiQuotaCoverage.test.ts` locks the scoped/deferred Functions and tooling
dispatch/SDK inventory, including the live evaluator and network-denied
benchmark guards. The obsolete `createFlashModel` wrapper is removed.

For local timing, run `scripts/benchmark_ai_boundary.ts` from the Supabase tree
using the repository command and methodology in that record. It compares cached
native SDK requests with real shared preparation/invocation on synthetic inputs;
it measures neither provider latency nor end-to-end product timing.

## Future provider assignments

Follow [Adding a provider later](ADDING_PROVIDERS.md) for exact input/task
qualification, common-contract extensions, database/Edge admission, disclosure,
confidence, usage, cache, and activation work. The app owns a private
complete-input routing catalog: beta still photos select OpenAI and other
profiles select Gemini. There is no end-user provider selector or
percentage-routing control. Evaluation and the production photo binding retain
separate identities. Deploy the enabled adapter before the activation migration.
Ordered video frames have their own input profile and a planned separately
qualified OpenAI binding; audio is never dropped to fit a route.

## Metric interpretation

`metricCompatibility.ts` is the pure exact-profile owner for existing Gemini
metric meanings in private Insight Chat. It shares qualified policy version 1
and profile semantics with SQL `identification_metrics_are_gemini_compatible`
and native `InferenceConfidencePolicy`; database tests compare the TypeScript
and SQL results against actual registry snapshots. Unknown metadata cannot
inherit known score meanings. Field Chat removes unqualified numeric metrics
while keeping descriptive evidence. New immutable export snapshots freeze the
SQL predicate's boolean for the DwC-A worker. See the
[chat/export record](../../../../../docs/rfcs/identification-chat-export-metrics-2026-09-26.md)
for compatibility, rollout and verification.
