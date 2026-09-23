# Server-owned audio comparison assignments

Date: 23 September 2026\
Status: Implemented locally; disabled; app receipt collection remains next

This slice binds a successful identification to its source clip, processing arm
and exact Gemini request through the existing authenticated
`identify-multimodal` route. It implements the server half of the
[provenance preparation follow-up](./identification-audio-comparison-provenance-2026-09-23.md).
It makes no provider call, deployment, account change or model-quality claim.
Gemini remains the sole provider. Formal corpus counts remain 0/60 development
and 0/240 held-out groups.

## Fixed experiment, ordinary admission

The generated `comparison/plan.ts` contains exactly twelve assignments from the
immutable preparation with canonical digest
`42350d978486e1a9edb409065be163b45f2d01d1182042b3e48f318e7ed43681`. Each of six
clips has one historical and one current processing assignment, with the first
arm alternating by case. Plan digest
`fc30d6c938d000b2ecb994509e63b0f8e129bc5dfcb2a914a3517c8cbd4fc213` binds the
table. Re-running its generator verifies the immutable source digest; it cannot
silently substitute another preparation.

The optional request handle is `audio_comparison: {planSha256, slot}`. The
caller cannot supply a provider, model, processor name, prompt or alternative
hash. The server looks up the assignment. The source and processed WAV hashes
must match before quota reservation. The production Gemini request, execution
snapshot and confidence thresholds must match the frozen hashes before quota
commitment and invocation. Prompt, schema, context, model or processing drift
therefore stops the attempt.

Only the exact fixed-context body is eligible: one inline standalone canonical
mono PCM16 44.1 kHz WAV of at most 15 seconds, its audio descriptor and owner
timeline, the normal authenticated owner/scan identity and geoprivacy
preference, and synthetic `en`/`UTC`/January/noon context. Extra fields, text,
location, staged media, images and video are rejected. Ordinary image snapshots
and video companions retain their existing processing path.

`comparison/audio.ts` now owns both bounded transforms. The historical DSP moved
from evaluation scripts into that route-private directory; offline preparation
imports the same owner. No deployed function imports an evaluation script.
Normal requests continue through `processMultimodalWAV`. The old preparation's
implementation fingerprint remains historical; it is not evidence for this new
runtime graph. Its frozen expected bytes/settings remain the comparison target.

## Configuration and attempt limits

The environment configuration `IDENTIFICATION_AUDIO_COMPARISON_V1` is absent by
default. The strict, at-most-1-KiB object contains only `version: 1`, the
approved `ownerId`, `planSha256`, `backendBundleSha256`, `startsAt` and
`expiresAt`. Owner identity remains private operational configuration; it must
never enter source, benchmark artifacts or logs. The bundle hash must equal the
generated runtime identity. UTC instants use the exact
`YYYY-MM-DDTHH:mm:ss.sssZ` form.

The active window lasts at most 24 hours and must lie between
`2026-09-23T00:00:00.000Z` and `2026-10-22T00:00:00.000Z`. The fixed lifetime is
shorter than the quota ledger's 30-day retention and does not extend source
retention. Re-enabling this plan cannot create new scan IDs or reset slots. The
approved owner must remain the same throughout the run. A new plan or changed
owner requires a separately reviewed experiment, not a selective retry.

`audioComparisonScanId(slot)` derives the stable native scan UUID from the plan
and slot, reserving UUIDv8 prefix `ac0a0001-`. Ordinary UUIDv4 scans remain
eligible even if their first eight hexadecimal digits coincide. It is also the
normal quota request ID. The route checks the handle and reserved prefix before
recovery, completed-result lookup, media resolution or quota. Removing the
handle, disabling configuration or entering service/background replay cannot
turn this scan ID into an ordinary retry. Raw scan IDs are not included in the
proof header or benchmark artifacts.

Existing consent, account, entitlement, quota and durable-ingestion owners still
apply. Only an admitted Gemini Pro reservation with effective Pro tier and no
Flash fallback is eligible; paid, trial and existing complimentary Pro all use
their existing account rules. This feature grants no new allowance. Immediately
after reservation, `attemptCount !== 1` refunds the uncommitted lease and stops
before ingestion or provider preparation. Reopened failed, refunded or expired
slots cannot call the provider again. The same guard and expiry check run again
before commitment. A failure or unknown result burns/excludes its slot. No
selective retry is authorized by a refund.

Duplicate successful requests may return the existing durable result, with only
the normal replay header. Concurrent duplicates retain the
quota/owner-completion wait. Expired or disabled comparison requests stop even
if a completion exists; ordinary owner Library access remains available. These
controls bound primary comparison invocations for the approved owner, not all
account activity or total enrichment/billing cost. A caller submitting the audio
with neither the handle nor reserved ID makes an ordinary request, without
comparison proof. Other legacy endpoints do not gain comparison support.

## Fresh success proof and remaining app work

Only the final fresh durable-success response includes
`X-Merian-Audio-Comparison`. Version 1 contains the plan hash, slot, case, arm,
source WAV hash, processed WAV hash, provider-request hash, policy hash and
confidence hash. The exact field names are in the
[API contract](../backend-and-data/05-api-contracts.md#server-owned-audio-comparison).
The bounded allowlist includes no provider text, raw media, owner or scan ID.
Errors and stored/reconstructed replays never receive this header. Existing
Identify JSON responses, generated Swift DTOs and v1 diagnostic headers are
unchanged.

The header attests server processing and durable completion on that response. It
does not prove active foreground ownership, app persistence/display, a complete
observation window, all billed work or independent reference correctness. It is
an authenticated response claim, not a standalone signed artifact.

The Debug app does not yet send the handle/derived scan identity or collect this
header. Its existing v2 measurement remains profile-only. **Keep the
configuration unset** until the next slice binds the staged clip and durable
queue identity, records the receipt within the native log budget, joins it to
one complete observation window, and excludes interrupted/replayed/failed
outcomes. Activation, deployment and the twelve-request paid run remain separate
explicit operations under the existing release controls. No manual request
workaround or old backend rollback is needed.

## Validation

The
[offline binding verification](./identification-evaluation-evidence/2026-09-23-audio-comparison-assignment/verification.json)
reprocessed all six frozen source WAVs through both runtime arms. All twelve
source/processed/request/policy/confidence bindings matched the immutable table.
The source packet was read-only; network and environment access were denied. The
regenerated runtime bundle is
`a5939b36fd43dcf1fbfb7f5ee01875d3888a313e66af8756e79fb04f19694b2c`.

Local runtime tests passed **133 tests and 168 substeps**, covering the main
route, comparison guards, shared provider boundary, quota, ingestion
intents/jobs and replay worker. This includes both valid arms through synthetic
storage, provider and durable completion; mismatch/retry/failure cases; and
normal requests. The complete tooling gate passed **375 standard tests**, nine
isolated evaluator tests, 39 DTO tests and all seven shell test files. The two
generated artifact checks are discovered by that gate, which candidate
validation already runs. Candidate validation now explicitly includes the
route's behavior suite and comparison assignment suite as well.

Identify DTO regeneration produced no Swift diff. Whole-tree Deno formatting and
lint passed. All 101 per-function configurations, dependency graphs and
recursive entrypoint type checks passed. No database schema or native code
changed; no disposable-database, Xcode, simulator, physical-device or hosted run
is claimed for this slice. Provider/database behavior tests use synthetic
adapters and database doubles; they do not prove hosted concurrency.

Independent read-only review confirmed the early reserved-ID/replay fence,
pre-ingestion refund guard, source/request checks and final receipt placement.
The final generated identity and explicit Pro-plus-fallback predicate test are
verified. No remaining finding was identified within this backend scope. Native
receipt/outcome admission remains open.
