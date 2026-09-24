# AI provider boundary

All four identification routes (`identify-multimodal`, `identify-describe`,
`identify`, and `audio-spec`) and the biological overview, lookalike, and
group-tag helpers use this boundary. Their user enrichment and claimed
public-job callers retain separate admission paths. All live requests still use
Gemini; see the
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
- `registry.ts` resolves the fixed `gemini_baseline_v1` binding from the
  quota-selected model and, where applicable, the admitted tier. It checks task,
  representation, operation, Gemini permission dependency, and reservation
  metadata before commitment. No client field, environment variable, provider
  name, or URL can select another adapter.
- `contentRegistry.ts` binds the three content tasks to their existing quota
  operations and generation settings. User authority carries its admitted model,
  permission, and reservation. Service authority carries a claimed job, matching
  public-fact task, bounded attempt, and the fixed Flash model; its permission
  and user quota policy version are null.
- `production.ts` composes the registry and Gemini adapter. Tests inject their
  deterministic adapter through internal handler injection and the shared
  executor; its implementation is confined to a test file.
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

## Usage and diagnostics

Returned token counts retain Gemini's existing interpretation, including null
for missing counts; modality breakdown and scan-row accounting are unchanged.
The image compatibility route retains cached-token counts; legacy audio keeps
its existing null cached-token scan field. Bounded execution/version fields are
added to the existing optional `ScanCompleted` telemetry for image/description,
`AudioScanCompleted` for legacy audio, and the successful primary
`multimodal/latency` event. The compatibility `ai_provider_duration_ms` field
measures native invocation only, excluding decoding. They contain no evidence,
owner/attempt identifiers, provider diagnostics, or credentials. This adds no
durable configuration pin or new billing record. Failed/uncertain attempts and
disabled telemetry retain their existing accounting gaps.

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
confidence, usage, cache, and activation work. There is currently no runtime
provider selector, percentage-routing control, or alternate live adapter.
