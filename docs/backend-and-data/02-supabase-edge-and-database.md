# Supabase Edge and PostgreSQL Engine

Naturebook uses Supabase as its backend platform. The Supabase URL and
publishable client key are build configuration and are necessarily compiled into
the app; RLS and explicit object grants—not key secrecy—protect direct
owner-scoped Data API access. Service-role credentials, provider keys, webhook
secrets, and other privileged secrets remain server-only in Supabase Edge.
Gemini provider calls and privileged database admission execute server-side in
Deno Edge Functions.

The normative joined success, retry, media, recovery, and deployment boundary
for all scan producers is
[Scan Ingestion Reliability and Recovery](./16-scan-ingestion-reliability-and-recovery.md).

## Core Schema Structure

`00001_initial_schema.sql` defines the base backend schema.
`00002_user_auth_trigger.sql` handles the auth relationship. All anonymous users
are identified by a persistent Keychain-backed
`UIDevice.current.identifierForVendor` IDFV.

- **`species_dictionary`**: Stores every tracked taxon with its scientific and
  biological descriptors.
- **`species_observation_stats_cache`**: Stores public global provider
  aggregates for species observation charts, keyed by species/source/scope.
- **`scans`**: Records GPS bounds, the LLM-generated `ai_confidence_score`,
  `inference_tier`, UUID references, and the `ecology_type_enum` for each scan,
  tied to the user's streak.
- **`insight_chat_conversations` / `insight_chat_messages`**: Private Pro
  follow-up chat conversations keyed to owned `scans.id`, with owner-only RLS,
  scan cascade cleanup, and assistant token telemetry for cost audits.
- **`users`**: Binds the IDFV (or authenticated UUID) to the product schema,
  tracking usage limits, subscription tier, public Explore display identity,
  avatar projection, and canonical `public_username` handle. Current handles
  reject protected product namespaces, official/system roles, and exact
  product-role combinations through a database-authoritative CHECK.
- **`explore_comment_mentions`**: Stores the durable mentioned-user edge and the
  historical normalized username token that still appears in immutable comment
  text. The snapshot keeps structural username validation but does not inherit
  later reserved-name expansions.
- **`user_terms_acceptance_receipts`**: Immutable, account-owned evidence for
  each accepted Terms version, including exact action copy, device action time,
  app version/build, and an authoritative server-recorded time.
- **`user_ai_consent_events`**: Immutable account-owned `granted` / `revoked`
  history for a named AI provider and disclosure version. Direct client inserts
  are denied; an authenticated causal RPC accepts a grant only from the
  currently observed stream head, while a revocation is accepted and rebased to
  the locked current head. Authorization first resolves the all-version greatest
  server revision; any head revocation denies before the head grant's disclosure
  version and rollout bundle are evaluated.
- **`user_adult_eligibility_receipts`**: Immutable evidence of the current 18+
  self-attestation, including exact displayed text, method, device action time,
  platform, app version/build, and authoritative server time. No birth date or
  exact age is collected.
- **`user_analytics_consent_events`**: Immutable account-wide PostHog grants and
  revocations under the same causal revision protocol. Absence of a current
  grant means analytics is off; owner-only Realtime INSERT events and foreground
  reconciliation propagate accepted changes. A delayed stale grant is rejected
  without insertion; a delayed revocation is rebased and accepted so withdrawal
  remains deny-wins. Both iOS and Edge analytics require the all-version head
  itself to be a current-version grant.

The additive schema and static migration contracts establish the intended
database boundary, but do not prove the iOS local-ledger, SDK-shutdown,
account-transition, or synchronization lifecycle. Those client findings keep the
candidate blocked in the
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

- **`internal.user_species_scan_counts`
  (`20260724222838_optimize_species_count_trigger.sql`)**: A private
  `(user_id, species_id)` ledger with the number of matching scans. Four
  statement-level transition-table triggers aggregate insert, delete, update,
  and truncate changes. The total changes only when a ledger row crosses zero;
  owner transfers include both `OLD.user_id` and `NEW.user_id`, while unrelated
  scan updates net to no work. The migration replaces the historical
  `unified_species_count_sync` full-history row trigger. Its one-time backfill
  and trigger swap run inside one explicit transaction: `BEGIN` precedes the
  `SHARE ROW EXCLUSIVE` scan lock, and `COMMIT` follows the final trigger. That
  boundary is part of this immutable historical file, not guidance for new
  migrations; new files leave transaction and history ownership to the CLI.

## Shared Edge Utilities (`_shared/`)

Several utilities are shared across all Edge Functions via
`services/supabase/functions/_shared/`:

- **`http.ts`**: The unified networking primitive module. Defines `corsHeaders`,
  `jsonResponse(payload, status)`, strict POST payload
  `requireParams(body, fields)`, and cryptographic `timingSafeCompare(a, b)` for
  secret validation. Its canonical `parseJsonBody(...)` reader accepts only JSON
  media types, enforces declared and streamed byte counts, rejects invalid
  UTF-8, coalesces transport chunks without retaining a per-chunk object graph,
  and requires a JSON object by default. Routes select a 16 KiB `small`, 64 KiB
  `standard`, 1 MiB `bulk`, or reviewed media-specific limit; production
  handlers must not call `req.json()` or `req.text()` directly.
- **`outbound.ts`**: The outbound networking boundary. It combines caller
  cancellation with a hard provider deadline and exposes bounded strict-UTF-8
  text/JSON response readers. Production modules cannot call global or injected
  fetch transports directly; CI inventories the remaining signed R2 client calls
  and requires their deadline-bound `Request` adapters.
- **`edgeHandler.ts`**: Wraps endpoints natively using `withEdgeHandler()`,
  automatically intercepting CORS `OPTIONS` preflights and Deno SDK JWT
  extraction layers, eliminating boilerplate. Exposes `runBackground(task)` via
  standard `EdgeRuntime.waitUntil`; custom-auth, webhook, and intentionally
  public handlers register through `serveEdge(...)`. Both paths create a
  server-owned UUID for every request and return it in `X-Request-ID`.
  Unexpected exceptions become `500 internal_error`; ordinary returned `5xx`
  bodies keep their status but receive a generic status-derived response.
  Expected thrown failures use `PublicHttpError`, explicit safe response
  failures use `publicErrorResponse(...)`, and retained `4xx` application
  responses must contain only audited validation or caller-state fields. Raw
  exception and provider details are logged server-side with the request ID.
  `logStructuredError(event, details)` writes details first and then the
  canonical `event` and `ts`, so caller-controlled detail keys cannot overwrite
  the log identity.
- **`biology.ts`**: The centralized Gemini-2.5-Flash LLM taxonomy engine. It
  aggregates the schema logic for calculating `fetchStaticEncyclopedicData`,
  `fetchSimilarSpecies`, and `fetchGroupTags`. Explicitly enforces standard API
  mappings and funnels usage out to PostHog. All system instructions are
  structured as hierarchical Markdown (`# Role / # Task / # Rules`) inside
  TypeScript template literals, matching the format used by the `identify` Edge
  Function. This improves instruction-following and TTFM alignment within
  Gemini's attention mechanisms. `fetchSimilarSpecies` system instruction
  enforces **same taxonomic order** as Rule 1 — lookalikes must share the
  primary species' order. "Field visual similarity" framing is explicit, padding
  the array with unrelated species is forbidden, and new model output includes
  species-level relation explanations (`reason`, `visual_traits`, `confidence`)
  with no user-specific scan context.
- **`external.ts`**: Aggregates verified DaaS fetch calls to GBIF (Global
  Biodiversity Information Facility) and the Wikipedia rest_v1 API for canonical
  reference imagery, GBIF match taxonomy, Wikipedia extracts, and vernacular
  name synonyms. GBIF vernacular names
  (`GET /v1/species/{key}/vernacularNames?language=eng&limit=30`) are fetched in
  parallel with occurrence imagery behind the shared 2.5-second outbound
  deadline. Provider JSON is streamed through a 256 KiB ceiling before parsing.
  The result is normalised to Title Case, deduplicated, and filtered to
  English-only entries before being returned as
  `alternativeCommonNames: string[]`. This array is written to
  `species_dictionary.alternative_common_names` during the Cache Miss enrichment
  pass and served back to the iOS client as `alternative_common_names` on Cache
  Hit. Reference-image results are passed through `externalImagePolicy.ts`
  before return. That helper owns narrow, exact provider-media suppressions; its
  current rule rejects all variants beneath
  `inaturalist-open-data.s3.amazonaws.com/photos/605615444/` without blocking
  the provider or species.
- **`gemini.ts`**: Lazily constructs the paid-project `_genAI` client from only
  `GEMINI_PAID_API_KEY` and owns syntax-only JSON object extraction. Missing
  paid credentials fail before a provider request; there is no unpaid-key
  fallback.
- **`posthog.ts`**: A headless telemetry ingestion pipeline executing
  asynchronous `node-fetch` style queries to log per-scan events to PostHog for
  behavioral analytics (conversion funnel, scan frequency, species discovery
  rate). Before any PostHog request, it checks the latest current account-wide
  consent event and fails closed on absence, revocation, or lookup failure. It
  sends only the pseudonymous account UUID, never auth email or name. Capture is
  best-effort behind a 2.5-second hard deadline so telemetry cannot consume an
  unbounded share of Edge wall-clock time. PostHog receives token counters for
  funnel/debug slicing, including video-attributed counters on video-backed
  multimodal scans, but authoritative LLM token cost analytics are owned by
  Supabase SQL queries in `services/supabase/analytics/` (see below). Scan
  inference cost queries read `scans`; Insight chat cost queries read assistant
  rows in `insight_chat_messages`.
- **`aiQuota.ts`**: The paid-provider boundary. It validates UUID idempotency
  keys, derives a daily-rotating HMAC of the proxy-observed address, and calls
  the service-only `reserve_ai_quota` RPC. The RPC first requires current adult,
  Terms, and all-version Gemini-head consent for the active account. Only then
  does its atomic transaction resolve the durable plan, select the allowlisted
  model, and consume daily/user/IP counters before Edge provider dispatch. A
  provider attempt is committed; provider failure remains charged but becomes
  retryable, abandoned pre-provider leases expire, and only a verified
  pre-provider no-op is refunded. `_shared/groupTagQuota.ts` applies this
  boundary to optional group-tag generation.
- **`entitlement.ts`**: Non-provider feature and telemetry tier resolver. It
  calls service-only `get_user_entitlement_service(...)` on every resolution and
  validates paid, complimentary, or free plan, balances, in-flight holds, and
  monotonic version from the private database state. It also reads the rollout
  fence for public protocol enforcement. Query errors, missing rows, or
  malformed durable values return `503 ai_entitlement_unavailable`; there is no
  isolate-local authorization cache or webhook cache invalidation.
- **`aws.ts`**: Exports native `S3/R2` Cloudflare mappings utilizing
  `aws4fetch`. Exposes array batch tools (`deleteR2Objects`, `copyR2Object`)
  used for purging storage footprints. `deleteR2Objects` is bounded through
  `_shared/concurrency.ts` at 16 in-flight deletes so purge jobs cannot open an
  unbounded Cloudflare socket storm from one V8 isolate.
  `generatePresignedPutUrl` accepts an explicit Content-Type so image and audio
  staging uploads can be signed with the same header the iOS background upload
  task will send. R2 prefix ownership is explicit here: `staging/`,
  `quarantine/`, and `exports/` are temporary; `public_uploads/free/` and
  `public_uploads/pro/` are scan media; `avatars/` is durable public profile
  media. Scan cleanup code must call `deleteScanMediaR2Objects(...)` so it
  filters to scan-media URLs only. Every executed R2 object request carries a
  hard deadline, including batch delete, copy, upload, list, and staged
  inference-media reads. Avatar replacement must call
  `deleteAvatarR2Object(...)`, which accepts only `avatars/{sameUserId}/...`
  URLs.
- **`mediaBudgets.ts`**: Centralizes Edge media limits and reusable validation
  helpers for endpoint JSON body byte ceilings, image count/raw bytes, inline
  audio base64 length, raw audio bytes, audio clip count, staged R2 key
  ownership, path traversal, and `Content-Length` prechecks. The exported capped
  readers (`readRequestJsonWithinBudget`, `readResponseArrayBufferWithinBudget`,
  and `readStreamArrayBufferWithinBudget`) are mandatory for media-bearing
  request and response bodies because missing/chunked lengths are common.
  `identify`, `identify-multimodal`, `audio-spec`, and `generate-upload-urls`
  must import these helpers rather than redefining byte limits locally.
- **`concurrency.ts`**: Provides `mapWithConcurrencyLimit`, an ordered bounded
  fanout primitive for Edge paths that would otherwise launch unbounded
  `Promise.all(...)` work. The APNs delivery function uses it with width `8`.
- **`identify/media.ts`**: Shared inference-media resolver for `identify`,
  `identify-multimodal`, and `audio-spec`. It validates image R2 keys, resolves
  image payloads serially, validates inline image budgets, resolves
  inline/staged audio buffers, and returns standardized JSON error responses for
  media budget, IDOR, and path traversal failures.
- **`speciesContentProvenance.ts`**: Shared species dictionary provenance
  helpers. It builds field-level `species_content_provenance` rows for common
  names, alternate names, taxonomy, Wikipedia text/URLs, habitat, GBIF keys,
  reference images, group tags, hazard/conservation fields, and lookalikes.
  Writers use the helper as a best-effort side effect: provenance failures are
  logged but never block scan ingestion or public dictionary reads.
- **`auth.ts` / `claimsAuth.ts`**: `auth.ts` owns shared bearer extraction,
  explicit claims validation, and `auth.getUser()` compatibility.
  `claimsAuth.ts` is injected only by latency-sensitive `/identify-multimodal`
  and `/update-scan-context`; it uses `auth.getClaims(token)` with the project's
  cached ES256 JWKS, then validates issuer, audience, expiration/not-before,
  role, and `sub`. The claims path accepts anonymous/authenticated user roles
  but rejects service-role replay, while unrelated functions avoid its
  additional SDK graph.

## Authoritative AI Entitlement and Quota

Migration `20260723160229_enforce_server_ai_quotas.sql` established provider
authorization; forward migration
`20260802235833_three_complimentary_pro_scans.sql` extends the reservation with
the original analysis UUID, protocol fence, server-derived Flash fallback, and
private complimentary linkage. `reserve_ai_quota(...)` is a service-role-only,
`SECURITY DEFINER` RPC with an empty search path and an in-function
`require_service_role()` check. Migration
`20260804020351_record_legal_consent_receipts.sql` also places
`internal.require_current_ai_consent(user_id)` in both reservation overloads;
`20260804033307_add_adult_and_analytics_consent.sql` advances its current bundle
to adult policy `2026-08-03` and Terms `2026-08-03`; forward migration
`20260804215234_bump_consent_disclosure_versions.sql` advances Gemini to
`2026-08-04.1`. Additive TestFlight mode accepts only the complete newest or an
explicitly allowlisted complete prior beta bundle until owner-only strict
cutover. After old builds are expired,
`services/supabase/scripts/cutover_strict_ai_consent.sql` makes current evidence
mandatory. Missing, partial, stale, or revoked evidence raises
`ai_consent_required`; `_shared/aiQuota.ts` maps it to a caller-safe HTTP 403.
That code is a disclosure-policy transition, not quota exhaustion: it is raised
before entitlement selection, creates no provider reservation or included-Pro
hold, and consumes no daily Flash allowance. A first-time client's local
onboarding flag or persisted sync marker is never server authorization; the same
account rows must be uploaded and fetched authoritatively before its first
provider request. See the
[first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md).
In one transaction the reservation then:

1. Locks the authenticated user's row first, reads durable paid state and the
   rollout mode, and derives paid Pro → complimentary Pro → free. Legacy mode
   alone can derive `pro_trial`; post-cutover current resolution cannot.
2. Selects the enabled policy and allowlisted model for the exact operation and
   effective plan.
3. Serializes only identical `(user, operation, request_id)` keys.
4. Conditionally upserts shared UTC-day, per-user, and per-IP counters without a
   read-then-write race.
5. Returns an idempotent reservation, a ten-minute expiry, a per-attempt UUID
   fencing token, and remaining daily capacity.

The Edge helper commits immediately before provider dispatch. Reservations
already consume their counters, so a process crash or settlement failure cannot
create unmetered work. Refund is restricted to a verified no-provider path and
decrements each linked counter exactly once. A daily-rotating HMAC address
bucket supports network throttling without persisting a raw IP address.
Reservation and refund paths acquire daily, user-rate, and IP-rate counter locks
in the same order to avoid deadlocks under concurrent traffic.
`refund_expired_ai_quota_reservations()` reclaims abandoned pre-provider leases
every five minutes. A fresh fencing token on retry prevents delayed settlement
from an older attempt from changing the new attempt. Provider errors transition
`committed` to `failed`; their counters remain consumed, while the same request
key may start a newly metered retry.

Terminal reservations ordinarily prune after 30 days. Migration
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql` retains only
exact failed/committed normal and replay scan reservations as chronological
authority while the matching owner/scan remains unresolved
`media_reconciliation_abandoned`. The exception does not retain refunded or
unrelated state and ends after recovery or explicit operator resolution.

Current post-cutover policy ceilings are 1/50/500 primary scan attempts per UTC
day for free/complimentary/paid, 4/100/500 cache-miss
overview/lookalike/group-tag enrichment attempts, 3/25/100 Explore/Community
audio moderation attempts, and denied/60/120 model-chat attempts. Historical
`pro_trial` policy and reservation rows remain readable. All allowed plans also
share per-minute user and IP ceilings. These are database-owned cost/abuse
controls; iOS `UsageManager` is only an advisory capture meter.

Provider quota and complimentary settlement are independent. Attempted provider
calls retain their cost/rate counters even when a proven terminal failure
releases the user's held credit. Retryable or ambiguous outcomes keep the hold
until recovery proves a durable result or terminal failure. The normative
lifecycle and user-first lock order are in
[`18-complimentary-pro-scans.md`](./18-complimentary-pro-scans.md).

Database entitlement lookup fails closed. A query error, missing user row,
missing/disabled policy, or unsupported model prevents provider work.
`users.entitlement_version` advances in a trigger on tier or expiry changes, so
RevenueCat never needs to invalidate memory in other Edge isolates.

## The R2 Upload URL Node (`generate-upload-urls`)

The `/generate-upload-urls` Edge Function signs direct-to-Cloudflare R2 `PUT`
URLs for background staging. Current clients send a structured `files` manifest
built by `MediaStagingContract` for the app queue. Each entry includes
`fileName`, `mediaKind`, `contentType`, `sizeBytes`, and, for scan media,
`clientScanId` plus `mediaRole`. Explicit post-analysis sharing recovery also
sets `uploadPurpose` to `scan_share_restore`. When those scan fields are
present, the signer creates staged `scan_media_assets` rows and returns
`mediaAssetId` / `mediaSessionId` next to each signed URL. These staged rows are
allowed to keep `scan_id` null until `identify-multimodal` inserts the final
scan and promotes the media. The restore purpose is accepted only for an exact
scan/category-bound deterministic filename and canonical role. A completed job
requires a fresh unrestricted scan read: an existing row must be non-tombstoned
and owned by the authenticated caller, while a genuinely absent row may only
stage media for guarded reconstruction. A missing or nonterminal job may also
stage before that reconstruction, but signing itself grants no scan-write or
publication authority. Failed-terminal and ordinary completed-ingestion uploads
stay closed, and repair/ordinary files cannot mix for one scan. The Edge parser
rejects unsanitized names, media-kind/content-type mismatches, invalid role/kind
combinations, over-budget audio, video, or image files, batches above six files,
batches above five images, batches above one video, and batches above two audio
files before calling `generatePresignedPutUrl()`. The six-file cap is
specifically for video scans that need five sampled inference frames plus one
playback clip. Ordinary inference audio is restricted to `.wav`/`audio/wav`;
`.m4a`/`audio/mp4` is allowed only for exact `scan_share_restore`, and audio
filename/MIME mismatches fail before signing. Legacy `fileNames` requests,
structured entries without a declared size, top-level arrays/non-objects, and
other old shapes fail with stable `400 size_bytes_required`; every supported
request carries an exact positive `sizeBytes`. Each response item declares the
exact `Content-Type` and `Content-Length` headers the client must send. Both are
signed with `host` through `allHeaders: true`
(`content-length;content-type;host`), so a different MIME type or body length
fails signature verification at R2. Every iOS data, file, avatar, repair,
restore, foreground, and background PUT applies that response map. File-backed
work re-stats immediately before task creation and re-signs when its size
changed. Deployed verification HEADs the exact uploaded object and checks its
stored length; declaration alone is not evidence. The limit and signing contract
is pinned in `docs/contracts/media-staging-upload-manifest.json` and loaded by
both Swift and Deno tests. Registration is idempotent per
owner/client-scan/object key, but signing calls for one scan may be composable
subsets (for example live video and later queue recovery media). Existing
unrequested rows are retained rather than treated as an immutable full manifest.
Edge code bounds the combined active staged/processing key union at six;
historical promoted capture rows do not consume a later explicit share-repair
budget. An owner-serialized database trigger enforces the staged-row cap across
concurrent disjoint-key registrations.

Profile avatar uploads also use this signing path. The iOS client uploads a
single prepared square WebP or JPEG to `staging/{userId}/...`, then calls
`/update-public-avatar` to promote that object into the durable `avatars/`
prefix. The signing endpoint stays generic; ownership and avatar MIME policy are
enforced by the promotion endpoint.

## The Scan Media Reconciliation Worker (`reconcile-scan-media-assets`)

The `reconcile-scan-media-assets` Edge Function is an internal service-role
worker scheduled hourly by pg_cron. It scans old `capture_upload` rows in
`scan_media_assets` and closes drift between R2 staging objects, the normalized
asset lifecycle table, and `scans.captured_media` / `video_storage_urls`.

If the scan row already exists, the worker only performs safe finalization:
matching image rows are marked `promoted`, consumed audio staging objects are
deleted and marked `deleted`, and stranded playback video objects are promoted
from `staging/` into `public_uploads/` before the scan's video URL array and
captured-media manifest are repaired. Repair compatibility-reads legacy aliases,
device-local references, and historical nested video audio, then rewrites only
strict Captured Media Wire V1. Because V1 drops nested audio, a positive rebuilt
`has_audio` must come from independently verified normalized or durable playback
metadata; video kind alone is never evidence. If no scan row exists after the
abandonment TTL, remaining staging objects are deleted and the asset row is
marked `failed` for audit. The worker does not replay AI inference; the iOS
offline queue remains responsible for inline/redacted scans, while
`replay-scan-ingestion` retries resumable staged scans that never reached
completion.

The worker now reads `scan_ingestion_jobs` before deciding whether stale media
is truly abandoned. Active `processing` / `finalizing` leases and future
`retry_after` windows keep media pending. Repaired existing scans can complete
only through `complete_scan_ingestion_finalization`, which verifies every
claimed key disposition and every required canonical media row before writing
the ledger's `complete` state last. Media abandoned after the TTL marks the job
`failed_terminal` with a structured reason code so status polling, compatibility
recovery, and health checks share one server-authoritative decision.

## The Scan Ingestion Replay Worker (`replay-scan-ingestion`)

The `replay-scan-ingestion` Edge Function is an internal service-role worker
scheduled every five minutes by pg_cron. It claims retryable or lease-expired
`scan_ingestion_jobs` rows whose paired `scan_ingestion_intents` are resumable,
reconstructs the sanitized staged media/audio/video or text-only request, and
invokes `identify-multimodal` with the same `client_scan_id`.

New intents use schema version 3: observation contexts contain only bounded
`freeText`, and the validated owner timeline carries ordering. Schema-v2 intents
remain replay-readable; multimodal accepts and discards any legacy description
`addedAt` / `added_at` value before new intent, scan, or Captured Media
persistence. Absence of an older intent's `ownerMediaTimeline` stays absent and
is never converted into an empty authoritative timeline.

`claim_replayable_scan_ingestion_jobs` caps automatic replay at 10 claims per
sanitized intent. Rows at or above that budget are handled in the same bounded
claim window and marked `failed_terminal` with
`stage = 'server_replay_limit_reached'`, so the scheduled worker cannot churn
forever on a permanently broken replay payload.

This worker is deliberately a dispatcher, not a second inference pipeline.
`identify-multimodal` remains the only owner of scan-identification Gemini
calls, scan-ingestion moderation, playback-video promotion, scan insertion,
`captured_media`, and asset finalization. Explore publication moderation is a
separate fail-closed classifier owned by `share-scan-to-explore`. Existing
complete scan rows are revalidated through the same finalization routine without
replay; existing incomplete video rows are left retryable for media
reconciliation or local-video repair.

The downstream multimodal invocation has a 120-second hard deadline and reads a
failed response through an 8 KiB ceiling. Database claims are clamped to at
least 150 seconds, so the request deadline always leaves a 30-second settlement
margin before another worker can replace the lease.

Legacy scan-producing endpoints (`identify`, `identify-describe`, and
`audio-spec`) call the same atomic `begin_scan_ingestion` boundary before
provider dispatch. It writes compatibility `scan_ingestion_jobs` and
`scan_ingestion_intents` in one transaction, returns server-canonical upload
sessions/checksums, and reports an already-complete recovery winner before paid
work begins. Setup failure fails closed and refunds unused quota; there is no
independent-write fallback. Their sanitized intents are shaped as multimodal
replay payloads, so staged image/audio and text-only requests can recover
through the same worker. Requests that used inline base64 media are recorded
with redacted counts and `resumable = false`; the iOS offline queue remains the
recovery owner because the server never stores raw private media bytes.

## Scan Media Health (`scan-media-health`)

The `scan-media-health` Edge Function is an internal service-role read path for
media durability observability. It reports stuck scan-ingestion jobs, stale
capture-upload asset rows, failed media assets, recent video scans whose
`video_storage_urls`, `captured_media`, and ready playback `scan_media_assets`
disagree, Explore video rows missing poster thumbnails, and the latest scan
media reconciliation run status.

The endpoint is intentionally read-only. It does not promote R2 objects, mutate
scan rows, replay inference, or delete staged media. Repairs stay owned by
`identify-multimodal`, `replay-scan-ingestion`, `reconcile-scan-media-assets`,
and the iOS offline queue. Deploy smoke tests call it with a small sample to
prove the service-role status surface is reachable after migrations and function
deployment. The scheduled **Scan Media Health Monitor** GitHub workflow calls
the same endpoint every 30 minutes, stores JSON/Markdown artifacts, and fails
only on `critical` by default so warnings remain visible without paging the
deploy path. Its Markdown artifact includes an **Incident Actions** table that
maps each issue code to an owner, next step, runbook, and sample-field hint, so
production drift triage starts from the generated report instead of raw table
inspection.

## Owned Missing-Image Repair (`repair-scan-image`)

Supabase Postgres owns scan/post metadata and public media references;
Cloudflare R2 owns the referenced object bytes. `repair-scan-image` restores the
connection when an active owned scan still references a durable image that R2
reports missing and the client has a strongly matched surviving local file.

The app first performs an authenticated inspection request containing only the
canonical `source_url`. The function derives the owner from the verified JWT,
requires an active owned scan reference, and performs an R2 `HEAD`. It returns
`healthy`, `missing`, or `not_referenced` without mutating state.

For a confirmed missing object, the app obtains an ordinary owner-bound signed
upload URL, uploads the local file to `staging/{sameUser}/repair_...`, and
repeats the request with `restored_object_key`. The function verifies both
object states, promotes the staging image into a new durable key for the owner's
current tier, validates that owner prefix, and calls service-only
`repair_owned_scan_image_reference`. One transaction replaces the exact URL
across scan arrays, recursive captured-media JSON, normalized media rows, and
matching Explore snapshots owned by the same account. A persistence failure
causes best-effort deletion of the new promoted object.

The route fails closed while account deletion is active, never accepts a target
user ID from HTTP, and is not a general image-editing/replacement API. Local
file discovery and confidence constraints are documented in
[`system-architecture/03-image-pipeline.md`](../system-architecture/03-image-pipeline.md).

## Explore Media Health (`reconcile-explore-media-health`)

Published observation availability is verified separately from client display
and from author/moderation state. The service-role worker leases due active
`explore_post_media` rows, performs signed direct R2-origin `HEAD` requests with
required bucket-scoped read-only credentials, and records every result through a
claim-token-fenced RPC.

One `404` creates `suspected_missing`; a second direct `404` at least five
minutes later confirms `missing`. Transport errors, timeouts, credential
failures, `5xx`, and CDN/client errors only retry. Public projections omit a
confirmed-missing item and hide an all-missing post as system
`quarantined`—without setting `unshared_at`, changing moderation, or deleting
the post and engagement.

`get-explore-media-incidents` exposes only the authenticated owner's active
recovery queue in the canonical `{"data":[...]}` envelope. Corrected iOS builds
temporarily accept the older deployed direct-array envelope as an exact
compatibility shape, while rejecting every other malformed success body.
`ingest-r2-media-events` accepts optional trusted event batches under a
dedicated secret and merely advances due time. Scheduled origin checks are the
source of truth. A successful `/repair-scan-image` metadata transaction resets
matching item health and public projection restores automatically if ordinary
publication rules still pass.

The backing mixed user/server incident RPC dispatches on bound user identity
first and requires exact `auth.uid() = self_id` for a user caller. Only its
no-user branch invokes `internal.require_service_role()`. Migration
`20260727183356_restore_identity_first_media_incident_guard.sql` restores this
final contract after a later migration accidentally reintroduced role-first
dispatch.

The canonical product decision, state machine, user communication, security,
monitoring, and rollout contract is
[`12-explore-media-health-and-quarantine.md`](./12-explore-media-health-and-quarantine.md).

## The Public Avatar Promotion Node (`update-public-avatar`)

The `/update-public-avatar` Edge Function promotes a staged, user-owned image
into durable public profile media. It is app-facing and compatible with
anonymous Supabase sessions: Supabase gateway JWT verification is disabled in
`services/supabase/config.toml`, and the function resolves identity through
`withEdgeHandler`.

The request body is:

```json
{
  "r2_object_key": "staging/a1b2c3d4-e5f6-7890-abcd-ef1234567890/avatar_11111111-1111-4111-8111-111111111111.webp",
  "mime_type": "image/webp"
}
```

`r2_object_key` must validate through the shared staging-key guard and begin
with `staging/{authenticatedUserId}/`. Wrong-user keys return `403`; path
traversal and unsupported MIME types return `400`. Supported avatar MIME types
are `image/webp` and `image/jpeg`.

On success the function:

1. Copies the staged object to `avatars/{userId}/{uuid}.webp` or
   `avatars/{userId}/{uuid}.jpg`.
2. Updates `public.users.custom_avatar_url`,
   `public.users.custom_avatar_updated_at`, and
   `public.users.public_avatar_url`.
3. Deletes only the previous custom avatar when it is a
   `https://media.merian.app/avatars/{sameUserId}/...` URL.
4. Returns:

```json
{
  "avatar_url": "https://media.merian.app/avatars/a1b2c3d4-e5f6-7890-abcd-ef1234567890/22222222-2222-4222-8222-222222222222.webp"
}
```

OAuth/provider avatars remain the fallback. Database identity refresh helpers
resolve public avatars as `custom_avatar_url` first, then provider metadata via
`extract_public_avatar_url(...)`.

## The Public Display Name Node (`update-public-display-name`)

The `/update-public-display-name` Edge Function lets guest and signed-in users
choose the public name shown on Profile and Explore identity surfaces. It is
app-facing and compatible with anonymous Supabase sessions through
`withEdgeHandler`.

The request body is:

```json
{
  "display_name": "River Wren"
}
```

The function trims and collapses whitespace, rejects empty/control-character
names, caps names at 40 characters, and updates
`public.users.public_author_name` with
`public_identity_source = 'display_name'`. On success it returns:

```json
{
  "display_name": "River Wren"
}
```

## The Edge Inference Node (`identify`)

The `/identify` Edge Function acts as the inference proxy:

1. **Auth**: Receives a structured payload from iOS. The `Authorization` header
   JWT is verified via `requireAuth` inside `withEdgeHandler`. Merian uses
   anonymous ES256 sessions (`signInAnonymously`), so the default Supabase
   `verify_jwt` Edge Middleware is disabled in `services/supabase/config.toml`
   (`verify_jwt = false`). Auth is handled manually via the Supabase SDK.
2. **Direct Base64 Transfer**: If the iOS client sends `imageBase64s`, the Edge
   Function validates declared request `Content-Length`, then parses the JSON
   through `readRequestJsonWithinBudget` so chunked or missing-length bodies are
   counted while streaming. Aggregate base64 character budgets are checked
   before the strings are passed as Gemini `inlineData`. It does not decode
   inline images into a second full buffer on the Edge path.
3. **Legacy AWS Fallback (`_shared/aws.ts`)**: If inline images are absent
   (e.g., during background `URLSession` uploads where the image was already
   staged to R2), the function falls back to fetching from R2 through
   `_shared/identify/media.ts`. Responses are processed serially through
   `readResponseArrayBufferWithinBudget`, which reads chunks, increments the
   running byte counter before retaining each chunk, cancels the stream on
   overflow, and returns HTTP 413 if the accumulated total exceeds the media
   budget. The `Content-Length` header is used as a per-image pre-check to
   reject oversized images early, but is not the authoritative guard — chunked
   transfer encoding makes this header absent on some R2 responses.
4. **Google Gemini Model Selection**: Pro users use `gemini-2.5-pro` for maximum
   identification depth (rare species, fossils, subspecies). Free users use
   `gemini-2.5-flash` for 2–3× lower latency. The model is chosen immediately
   after the tier SELECT — before the Gemini call — so both tiers receive the
   correct model. Generation uses `temperature: 0.1` for rigid JSON output. The
   schema explicitly instructs Gemini to extract Data-as-a-Service (DaaS)
   parameters: phenology (`life_stage`, `reproductive_condition`), sex
   annotation (`sex`, `sex_confidence`, `sex_evidence`), population counts
   (`individual_count`), and cross-species relationships
   (`ecological_interactions`) synchronously within this zero-OOM primary pass.
5. **Durability Boundary and Optional Edge Decoupling**: `/identify-multimodal`
   claims a scan-ingestion job after media validation and before AI inference.
   Claim and owner-row recovery share a transaction-scoped per-scan advisory
   lock; recovery-first writes the row plus completed recovery ledger
   atomically, while claim-first makes recovery defer before provider work.
   After inference, one service-only finalization transaction checks every
   claimed staging-key disposition, rebuilds ready canonical image/video/audio
   rows, and marks the ledger complete last. Only then can that fresh
   provider-owning invocation return success. A later same-UUID invocation may
   return a marked reconstructed replay from the exact owner row while canonical
   repair remains retryable, without redispatching the provider. Field Chat,
   Explore, field trips, and owner sync can therefore use the returned `scan_id`
   immediately. Analytics, group tags, and candidate enrichment remain deferred
   via `runBackground(task)` from `_shared/edgeHandler.ts`. Compatibility
   scan-producing endpoints establish the same job/intent ledger atomically
   before inference, using multimodal-shaped sanitized intents so staged media
   and text-only rows have the same recovery surface. Setup is fail-closed and
   takes the same per-scan lock; they can complete only through the shared
   finalization RPC. Active multimodal persistence failures are captured in the
   older dead-letter table as a fallback and return retryable
   `scan_persistence_failed` instead of delivering a local-only observation.
   Compatibility insertion and finalization are also awaited. A failure before
   the exact owner row returns retryable 503. A finalizer failure after that row
   was inserted may return the already validated compatibility response, but
   leaves the ledger `failed_retryable` for no-provider-call canonical
   reconciliation. The job ledger gives `/check-scan-status` live state,
   including bulk status probes, atomic authenticated single-row repair, and
   video-completeness checks via `required_video_count`; dead letters are legacy
   ops evidence rather than the primary recovery surface. Replay is safe because
   `insertScan` uses `ignoreDuplicates: true` and then proves the row exists for
   the authenticated owner before success. Repair writes independently defer to
   active/retryable ingestion. Terminal recovery permits explicit
   `replay_exhausted`, or exact `media_reconciliation_abandoned` only with the
   matching composite dead-letter/quota/media-lifecycle proof. Current/later
   policy, unproven-abandonment, and arbitrary terminal state remains closed. A
   bounded service-only proof RPC gives signing the same database decision;
   proof and recovery signatures are registered in the privileged-routine ledger
   and reached by exact production no-write readiness probes. Server replay and
   media reconciliation use the same finalization RPC instead of directly
   writing `complete`; compatibility identify/audio/describe routes have no
   direct complete path either. A catalog trigger independently rejects
   completion unless that transaction publishes the exact owner-and-scan
   finalization fence. Completed status and scan identity are immutable. The
   atomic ghost-profile merge remains compatible through its pre-existing exact
   source/target/enabled transaction-local markers; no generic service-key owner
   update is accepted.
6. **Moderation Pipeline (`_shared/identify/moderation.ts`)**: Evaluates Gemini
   Safety Ratings before scan-media publication and final scan insertion. Unsafe
   media increments abuse strikes, sets `is_shadowbanned` when the new total
   reaches three, deletes staged R2 objects, and rejects the observation. Safe
   biological media is promoted into durable scan storage under the current
   `.userTier` prefix. The shared moderation module calls `getR2Config()` once
   at the top and reuses the resulting `AwsClient`. **Moderation ERROR guard**:
   When `modResult.status === "ERROR"` (for example, an abuse-strike write or
   promotion batch fails), the active multimodal durability boundary rolls back
   promoted objects and returns retryable `503 scan_persistence_failed`;
   compatibility required insertion halts and records its failure. Neither path
   inserts a scan from an unrecorded or operationally uncertain moderation
   result. Copy, promotion, and staging deletion responses are checked
   explicitly. Completion-sensitive deletion accepts only R2 2xx or idempotent
   404; every other provider response fails before a deletion disposition can be
   finalized.
7. **R2 Promotion Rollback (Reference Safety First)**: After `moderation.ts`
   successfully copies binaries from `staging/` to `public_uploads/`, every scan
   adapter writes idempotently and rereads the exact `(scan_id, user_id)` row. A
   returned database rejection plus a definitive missing-owner read permits
   status-checked R2 rollback. A timeout, lost write response, reported-success
   anomaly, or unavailable owner read preserves promoted objects and committed
   quota while returning retryable 503. Preventing an orphan must never delete
   an object that a transaction may already have committed into a scan.
8. **Enrichment & Reference Imagery**: Wikipedia (deep-linked URLs and paragraph
   extracts), GBIF Occurrence (verified field imagery), and GBIF vernacular
   names (`alternative_common_names`) lookups run concurrently via
   `Promise.allSettled()` behind the shared 2.5-second outbound deadline and 256
   KiB JSON response ceiling. The vernacular names result is stored in
   `species_dictionary.alternative_common_names` and returned as
   `alternative_common_names` in the identify response on Cache Hit. The
   ingestion pipeline writes verified image URLs into both the legacy
   comma-separated `species_dictionary.reference_image_url` cache and normalized
   `species_reference_images` rows; public dictionary/Explore readers prefer
   normalized rows and fall back to the legacy cache. These dictionary writes
   also record field-level provenance in `species_content_provenance` so stale
   or low-confidence species content can be refreshed deliberately later. The
   pipeline _exclusively_ sources reference imagery from these verified APIs to
   prevent LLM hallucinations. `extractJson<unknown>(text)` from
   `_shared/gemini.ts` handles only outer JSON syntax because Gemini can still
   wrap output in markdown fences. The extracted value is parsed against the
   dependency-free executable model contract in `_shared/identify/contract.ts`.
   After normalization, cache hydration, and server enrichment, the complete
   `{ success, data }` payload is parsed again against the final wire contract
   before persistence or delivery. These gates enforce nested types,
   requiredness, nullability, enums, string/cardinality limits, safe integers,
   and numeric bounds. Malformed provider JSON/model output returns HTTP 503; a
   final enriched-payload mismatch returns HTTP 502 with stable code
   `identify_response_invalid`. Internal contract details are logged but not
   exposed. **503 vs 400 for Gemini errors**: The `catch (genError)` block
   wrapping the Gemini call returns HTTP **503** (Service Unavailable) for
   transient Gemini errors — iOS treats 4xx as permanent and tombstones the
   scan, whereas 503 causes the offline queue to retain the scan for retry.
   Non-STOP finish reasons also return 503, **except** `SAFETY` and
   `PROHIBITED_CONTENT` which return 400 (permanent content policy failure — no
   point retrying).
9. **Swift `JSONDecoder` Null Protection**: `wikipedia_overview` is a flat
   `TEXT` column on `species_dictionary` — it can be `null` if Wikipedia has no
   entry. The iOS decoding struct types this as
   `let wikipedia_overview: String?`. It is returned directly from the Edge
   function as `wikipedia_overview` in the API response and stored as
   `LocalScanRecord.wikipediaOverview`.
10. **Species Dictionary Upsert**: Calls
    `supabaseAdmin.from('species_dictionary').upsert()` with
    `{ onConflict: "scientific_name", ignoreDuplicates: false }`. This always
    merges on conflict rather than skipping, ensuring that locale-miss Cache
    Misses can add new `common_names` entries to an existing row. Existing
    `common_names.en` values are canonical and win over scan-level names; the
    scan name can only fill an empty English name for a normalized biological
    subject. To prevent lower-quality Flash-generated data from overwriting
    previously stored Pro-sourced taxonomy, toxicity, IUCN status, and habitat
    data, all those fields are written using `??` null-coalescing — existing
    non-null values are always preserved. `common_names` is merged through the
    shared keyed helper so existing English names remain stable while missing
    locale keys can still be filled.
11. **Atomic Entitlement + Quota Reservation**: Before provider work,
    `_shared/aiQuota.ts` calls `reserve_ai_quota` with the authenticated user,
    operation, UUID request key, original `client_scan_id`, HMAC address bucket,
    protocol, and server-derived Flash-fallback eligibility. The transaction
    locks the user first, resolves paid Pro → complimentary Pro → free, and
    atomically acquires a hold from the private three-scan lifetime ledger.
    Provider daily/per-minute counters remain separate and are retained after an
    attempted provider call even if a terminal failure releases the user's hold.
    Paid passes with stale expiry resolve free even before the expiry worker
    repairs the row. A missing `public.users` row is an identity-system fault
    and fails closed. Successful Auth signup is responsible for creating that
    row before inference. Optional group-tag generation uses
    `_shared/groupTagQuota.ts`, the separate `scan_group_tag_enrichment` policy,
    and its database-selected model; public routes cannot dispatch the
    biological helper directly.
12. **Scan Insert**: Calls `supabaseAdmin.from('scans').insert()` using the
    service role key, binding the scan to the authenticated `user.id`. All
    environmental telemetry (time of day, month, locale, semantic location,
    LiDAR depth scale), Google Cloud LLM token metrics (`llm_prompt_tokens`,
    `llm_candidate_tokens`, `llm_thinking_tokens`, `llm_cached_tokens`,
    `llm_total_tokens` from Gemini's `usageMetadata`), the selected
    `inference_tier`, `extracted_visual_traits` (3 bullet-point arrays
    representing exactly what physical features led to the ID), `ai_reasoning`
    (Gemini's visual identification justification), and `colors` (1–3 dominant
    biological colors) are all written in the same insert. `llm_thinking_tokens`
    captures Gemini's internal reasoning token consumption and is billed at the
    output token rate — it is the dominant cost driver for Pro scans.
    `llm_cached_tokens` is non-zero when Gemini's implicit context caching
    served the system instruction prefix from cache (Flash only; requires the
    prefix to exceed 2,048 tokens); cached tokens are billed at 75% off the
    standard input rate. `colors` feeds into `semanticTags` on the Swift side
    for full-text search. `ai_reasoning` is fetched back during historical cloud
    sync and stored as `LocalScanRecord.aiReasoning`. The legacy `/identify`
    Flash route explicitly uses a 2,048-token thinking budget, while
    `/identify-multimodal` preserves its existing Flash provider-default
    behavior; both primary Pro routes retain their existing explicit 5,000-token
    budget. Note: `group_tags` are stored on `species_dictionary`, not `scans`.
    **LLM field sanitization bounds** (applied in `index.ts` after scientific
    name sanitization, before the DB insert): `colors`,
    `extracted_visual_traits`, and `ecological_interactions` are each capped at
    10 items; `ai_reasoning` is truncated to 2000 characters; `individual_count`
    is validated as a positive integer ≤ 99999; `estimated_size_cm`
    (client-supplied) is validated as a positive finite number ≤ 50000. **GPS
    coordinate range validation**: `gpsLatitude` and `gpsLongitude` from the
    client payload are validated against physical bounds (`−90 ≤ lat ≤ 90`,
    `−180 ≤ lon ≤ 180`). Out-of-range values are sanitised to `null` (stored as
    `safeGpsLat`/`safeGpsLon`) rather than rejecting the request — location is
    supplementary metadata and a bad coordinate must not abort identification.
    **`candidates` cap**: the `candidates` array received from Gemini is capped
    at 5 items before `payloadReadyForClient` is built, bounding the JSONB
    column and client decode size. These guards protect the V8 heap and SQLite
    columns from unbounded LLM output.
13. **Response format**: Returns `{ success: true, data: { ... } }` to the iOS
    client via `jsonResponse()`.

## The Public Species Dictionary Node (`species-dictionary`)

The `/species-dictionary` Edge Function is a public read-only projection over
species-level dictionary data. It powers the standalone
`SpeciesDictionaryPageView` opened from Insight similar-species cards and
Explore post detail similar-species cards, plus the server-rendered
`/species/[speciesId]/[slug]` web route and its UUID-only compatibility
redirect.

Key rules:

- `verify_jwt = false` is configured in `services/supabase/config.toml`.
- The function intentionally does not call `withEdgeHandler` / `requireAuth`;
  user identity must not affect the response.
- The service role key is used only for tightly scoped reads from
  `species_dictionary`, `species_reference_images`, and `species_lookalikes`.
- The response includes canonical names, taxonomy, hazard/conservation fields,
  Wikipedia/habitat/GBIF fields, group tags, reference images, and read-only
  lookalikes.
- The response wrapper includes `schema_version: 1`; new clients should use it
  as the public species contract marker, while older clients can keep decoding
  `data` only.
- Successful `200 OK` responses send public cache headers
  (`Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`). Error responses intentionally do not opt into
  public caching.
- The additive `content_quality` field classifies each row as `complete`,
  `sparse`, or `needs_enrichment` from public imagery, overview,
  habitat/distribution, and taxonomy signals.
- New `species_dictionary` inserts enqueue missing species-level hydration work
  through the database trigger added in
  `20260707153931_species_dictionary_enrichment_queue_backfill.sql`, so scan,
  Community ID, taxonomy import, and repair paths share one enrichment contract.
- The response must not include scan IDs, user IDs, Explore post IDs, field
  notes, comments, locations, local user media, per-scan AI reasoning, or
  preferred-name overrides.
- Lookalikes are hydrated with the explicit `species_dictionary!lookalike_id` FK
  hint because `species_lookalikes` has two foreign keys to
  `species_dictionary`.
- V1 does not expose provenance in the API response. Freshness/source data is
  stored separately in `species_content_provenance` for internal refresh
  workflows and future curation surfaces.
- Normalized image rows, legacy image caches, catalog thumbnails, and lookalike
  thumbnails use the same exact external-media policy. A denied first URL is
  omitted and the next permitted ordered URL is promoted; the response schema
  and species/navigation rows are unchanged.
- The Next.js server invokes this function with `species_id`; it does not query
  broad species, scan, profile, or Explore tables. Invalid UUIDs and function
  `404` responses become non-indexable web 404s, while transient failures stay
  server errors.
- The web mapper runs `publicWebReferenceImageAttributionIssues(...)` before
  page or metadata use, omits every image missing license or attribution, and
  does not render lookalike thumbnails because that payload lacks equivalent
  rights fields.

See `docs/backend-and-data/05-api-contracts.md`,
`docs/features-and-hardware/16-species-dictionary.md`, and
`docs/features-and-hardware/17-public-web-share-pages.md` for the
request/response, iOS, and web contracts.

## The Authenticated Species Sightings Node (`get-explore-species-posts`)

`/get-explore-species-posts` keeps viewer-aware Explore cards out of the public,
cacheable `/species-dictionary` response. It requires the normal app session,
validates a canonical species UUID and a 1...100 limit, and calls the
service-role-only `public.get_explore_species_posts(...)` RPC.

The RPC reuses `public.explore_projected_post_cards(viewer_id)` for visibility
and privacy, then matches the exact effective species. Confirmed scan taxonomy
uses `confirmed_species_id`; `community_resolved` posts use the projected taxon
node's canonical `species_id`. Genus and lookalike similarity never participate.
Rows order by `image_quality_score DESC NULLS LAST`, `shared_at DESC`, and post
UUID descending. The Edge Function uses the internal score to build a stable
cursor, removes it from card payloads, then applies the normal Explore username,
Pro badge, hashtag, and media enrichment.

## The Public Species Observation Stats Node (`species-observation-stats`)

The `/species-observation-stats` Edge Function returns global public iNaturalist
aggregates for reusable species observation charts. It powers the Insight Sheet
and Species Dictionary chart cards, while local Merian logs are aggregated
entirely on-device by iOS.

Key rules:

- `verify_jwt = false` is configured in `services/supabase/config.toml`.
- The response remains public. Missing/project-key Authorization uses an IP-only
  budget; a valid user JWT adds a per-user budget; an invalid supplied user
  token returns `401`. The atomic IP preflight runs before optional token
  validation, bounding invalid-token traffic before it reaches Supabase Auth.
  The hosted gateway must overwrite the proxy-address headers used for the IP
  HMAC; a custom proxy must not pass through caller-controlled values.
- `species_id` and `scientific_name` are both required. A service-only RPC
  rate-limits the request, resolves the UUID from `species_dictionary`, and
  rejects a non-canonical name before provider work. Compatibility POST bodies
  are stream-bounded to 4 KiB before JSON decoding.
- The provider scope is global and source is currently only `inaturalist`.
- Requests prefer a stored `inaturalist_taxon_id`. A lease owner may resolve an
  exact canonical dictionary name through `/v1/taxa`; observation calls require
  the resulting `taxon_id`. There is no free-form `taxon_name` fallback.
- Request limits are 60/user/minute and 120/IP/minute. Cold population adds
  12/user/minute, 30/IP/minute, and a global four-populations/minute provider
  ceiling. IPs are stored only as daily, purpose-separated server HMACs.
- `internal.species_observation_stats_population_leases` issues a fenced
  90-second token. Only the current token can finalize a cache row, preventing
  cross-isolate stampedes and late-owner overwrites.
- Final cache TTLs are seven days (`fresh`), 24 hours (`no_data`), one hour
  (`partial`), and five minutes (`unavailable`). Exact taxon misses and provider
  incidents therefore have negative-cache damping.
- Cold misses return core totals, seasonality, and history as
  `status: "partial"` while life-stage and sex annotation buckets refresh via
  `runBackground`. Usable stale rows return immediately and refresh in the
  background.
- Provider calls have five-second fetch timeouts, 15/45-second foreground and
  background deadlines, and a one-MiB streaming response cap.
- Database RPCs and cache reads are client-aborted after five seconds; each
  privileged RPC also carries a five-second PostgreSQL statement timeout.
- Partial provider failures also return `status: "partial"` when enough buckets
  are still available to render a useful chart. Any provider failure with no
  useful data becomes `unavailable`; an empty failed result is never cached as
  `partial`.
- A failed refresh preserves a positive payload that is still within the 37-day
  retention ceiling. The database marks it `stale`, retains the original
  `fetched_at`, records the current row-level provider error, and retries after
  a five-minute backoff instead of replacing it with empty unavailable data.
- iOS validates the UUID/name bounds before networking and accepts a response
  for memoization only when `schema_version >= 2` and the returned canonical
  identity matches the request.
- Successful responses vary only by content encoding, not Authorization, because
  the public body is identity-independent. This preserves shared cache reuse
  across sessions; errors stay private/no-store and authorization-varying.
- The response must not include Merian scan IDs, user IDs, Explore post IDs,
  field notes, comments, locations, local media, local observation counts, or
  preferred-name overrides.

See `docs/features-and-hardware/18-species-observation-charts.md` and
`services/supabase/functions/species-observation-stats/README.md` for the
request/response contract, iNaturalist annotation mappings, cache semantics, and
iOS surface.

## The Scheduled Species Content Refresh Node (`refresh-species-content`)

The `/refresh-species-content` Edge Function is an internal service-role worker
invoked by `pg_cron`/`pg_net`. It claims `gbif_wikipedia_reference` work from
`species_enrichment_jobs`, falls back to
`public.get_species_content_refresh_queue(...)` when no first-class jobs are
available, batches stale rows by species, refreshes supported public fields from
GBIF/Wikipedia, writes updated dictionary fields, synchronizes normalized
reference imagery through `public.replace_species_reference_images(...)`, and
records fresh provenance rows.

Key rules:

- `verify_jwt = false` is configured for `pg_net` compatibility, but every
  request must carry one exact platform-managed current or legacy server key and
  is checked with `timingSafeCompare`. Opaque keys use `apikey` only.
- The scheduled job `refresh_species_content_hourly` runs at minute 17 every
  hour with `{ "limit": 25 }`; manual service-role calls may use `dry_run`,
  `as_of`, `limit`, and `content_keys`.
- Newly inserted or backfilled sparse dictionary rows are queued in
  `species_enrichment_jobs`; this worker claims `gbif_wikipedia_reference` jobs
  before falling back to the older provenance queue.
- Per-species refresh work runs with a concurrency cap of 4 to stay within Edge
  runtime bounds without overwhelming GBIF/Wikipedia.
- V1 refreshes only fields backed by authoritative external APIs:
  `alternative_common_names`, `taxonomy`, `wikipedia_url`, `wikipedia_overview`,
  `gbif_taxon_key`, and `reference_images`.
- Unsupported queued keys are reported as skipped rather than overwritten.
  `habitat_description`, `lookalikes`, and `group_tags` are handled by
  `/refresh-species-model-content`; common-name overrides,
  `iucn_red_list_status`, and `hazard_type` remain curation-owned.
- Reference image refreshes update the legacy comma-separated cache and the
  normalized `species_reference_images` table. Existing license/attribution
  metadata is preserved when a refreshed URL matches an existing row. Merian
  community rows are preserved and ordered separately by the Merian reference
  image worker. Denied provider media is removed before both writes, while the
  database trigger from
  `20260719023147_suppress_european_wildcat_roadkill_image.sql` prevents the
  current exact outlier from being reinserted by any service-role repair path.

## The Scheduled Species Model Content Node (`refresh-species-model-content`)

The `/refresh-species-model-content` Edge Function is the paired internal
service-role worker for model-heavy species dictionary hydration. It claims
`habitat`, `lookalikes`, and `group_tags` jobs from `species_enrichment_jobs`,
reuses the species-level biology primitives behind `enrich-scan`, writes results
to `species_dictionary` and `species_lookalikes`, records provenance, and marks
each job succeeded or failed.

Key rules:

- `verify_jwt = false` is configured for `pg_net` compatibility, but every
  request must carry one exact platform-managed current or legacy server key and
  is checked with `timingSafeCompare`. Opaque keys use `apikey` only.
- The scheduled job runs with `{ "limit": 12 }`; manual service-role calls may
  use `dry_run`, `as_of`, `limit`, and `content_groups`.
- Refresh work runs with a concurrency cap of 2 to avoid stampeding Gemini.
- The worker never attaches media to a species and never changes scan identity;
  scan-to-species attachment remains owner publish through
  `confirmed_species_id`.

## The Scheduled Merian Reference Image Node (`refresh-merian-reference-images`)

The `/refresh-merian-reference-images` Edge Function is an internal service-role
worker invoked by `pg_cron`/`pg_net`. It promotes high-quality, currently
published Explore media into public species dictionary galleries with
`source = "merian"`.

Key rules:

- `verify_jwt = false` is configured for `pg_net` compatibility, but every
  request must carry one exact platform-managed current or legacy server key and
  is checked with `timingSafeCompare`. Opaque keys use `apikey` only.
- The scheduled job `refresh_merian_reference_images_hourly` runs at minute 37
  every hour with
  `{ "quality_threshold": 80, "species_confidence_threshold": 0.95, "per_species_limit": 8 }`.
- Selection happens transactionally in
  `public.refresh_merian_reference_images(...)`: visible Explore posts only, all
  non-empty image URLs from qualifying scans, `image_quality_score >= 80`,
  `ai_confidence_score >= 0.95` unless `confirmed_species_id` is present,
  species resolution through `COALESCE(confirmed_species_id, species_id)`, and
  up to 8 promoted images per species.
- Public rows store only `url`, the stable technical `source = "merian"`,
  `license = "Used with permission via Naturebook"`, and the public author label
  in `attribution`. This uses `public_author_name`, not the username handle
  unless the display label itself is the default username. Source scan/post/user
  IDs remain in the private `species_reference_image_merian_sources` table along
  with the private confidence/provenance snapshot used for promotion.
- `/species-dictionary` performs one bounded lookup by the promoted source's
  stable `(species_id, image_url)` key and joins `users.public_username`. This
  still resolves legacy promoted rows whose nullable `reference_image_id` link
  has not been repaired. The public image item adds only `author_user_id` and
  the current `author_username`; source scan/post IDs and all other provenance
  stay out of the response.
- If an Explore post is unshared, media is cleared, the source scan geoprivacy
  becomes private, the scan is tombstoned, or the author is shadowbanned, the
  next refresh removes the corresponding Merian public reference image. This
  reference-image promotion gate is stricter than ordinary Explore visibility: a
  post-level `private` location setting can still leave the post visible, but
  private backing scans are not promoted into species reference imagery.

## The Unified Multi-Modal Inference Node (`identify-multimodal`)

The `/identify-multimodal` Edge Function is the primary client-facing inference
path today. It unifies the image, audio, and text-only request shapes into one
pipeline while the legacy endpoints remain deployed for compatibility.

1. **Payload Assembly**: It accepts `imageBase64s`, image `r2ObjectKeys`, inline
   `audioBase64s`, staged `audioR2ObjectKeys`, staged `videoR2ObjectKeys`,
   `visualMediaItems` / `visual_media_items`, `audioMediaItems` /
   `audio_media_items`, `videoFrameCount`, and `observation_contexts` arrays.
   Video scans send five ordered sampled frames through the normal image payload
   path for AI inference and, when available, send an extracted accompanying
   Int16 PCM WAV audio track through the normal audio path. The upload-bounded
   playback `.mp4` is staged only for persistence after moderation; it is
   usually a compressed 720p export, with an original-file fallback only when
   the source remains under the hard video byte cap. `visualMediaItems` is the
   preferred contract for telling the prompt which visual inputs are still
   photos and which are ordered frames from one or more short clips; still-photo
   entries may add a validated top-left-normalized `focusRegion` as a tentative
   client-side attention hint without replacing the full image. The hint does
   not prove or force the primary subject; `audioMediaItems` identifies
   standalone audio versus audio extracted from a video clip. If optional video
   audio cannot be parsed or is too short after trimming, the edge skips that
   audio when visual evidence is present instead of rejecting the whole video
   scan. `videoFrameCount` remains a legacy fallback when older clients omit
   explicit media metadata.
2. **WAV Preprocessing**: Audio data is preflighted before decode/fetch. The
   endpoint rejects oversized declared request `Content-Length` headers before
   body parsing, then uses `readRequestJsonWithinBudget` as the authoritative
   JSON cap for missing-length and chunked bodies. Inline base64 length, raw
   byte size, clip count, staged-key ownership, R2 stream byte caps, and `..`
   traversal checks are delegated to `_shared/identify/media.ts`. Audio buffers
   are processed serially via `processWAV` (mono mix, silence trim, 16kHz
   resample) to keep V8 heap pressure predictable.
3. **Dynamic Dispatch Logic**: Generates inference payload based on the
   submitted modalities:
   - **Combined Text, Audio & Vision**: Uses
     `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` focusing on comprehensive
     multi-sensory synthesis. This branch preserves its established
     visual/acoustic arbitration and does not currently interpolate the complete
     image-only whole-frame primary-subject instruction. Only still photos with
     an accepted `focusRegion` receive the separate tentative per-photo warning;
     unhinted stills and sampled video frames do not.
   - **Audio-only (`audioBase64s`)**: Dispatches using
     `BIOACOUSTIC_SYSTEM_INSTRUCTION`, leveraging specific bioacoustic AI
     interpretation.
   - **Vision-only (`imageBase64s`)**: Follows the standard vision
     identification path and asks the provider to select the intended
     whole-frame visual subject before taxonomy. When a video is present, prompt
     context identifies those visual inputs as ordered frames from one short
     clip.
   - **Text-only (`observation_contexts`)**: Follows the legacy sighting
     pipeline utilizing only the user's structured observation text.
4. The current iOS client sends queued images via `r2ObjectKeys`, queued audio
   via `audioR2ObjectKeys`, queued videos via `videoR2ObjectKeys`, live
   foreground video uploads through the same staging contract, live foreground
   audio via inline `audioBase64s`, and text via `observation_contexts`.
   Playback videos are never sent to Gemini as public or inference media; only
   five sampled frames and optional accompanying audio enter the prompt.
   Telemetry on this path is camelCase (`gpsLatitude`, `semanticLocation`,
   `deviceTimeZone`, etc.); the server also accepts legacy snake_case aliases
   for backward compatibility during offline queue replay and staged endpoint
   migration.
5. Candidate handling on `/identify-multimodal` now matches `/identify`:
   scientific names are sanitized before cache lookup/persistence, `candidates`
   are stripped at `confidence_score >= diagnosticTrigger`, cached English
   common names are attached synchronously when available, and candidate cache
   misses are enriched in the background so the next scan is warm. A shared
   processed-material guard runs before this gate: manufactured/processed
   objects are normalized to non-biological, have candidates and source-species
   scientific names cleared, skip dictionary novelty, and cannot upsert
   `species_dictionary`. That runtime guard does not infer scene composition and
   cannot independently demote a real organism that Gemini selected from the
   background. Primary-subject selection remains provider guidance.
6. Persisted multimodal scan imagery still lands in `scans.image_storage_urls`;
   promoted playback clips land separately in `scans.video_storage_urls`. Staged
   audio, including extracted video audio, is an inference input, not a public
   media artifact; `identify-multimodal` deletes `audioR2ObjectKeys` from
   staging after successful durable ingestion. Staged video keys are a
   durability gate: they are promoted only after the sampled frames pass
   moderation, and any promotion shortfall fails the video scan instead of
   inserting a frame-only row. Successful video inserts write both
   `video_storage_urls` and a `captured_media` video item before the client
   treats the scan as complete. Upload-session rows created by
   `/generate-upload-urls` are linked to the scan during this finalization step:
   promoted visual/video rows become `promoted`, consumed audio rows become
   `deleted`, and failed finalization leaves a retryable `failed` trail. Before
   AI inference starts, the same request claims `scan_ingestion_jobs` with
   expected media counts, staged object keys, recovered upload-session ids, and
   a normalized `manifest_checksum`; that job row is the server-side source of
   truth for status polling, retry ownership, and later media reconciliation.
   The request also records a `scan_ingestion_intents` row with the sanitized
   schema-v3 replay payload and a `payload_checksum`; observation contexts are
   text-only, inline base64 media is redacted and marks the intent
   non-resumable, while queued/staged media requests become eligible for future
   server-side replay. The `scan_media_assets` lifecycle table is refreshed
   inside the required database finalization transaction. The ledger cannot
   become complete unless every claimed promoted URL is represented by a ready
   canonical row, so newer media readers can use ready display/playback rows
   instead of inferring user-visible media from compatibility arrays.

### Latency Boundary and Database Round Trips

The `/identify-multimodal` body, model selection, prompt/schema, thinking
budgets, image resolution, output limits, and one-call-per-scan behavior remain
unchanged. Free uses `gemini-2.5-flash`; Pro uses `gemini-2.5-pro`.

Before inference, the service-role-only `begin_scan_ingestion` RPC combines
upload-session lookup, ingestion-job claim, sanitized intent recording, and the
`ai_inference_started` transition into one database round trip. It computes the
manifest and payload checksums only after the resolved upload-session ids are
merged into the stored payload. After Gemini,
`hydrate_identification_dictionary` combines cached primary-species hydration
and candidate common-name lookup. Both functions revoke execution from `PUBLIC`,
`anon`, and `authenticated`; only `service_role` may call them.

Primary cache-miss Wikipedia/GBIF resolution, moderation, required media
promotion, and scan insertion complete before success for every current
multimodal observation. Analytics, group tags, and candidate enrichment run
behind `EdgeRuntime.waitUntil` so they cannot delay the response after the
durability boundary.

Successful responses expose privacy-safe `Server-Timing` metrics for auth, body
read, tier resolution, pre-Gemini database work, Gemini, dictionary hydration,
post-Gemini response work, and total Edge time. The structured latency event is
tagged only by tier, model, image count, payload bytes, Edge region, and
constrained-network state. `gemini_latency_ms` ends immediately after
`generateContent` returns.

`/update-scan-context` accepts late elevation, weather, and semantic-location
fields keyed by `scan_id`. `apply_or_stage_scan_context` updates an existing
owner scan or stores the values in `scan_deferred_context_updates`; a before-
insert trigger merges staged context when the scan is created. RLS is enabled
and direct client table/function privileges are revoked.

## The Explore Social Surface

Explore uses a dedicated set of Edge Functions and SQL RPCs rather than sharing
the identify pipeline. The current shipped surface includes:

- feed + detail reads: `get-explore-feed`, `get-explore-post`,
  `get-explore-post-detail`, `get-explore-comments`
- author profile reads: `get-explore-author-profile`, `get-explore-author-posts`
- hashtag reads: `get-explore-hashtag-posts`
- map reads: `get-explore-map-points`
- community identification reads: `get-community-identification-feed`,
  `get-community-identification-activity`, `get-community-identification-detail`
- mutations: `share-scan-to-explore`, `unshare-explore-post`,
  `update-explore-field-notes`, `set-explore-post-like`, `set-user-follow`,
  `create-explore-comment`, `delete-explore-comment`,
  `toggle-explore-comment-reaction`, `report-explore-comment`,
  `report-explore-post`
- bell activity reads: `get-explore-notifications`,
  `get-explore-unread-notification-count`, `mark-explore-notifications-read`
- private viewer tools: `explore-post-chat`
- device registration and delivery: `register-push-device`,
  `send-push-notification`

`explore-post-chat` creates one private conversation per requesting viewer and
active post. The authenticated viewer ID is supplied by `withEdgeHandler`, not
the request body. Other viewers cannot read that thread; when the viewer is the
post author, they can use their own private post-scoped conversation. The Edge
Function uses service-role access internally, while its three storage tables
retain RLS ownership policies and revoke direct `anon` and `authenticated` Data
API access. Chat context comes only from the same public post/detail projections
used by Explore plus Species Dictionary fields; unpublishing the post deletes
all attached viewer conversations.

The source candidate also adds authenticated `species-dictionary-chat` for the
in-app detail page. It creates one private conversation per viewer and canonical
biological species UUID, and reloads only bounded public reference text for each
send. It is separate from the anonymous, cacheable `species-dictionary` read
route and is never called by public web pages.

Insight, Explore, and Species Dictionary sends share the service-only
`reserve_field_chat_send(...)` database boundary after migration
`20260821030027_add_species_dictionary_field_chat.sql`. It serializes per-user
cross-table daily accounting before per-conversation admission, validates the
exact subject, and inserts the user row in the same transaction as idempotency,
unanswered-request, 30-row, and 20/day checks. Edge count reads are presentation
only and cannot authorize a send. An exact committed request whose assistant is
still absent after ten minutes may use the narrow
`recover_stale_field_chat_quota(...)` proof before a newly metered retry.

Migration `20260824210544_preserve_field_chat_daily_usage.sql` makes the 20/day
contract survive conversation deletion. It stores a content-free user/UTC-day
aggregate, increments it inside the admission transaction, exposes it only
through a service-role read RPC, and conservatively sums it during Ghost merge.
The Ghost handler is part of the effective allowlist and the migration asserts
the full policy registry before commit. Conversation creation and the first user
row are now one admission transaction, so a rejected send creates no thread.

The retained-row seed cannot recover earlier same-day deletions. Under short
locks on all six conversation/message tables, PostgreSQL first removes
historical message-less threads, then records the next UTC boundary, blocks
every novel reservation through that boundary and until explicit activation, and
permanently reserves conversation insertion for the atomic RPC. It exposes only
bounded service-only cutover evidence. Exact persisted replays remain available.
Source fixtures exercise all three real reserve-delete-fresh-reserve paths and
the complete current-day public-reservation/full-merge race. Database time
advances the cutover only from `pending` to closed `ready`; a one-way
service-only transition records the exact clean candidate and migration digest
plus three candidate-derived bundle digests after all routes deploy and every
live route exposes both the `atomic-admission-v1` compatibility marker and its
`X-Merian-Field-Chat-Bundle-SHA256`. A database `ready` state force-selects the
three routes even after the migration becomes the deployment baseline. Swift and
Deno execute the same versioned prompt-label scalar fixture, including U+2013 EN
DASH, U+FEFF rejection, and U+0085 normalization. Dictionary Field Chat remains
production-held until those database cases execute without a skip, the hosted
real-token wrapper and same-SHA hosted gates pass, physical V49→V50 install-over
succeeds, immutable live-route provenance and ready-rerun selection have
retained exact-SHA evidence, and the canonical external approvals are complete.
The local handler suite already executes deterministic accepted/refused outcomes
through the actual wrapper.

The in-app notifications feed is backed by server tables, not by local client
state. Explore post activity lives in `public.explore_post_notifications`. Field
trip-only activity for comments, replies, and followed-author publications lives
in `public.field_trip_activity_notifications` and is unioned into
`get_explore_notifications` for the in-app activity sheet and unread bell.
Seasonal Field trip Challenges use their own challenge participation, badge,
entry, like, and comment tables; challenge joins, likes, badges, and progress
updates do not notify other users and never fan out to APNs. Like notifications
are recomputed from the authoritative `explore_post_likes` table after each
insert/delete so concurrency cannot drift the aggregate count, comment
notifications are created and removed via triggers on `explore_post_comments`,
comment-reaction notifications are recomputed per `(comment, emoji)` from
`explore_comment_reactions`, follow notifications are created and removed via
triggers on `user_follows`, Field trip activity is created from Field trip
publication/comment triggers, self-notifications are suppressed server-side, and
rows are pruned or hidden when relevant content is removed, a follow is removed,
or either user blocks the other.

Identify Activity is deliberately separate from these bell tables. Migration
`20260731050009_add_community_identification_activity.sql` projects
identification inserts and consensus events into service-only suggestion bursts,
standalone consensus changes, and immutable resolution milestones. Adjacent
suggestions on one request generation chain across an inclusive 60-minute
boundary. Submission-caused consensus updates enrich the burst; every resolution
remains separate.

`get-community-identification-activity` verifies the caller through
`withEdgeHandler`, derives the viewer ID from that JWT, and calls the
service-role-only `get_community_identification_activity(...)` RPC. Projection
tables have RLS enabled and no direct client privileges. Names are not stored;
up to three visible actors are attributed by `public_username` at read time
after blocking and shadowban checks. Profile/display names are not returned.
Request owner visibility, withdrawal, unshare, moderation, tombstone, media
quarantine, and usable-media rules are reapplied for every read. This endpoint
never reads or changes notification unread state.

The authenticated `/field-trips` catalog and template-detail actions use a
private viewer-specific projection that is intentionally different from public
Field trip profile/publication data. Completed standard checklist items may
include `completed_scan_id`, linking the item to its exact
`user_field_trip_item_completions.scan_id`, but the response contains no media
URL. iOS resolves that identifier only against the caller's device-local scan
library. The catalog/detail RPCs are revoked from `PUBLIC`, `anon`, and
`authenticated` and granted only to `service_role`; the Edge action supplies the
verified `user.id`. Public profiles, publications, challenge entries and badges,
Explore feed/map data, and the Scan `capture_context` projection remain
evidence-free. This contract is defined by
`20260718043218_expose_field_trip_completion_scan_ids.sql`. Template detail may
also include the requesting owner's active, non-deleted `publication_id` and
`published_at` inside `active_progress`; iOS uses only that detail-only state
for the Private/Published badge. This addition is defined by
`20260718051748_expose_field_trip_publication_status.sql` and does not expand
catalog or public/capture projections.

The scan-progress response is extended by
`20260718150932_add_credited_field_trip_progress.sql` and hardened by
`20260718162409_scope_credited_progress_to_current_attempt.sql`. Both the
standard and Seasonal Challenge progress RPCs retain their signatures,
security-definer search paths, execute permissions, and existing response
fields. They add the level number/title and completed/target counts credited by
the scan so a client can distinguish a just-completed level from the next active
level. The two migrations add response fields only, and iOS decodes those
additions optionally during staged rollout. The follow-up scope prevents a
re-identified scan with historical completions in an earlier level from
duplicating a response destination or supplying the wrong progress ring.

`20260722025411_persistent_field_trip_scan_contributions.sql` replaces the
progress entry point with an additive preferred-goal contract and enforces one
credit per scan per standard outing or Event participation. The preference is
stored only in private `field_trip_scan_goal_preferences`, validated against the
verified owner and scan-time activity window, and ignored when stale, hidden,
completed, unauthorized, noncurrent, or nonmatching. Without a valid preference,
the database uses deterministic specificity and checklist ranking. Unfinished
identification corrections can move or remove credit in the original credited
level; completed experiences are immutable for normal identification
corrections. Evidence-policy invalidation is the exception described below.

The same migration adds private
`public.get_field_trip_scan_contributions(self_id, target_scan_id)`, with
execute revoked from `PUBLIC`, `anon`, and `authenticated` and granted only to
`service_role`. `/field-trips` action `scan_contributions` supplies the verified
user ID and returns evidence-minimal labels, counts, artwork inputs, and typed
routing. It returns no media, storage URLs, coordinates, place labels, or notes.
The `/field-trips` `apply_scan_progress` body may now include optional
`preferred_goal`; legacy clients omit it and receive deterministic fallback.

`20260722064704_harden_atomic_field_trip_progress.sql` makes this path
transactional and ingestion-owned. The identify ingestion intent retains a
validated preferred goal; scan insert and relevant identification-update
triggers call `apply_field_trip_scan_progress_atomic(...)`, which applies the
standard outing, joined Event, preference, and first-outing achievement work in
one transaction and stores a private scan-revision receipt. The later
`apply_scan_progress` Edge call invokes the same RPC and receives that original
result, so app termination cannot lose the selection or unlock metadata and an
Event-side error cannot commit standard progress alone.

The hardening migration also revokes execute on every public-schema Field
trip/Event `SECURITY DEFINER` function from `PUBLIC`, `anon`, and
`authenticated`, granting only `service_role`. These routines are Edge-owned:
`withEdgeHandler` verifies the session and the Edge router supplies `self_id`.
No direct client RPC is intentionally exposed. The same migration repairs
`publish_field_trip(...)` so snapshot rows use the publication ID returned by
the upsert.

The follow-up `20260722195453_exclude_ants_from_bee_wasp_goal.sql` adds the
generic `taxonomy_excluding_family` checklist criterion. At that migration step,
Park Pollinators keeps `Hymenoptera` as the positive order for **Bee or wasp**
but excludes `Formicidae`, preventing ants from matching. Family lineage is
required for this negative criterion; an unknown family fails closed. The
migration repairs existing ant-backed credit and its derived receipts/completion
state.

`20260722211636_tighten_field_trip_goal_matching.sql` adds the conjunctive
`taxonomy_and_signal` criterion. It requires at least one populated taxonomy
rank, at least one ecology/habitat/semantic signal, and every populated
constraint to match. Active Backyard Safari and Park Pollinators goals use it
where a signal alone could accept the wrong kingdom or a broad taxonomy could
accept the wrong group. Spider goals require order `Araneae`; Backyard
**Butterfly** additionally requires the `butterfly` group tag. Context that the
saved scan contract cannot prove is removed from Park prompt copy, and the old
scene-based **Pollinator habitat** target becomes a plant-plus-meadow **Meadow
plant** target. **Bee or wasp** is also finalized as Hymenoptera plus either the
`bee` or `wasp` semantic category, preventing sawflies and other
non-bee/non-wasp members of the order from receiving credit. Compound semantic
criteria may separate accepted alternatives with `|`. The migration removes
previously credited rows that no longer satisfy the corrected rules and repairs
derived progress, receipts, badges, and publications. The exact active catalog
is maintained in the
[Field Trips matching contract](../features-and-hardware/25-field-trips.md#active-objective-matching-contract).

`20260730023042_gate_field_trip_progress_by_confidence.sql` adds the evidence
policy ahead of both standard and Event matching. Unreviewed AI identification
must meet the exact inference tier's Possible-match boundary (`Flash >= 0.75`,
`Pro >= 0.65`); explicit confirmation or a confirmed correction/community
resolution can qualify below it. Confidence, inference-tier, and confirmation
fields participate in receipt revisions, and the correction trigger re-enters
the atomic boundary when those fields change. The migration also removes prior
weak-unreviewed credit and repairs derived completion artifacts while retaining
the selected Capture-goal preference as a pending hint. The same reconciliation
applies to future evidence downgrades, including scans credited before an
experience completed: it removes standard and Event credit, reopens progress,
clears derived Event badges, and soft-deletes invalid completion publications or
entries without announcing a new completion.

`20260802053044_simplify_backyard_and_pollinator_levels.sql` moves the existing
starter checklist identities into 2/4/4 progressions and reconciles the now
exact domestic-dog goal.
`20260803015025_auto_enroll_backyard_safari_level_one.sql` then enrolls every
account without prior Backyard Safari state into Level 1 and opens an activity
period at enrollment time. A deny-by-default internal trigger does the same when
future signed-in or ghost profiles are inserted. The insert-only conflict policy
preserves completed, stopped, and reset state, and the activity-window timestamp
prevents retroactive credit for older scans. The created row retains the
existing profile-visible Field trip status, but no scan evidence, media, notes,
or location is exposed by enrollment.

These Seasonal Challenge contracts are deployed and Events are public in iOS.
The client requests and renders challenge catalogs, details, badges, entries,
routes, progress, Insight contributions, and hashtag suggestions for every user.
This client release did not change database authorization, schema, or Function
contracts; the verified Edge and database boundaries remain authoritative.

`get-explore-post` is an important routing helper for the iOS client: it returns
a single privacy-safe feed-card projection so notification taps and deep links
do not depend on the target post already existing in the currently paged
`ExploreFeedViewModel.posts` array.

The public Next.js app uses a separate server-only boundary for
`https://naturebook.earth/explore/post/{postId}`:
`get_public_web_explore_posts(...)` and
`get_public_web_explore_post_detail(...)`. Both wrappers fix the viewer to
`NULL`, expose only the web DTO, and are executable only by `service_role`;
browser `anon` and `authenticated` roles are explicitly denied. Both
independently require the canonical `explore_projected_post_cards(NULL)`
visibility/privacy projection. `get_public_web_explore_post_page(...)` returns
card and detail from one statement/MVCC snapshot, and Next.js uses that combined
routine. The server must not query private Explore, scan, user, taxonomy, or
Auth tables directly. Engagement counts are zero and viewer state is false.
Exact-SHA promotion evidence is tracked in the
[release assurance record](./14-dwca-and-public-web-release-hold-2026-07-27.md).

Explore post common names are post snapshots, not live dictionary labels. The
share and edit functions may write `explore_posts.species_common_name` from the
composer's selected known common name; `update-explore-field-notes` preserves
that snapshot when `species_common_name` is omitted. Read RPCs route through
`public.explore_post_species_common_name(...)` so feed, detail, author, map, and
hashtag views all prefer the stored snapshot and fall back to dictionary English
names or the scientific name only for legacy posts without a snapshot.

Explore post media is also a post-owned snapshot. Sharing copies safe public
image and video URLs from the scan into `explore_post_media` and keeps
`hero_image_url` as the backward-compatible universal thumbnail. Feed, detail,
author, hashtag, map, and Community ID reads include ordered `media_items` JSON.
Feed/detail surfaces may play muted videos conservatively, while maps, widgets,
profile grids, and compact previews stay thumbnail-first. In-app compact
previews may add a play indicator, but Home Screen widgets deliberately render
video posts as clean still thumbnails with no badge or inline playback.
Dictionary galleries and reference-image promotion remain image-only and read
from the eligible scan image URLs rather than public video clips.

Standalone Explore audio uses the same post-owned snapshot contract. After the
audio passes publication moderation, `share-scan-to-explore` and media edits
through `update-explore-field-notes` derive or reuse a deterministic PNG with
the iOS spectrogram parameters (2048-point Hann-windowed FFT, 128 mel bins over
80 Hz–16 kHz), store it beside the durable WAV, and copy the URL into
`explore_post_media.thumbnail_url` plus the matching
`scan_media_assets.thumbnail_url`. Public web feed, detail, and Open Graph
surfaces render that cached asset without downloading or decoding the recording
in each visitor's browser. The service-role-only
`backfill-explore-audio-spectrograms` worker fills older blank WAV thumbnails in
bounded batches. Non-WAV legacy recordings remain playable and use the volume
fallback until a codec-capable media processor is introduced.

For captured-media video scans, the Explore composer, `share-scan-to-explore`,
`update-explore-field-notes`, and Ask the Community request creation all resolve
media from the same asset-first source list, pairing the playback `.mp4` with
its poster thumbnail instead of treating sampled inference frames as standalone
user media. A post row is not considered feed-visible by share state unless it
has at least one saved `explore_post_media` row; this prevents failed media
snapshot writes from surfacing as phantom shared posts in the Insight Share
sheet.

Initial publication additionally uses
`public.publish_scan_to_explore_atomically(...)` after restoration, thumbnail
generation, and moderation complete. The invoker-rights, service-role-only RPC
locks and revalidates the exact owned, resolved non-Human biological scan,
accepts only bounded media URLs from that scan, and performs the post upsert,
media replacement, hashtag replacement, and resolved-community publication in
one transaction. Before invoking it, the shared Edge owner-row validator rejects
explicit non-biological state, missing/unresolved selected taxonomy, Human
aliases, and a Human user override; Ask the Community reuses that validator.
When backward-compatible clients omit `location_sharing`, the RPC resolves
geoprivacy from that locked scan. An insert, constraint, or late
community-publication failure therefore restores the entire previous snapshot;
it cannot leave a newly visible partial post or erase healthy media while
returning failure.

Ask the Community uses the companion
`public.request_community_identification_atomically(...)` boundary after
taxonomy resolution and the same media/moderation preparation. It commits the
post snapshot and hidden `needs_id` request together rather than issuing
separate post, media, and request Data API writes. Reopening starts a clean
consensus generation while preserving withdrawn vote history. A post-write
trigger rechecks `needs_id` at `shared_at`, preventing a concurrent explicit
share from returning success after the Community request wins the scan-lock
race.

Both transaction boundaries intentionally remain `SECURITY INVOKER`. Migration
`20260729044500_grant_atomic_explore_service_privileges.sql` supplies the exact
table operation classes their `service_role` caller needs for scan and request
locks, snapshot replacement, taxon validation, identification withdrawal,
consensus-job cleanup, and the existing invoker-rights location projection
trigger. `EXECUTE` remains revoked from `PUBLIC`, `anon`, and `authenticated`;
those roles receive no new table writes. Do not work around an invoker
`permission denied` by converting either routine to `SECURITY DEFINER`.

The scan finalizer uses that same distinction. Compatibility
`image_storage_urls` may retain sampled frames used for inference and video
posters, so those URLs are not individually required as ready standalone image
rows. Migration `20260729012153_fix_video_scan_canonical_finalization.sql`
projects valid structured `captured_media` visuals when available and otherwise
mirrors the legacy refresher's standalone-image count (`images - videos × 5`)
plus every playback video and standalone audio item. Every projected item must
still match the exact scan owner, media kind, URL, and `ready` status before the
ingestion ledger can become complete. This corrects valid-video rejection
without weakening staged-key promotion, deletion, or missing standalone-image
checks.

Author profile reads are split the same way as feed/detail reads.
`get-explore-author-profile` returns a privacy-scoped profile sheet payload only
when the target author has at least one visible Explore post or visible Field
Trip profile surface for the requester. Aggregates are computed from the
author's non-tombstoned scans, preview posts are filtered to currently visible
Explore posts, and Field trip summaries are pulled from the separate Field trip
tables, including pinned published trips when present. It also returns public
follower/following counts plus the requester-specific `viewer_is_following`
flag. `get-explore-author-posts` returns the full published library projection
with stable `(shared_at, post_id)` cursor pagination. Neither endpoint exposes
raw auth metadata, exact coordinates, private scan IDs for achievements,
qualifying achievement scans, browsable follower/following identities, or active
Field trip scan evidence. Field trip challenge badges can appear as lightweight
profile rewards, but they expose no scan IDs, media, exact location, notes, or
private evidence.

`get-explore-feed` now supports four shipped feed modes through one edge
contract:

- `recent`: the default reverse-chronological feed, backed by
  `public.get_explore_feed(...)` and paginated by `(shared_at, post_id)`
- `following`: a reverse-chronological feed backed by
  `public.get_explore_feed_following(...)`, filtering to followed authors'
  currently visible posts and paginating by `(shared_at, post_id)`
- `trending`: a freshness-biased ranking backed by
  `public.get_explore_feed_trending(...)`, using trailing-30-day like activity
  plus `(shared_at, post_id)` tie-breakers and a
  `(ranking_value, shared_at, post_id)` cursor
- `nearby`: a location-gated feed backed by
  `public.get_explore_feed_nearby(...)`, requiring viewer coordinates, reading
  post-owned public coordinates from `explore_posts.public_latitude` /
  `public_longitude`, filtering non-owned coordinate-bearing posts to the
  selected 1–100-mile radius (50 miles by default), and then sorting the
  resulting posts by recency

Every mode also accepts shared species-category, media-kind, and inclusive
`shared_since` filters. Values are OR-ed within each group and AND-ed across
groups. The dedicated SQL RPCs apply these constraints before mode ordering and
cursor limits; the Edge Function does not thin an already paginated result.

Explore hashtags are normalized public metadata, not parsed captions. Publishing
through `share-scan-to-explore` replaces up to five
`public.explore_post_hashtags` edges for the post with lowercase tag text that
omits the leading `#`. Feed-card projections returned by `get-explore-feed`,
`get-explore-post`, `get-explore-author-posts`, and `get-explore-hashtag-posts`
hydrate `hashtags` with one batched lookup over each returned post page. The
detail RPC includes the same tags directly for `ExplorePostDetailView`.
`get-explore-hashtag-posts` queries `public.get_explore_hashtag_posts(...)` with
the standard visible-post rules and stable `(shared_at, post_id)` pagination for
the iOS tagged-post grid. The `(tag, post_id)` edge index is also the intended
base for future event and BioBlitz submission matching.

`set-user-follow` is the only write path for `public.user_follows`. It validates
no self-follow, no mutual block, a non-shadowbanned target, and a visible
Explore author profile before inserting. Unfollow deletes the row by
`(follower_user_id, followee_user_id)` even when the target profile is no longer
visible. `block-user` removes follow rows in both directions, and
`merge-ghost-profile` reparents ghost follow rows before deleting the ghost
public user.

The map path is intentionally split into two layers.
`public.get_explore_map_posts(...)` is the privacy-safe SQL projection over
`explore_posts`, `scans`, `users`, and `species_dictionary`;
`get-explore-map-points` enriches those rows with ordered media, derives
cross-filtered species-category and media-type counts, applies requested species
and media groups before clustering, and returns either clusters or individual
post rows. Values are OR-matched within a group and the two groups intersect.
Explore now stores the author-selected post geoprivacy on
`explore_posts.location_sharing` and projects post-owned public map fields when
that value is `open`. `obscured` and `private` posts can still be visible on
non-map Explore surfaces when otherwise eligible, but the map does not return
them. Protected-species and coordinate-uncertainty rules can still downgrade an
`open` post to rounded public coordinates with
`coordinate_visibility = 'obscured'`. The Nearby feed uses the same stored
post-owned public coordinates for spatial matching, so non-owned `obscured` and
`private` posts do not appear through Nearby even though they can appear in
Recent, Following, Trending, profile, hashtag, and detail reads.

Explore activity now supports optional remote APNs delivery on top of the in-app
feed. The app registers APNs device tokens through `register-push-device`,
stores them in `public.user_push_devices`, and a Postgres trigger on
`public.explore_post_notifications` uses `pg_net` to invoke
`send-push-notification` whenever a visible post-backed notification row is
inserted or a like/comment-reaction aggregate count increases. Follow
notifications are postless, informational, and intentionally skipped by the push
trigger. Field trip activity rows are stored in
`field_trip_activity_notifications`, which has no push trigger. Seasonal
challenge participation and entries also stay out of push, widgets, maps, and
Explore feed rows. Delivery fanout is bounded with
`mapWithConcurrencyLimit(devices, 8,
...)` so one notification row cannot launch
unbounded APNs requests and device state writes from a single V8 isolate. The
individual APNs request has a 10-second hard deadline and reads provider
diagnostics through a 4 KiB ceiling. `apns-collapse-id` is the durable
notification UUID, so a retry of the same notification is collapsed by APNs
instead of being presented twice. The device-token table checks a 32...512
character length separately from its hex-only regex. A `{32,512}` PostgreSQL
regex bound is invalid because the engine caps repetition bounds at 255;
migration `20260720174209_fix_push_device_token_constraint.sql` corrects the
original constraint without weakening token validation. The combined 32...512
regex in `register-push-device/index.ts` is still valid JavaScript and remains
the Edge Function request-boundary check. This repair changes only the database
and does not require a function redeployment. A healthy deployment has both
`user_push_devices_device_token_format_check` and
`user_push_devices_device_token_length_check` present and validated.

## The Webhook Node (`revenuecat-webhook`)

The `revenuecat-webhook` function drives tier updates (`pro` ↔ `free`) without
moving existing scan media between R2 prefixes. Both `public_uploads/free/` and
`public_uploads/pro/` are durable scan-media storage, so RevenueCat events only
update `users.subscription_tier` and `users.subscription_expires_at` through a
single service-only RPC. The database trigger atomically advances
`users.entitlement_version`; the next quota reservation observes the new version
from durable state regardless of which Edge isolate handles it.

Ingress is dual authenticated. `timingSafeCompare()` verifies the configured
Bearer credential, and `signature.ts` verifies RevenueCat's
`X-RevenueCat-Webhook-Signature` HMAC-SHA256 over the exact
`<timestamp>.<raw-body>` before parsing. A five-minute replay window rejects
captured deliveries. Missing signing configuration returns `503`; there is no
legacy unsigned fallback.

The event payload is not entitlement authority. After validating its durable
`id`, `event_timestamp_ms`, and customer identity fields, the handler fetches
the latest RevenueCat CustomerInfo with a secret server API key beginning with
`sk_`. A committed event with the same timestamp, type, and payload digest found
through the service-only duplicate lookup is the sole exception; it returns
without another provider request, limiting at-least-once/replay amplification.
Active `pro` or `Naturalist Tier` entitlements produce Pro through the later of
their recurring expiration or grace-period expiration; that timestamp is
persisted so access can expire without another webhook. `NULL` is reserved for
an explicitly non-expiring lifetime entitlement. An authoritative `pro_week`
non-subscription transaction produces a timed seven-day grant. Refund/revocation
events exclude the matching pass transaction. CustomerInfo timeouts, rate
limits, invalid responses, missing public user rows, and identity groups that
map to multiple live users fail closed without a tier write.

`public.apply_revenuecat_identity_state(...)` then performs the event insert,
principal/user locks, ordering comparison, separated StoreKit/account-grant
projection, and durable watermark update in one transaction. `TRANSFER` events
use `transferred_from` and `transferred_to` instead of `app_user_id`; the
handler fetches both customers before calling the RPC, and the RPC locks stable
principals before affected UUIDs in sorted order. During the expand/migrate
window, the previous bundle's exact
`public.apply_revenuecat_customer_state(...)` and
`public.schedule_revenuecat_reconciliation(...)` signatures remain only as
compatibility adapters. They delegate legacy UUID subjects into the identity
ledger and scheduler. The adapters and stable completion first take one shared
cutover advisory lock, then lock related principals before users and recheck
under lock, so even a previously unrelated rebind destination cannot race a
legacy write. `internal.revenuecat_webhook_events.event_id` is the unique
idempotency key, while the legacy and principal subject ledgers record zero to
two results. Authoritative CustomerInfo snapshot time orders state first;
webhook event time and event ID break only exact snapshot ties. Duplicate or
older deliveries remain auditable but cannot overwrite newer access, and a
transfer cannot partially commit. The internal tables have RLS enabled and no
direct grants; the `SECURITY DEFINER SET search_path = ''` mutation, adapter,
resolver, and duplicate-lookup RPCs call `internal.require_service_role()` and
are allowlisted only to `service_role`.

Migration `20260725052338_reconcile_revenuecat_subscribers.sql` adds a durable
authoritative repair queue. Migration
`20260726031502_scale_revenuecat_reconciliation.sql` makes the 15-minute worker
drain repeated six-customer `SKIP LOCKED` waves until empty or its 60-second
start-work cutoff, while provider concurrency remains three. It also indexes
expired claimed rows. A snapshot applies only when newer than the user's
transactional watermark. Pro users are revisited every six hours and free users
every 24 hours. Webhook handling also advances affected subjects' due times.
Historical seven-day purchases are not newly granted by background
reconciliation, so a refund cannot be resurrected from CustomerInfo history.
Migration `20260809055035_canonicalize_revenuecat_app_user_ids.sql` aligns the
queue and ghost-merge repair with iOS's uppercase, case-sensitive App User ID.
It resets claims only for lookups proven to be the same UUID and leaves
provider-supplied aliases untouched.

The service-only `get_revenuecat_reconciliation_health()` RPC returns due count,
expired-claim count, and oldest due age. A separate GitHub monitor checks it
every 15 minutes, alerts after 30 minutes or on any expired lease, and marks 60
minutes critical.

The scheduled `expire-subscription-passes` worker remains a fail-safe whenever
any timed recurring, grace-period, or pass grant reaches
`subscription_expires_at`. Existing scan media remains in place on every
transition.

RevenueCat customer identity is linked by the iOS client before purchase
evaluation: `SupabaseManager.linkExternalTelemetry(user:)` configures the SDK
directly with the uppercase Supabase Auth UUID on first use and switches known
accounts with `logIn`, without an anonymous configuration or SDK logout. It sets
subscriber attributes such as `supabase_user_id`, `auth_email`,
`public_username`, `public_author_name`, `public_identity_source`, and
`account_kind`. Manual RevenueCat Test Store support work should search by the
Supabase UUID first, then by those attributes.

Before saving `image_storage_urls` to PostgreSQL, the function strips AWS
signature query string parameters from the URL to prevent Cloudflare R2
`403 Forbidden` errors when the object key changes. R2 access uses
`getR2Config()` from `_shared/aws.ts`.

## The Scientific Export Pipeline (`request-export-dwca` & `export-dwca`)

This pipeline is installed but authoritatively disabled for the initial launch.
Release iOS hides the control; the private PostgreSQL singleton defaults off;
the first BEFORE INSERT trigger rejects old/direct intake; continuation cron is
absent; grants are revoked; and durable archive cleanup remains active. A valid
authenticated request returns `403 feature_unavailable`, a valid worker request
returns `200`/`disabled`, and a capability returns no-store `410`. The behavior
below applies after the separate feature-enable evidence gate.

The client-facing `/request-export-dwca` route requires a permanent account and
accepts only `exportScope: "personal"`. Global exports are intentionally
internal-only because they consume a shared repository-wide budget. Direct Data
API insertion is revoked. An atomic service-only request RPC takes a per-user
transaction advisory lock and combines release state, the rolling 24-hour
window, and insertion; the partial unique index remains a final duplicate fence.

The queue row is canonical and immutable. PostgreSQL webhooks and the
minute-level resume cron send either an opaque `job_id` or an empty body; they
never send trusted user, scope, precision, or cursor values. The service-only
worker performs an exact bearer comparison and claims each phase with a fresh
UUID token and short lease. An explicit insertion webhook attempts only its own
ID once, bounding intake fan-out. Empty-body cron dispatches read five-job
oldest-due waves from the durable queue.

Migration `20260725052339_bound_dwca_export_work.sql` persists the phase, keyset
cursors, cumulative row and CSV byte counts, chunk sequence, retry state, and
ordered R2 chunk manifest. Canonical defaults allow at most 5,000 CSV rows and
an 8 MiB final archive. Database constraints impose absolute ceilings of 20,000
rows and 16 MiB, and callers cannot mutate either budget after insert.
Deleted-account tombstones are excluded by matching partial indexes.

Ordered migrations `20260725175312_bound_dwca_export_source_bytes.sql` and
`20260725180321_validate_dwca_export_source_bounds.sql` close the remaining
pre-encoding allocation gap. The first transaction installs new-write checks
without scanning legacy rows; the second validates those rows before activating
the read RPC. Validated checks bound image URL arrays to 24 elements of 4,096
UTF-8 bytes, ecological interaction arrays to 10 elements of 2,048 bytes, and
selected taxonomy text to finite lengths. Those validated write-time limits
remain prerequisites for every snapshot page.

Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`
upgrades source snapshots to version 2. Scope evaluation, membership, and both
phase DTOs are materialized by one MVCC statement at job creation. Private
`internal.export_job_source_rows` stores the immutable occurrence and multimedia
JSON plus exact byte counts; confirmed species identity is used when present,
with the original AI identity retained only as scan history. Total source JSON
is capped at four times the immutable archive budget and never above 64 MiB.
Each phase DTO is independently capped at 256 KiB. Exact GPS keys are omitted
from global rows and from personal rows that did not opt into precise
coordinates; protected personal rows omit them even when precision was
requested.

The repaired materializer counts only bounded UUID membership first, then uses a
parameterized lateral cursor to project, measure, and insert one DTO at a time.
It stops at the first per-row or cumulative byte violation and removes partial
rows, so the aggregate source ceiling also bounds JSON DTO memory and
temporary-sort amplification during rejection.

The page RPC reads those immutable DTOs rather than querying live scan/taxonomy
state. A later scan or ordinary edit therefore cannot enter, alter, or
needlessly fail the export. Page reads retain their compact post-cursor hash
check, while a full-member predicate verifies version, count, durable
invalidation state, current eligibility, and every creation-time hash before
assembly, staging, email, and completion. Relevant scan and taxonomy changes
durably invalidate affected nonterminal jobs. Personal geoprivacy changes are
irrelevant because that scope contains only the requesting owner's rows; both
scopes revalidate protected-species coordinate redaction.

A mismatch becomes terminal `source_snapshot_changed`, revokes any application
capability, and durably enqueues the uploaded/staged object for deletion.
Processing jobs keep the opaque application URL in private work state; the
owner-visible URL and completed status are published atomically after the final
full fence. Failed status purges DTOs immediately; completed DTOs remain only
until grant cleanup succeeds. Existing nonterminal jobs are fenced, discard
prior manifests, and restart from occurrence against one version-2 snapshot.
`get_dwca_export_scan_batch(...)` remains executable only by `service_role`,
verifies the active claim token and exact durable cursor, and returns no more
than 100 rows or 256 KiB of serialized source. Exact-SHA verification is in the
[release assurance record](./14-dwca-and-public-web-release-hold-2026-07-27.md).

Each claimed step remains independently bounded:

1. `occurrence` or `multimedia` reads one monotonic row-and-byte-aware keyset
   page from shared immutable DTO rows after the page live-eligibility fence,
   incrementally RFC-4180 encodes into a fixed buffer of at most 512 KiB, writes
   one temporary R2 CSV chunk, and transactionally commits its object key,
   cursor, cumulative budgets, byte count, and CRC-32.
2. `assembling` reads the manifest in order and lazily streams the CSV chunks
   through the ZIP32 writer into a bounded R2 multipart upload after a
   full-member fence. Staging repeats that fence transactionally.
3. `delivering` resolves the canonical owner's Auth email, calls Resend with
   `Idempotency-Key: dwca-export/{job_id}`, and completes the job. Full-member
   checks run before and after email lookup; completion repeats the fence.

Migration `20260728035237_harden_dwca_downloads_and_scan_finalization.sql`
removes long-lived direct storage authority from delivery. The worker creates a
32-byte random application capability, stages its SHA-256 index with the
attempt-fenced archive, and emails `/functions/v1/download-dwca?token=...`. Scan
and protected-species policy triggers invalidate every affected unpurged
snapshot without trusting a concurrently changing job status, revoke any
already-present grant, and enqueue the current archive. Every click is also
distributed-rate-limited and reruns the complete source-membership predicate
against current deletion, ownership, taxonomy, protection, and privacy state.
Authorization returns only a no-store, read-only R2 redirect valid for at most
30 seconds.

Expired, revoked, terminal, staging-race, deleted-job, and legacy direct-URL
archives enter `internal.export_archive_cleanup_jobs`.
`reconcile-dwca-archive-cleanup` claims oldest-due rows with UUID leases every
five minutes, treats R2 `404` as success, and durably backs off other storage
failures. Its service-only health summary reports aggregate backlog, oldest-due
age, and expired leases. Completion is fenced to the job's exact current attempt
key, so stale cleanup cannot revoke a replacement grant or purge active source
state. Successful exact-current terminal cleanup purges retained source DTOs.
Deterministic Resend 4xx responses are terminal; ambiguous, rate-limited,
server, network, storage, and database failures remain retryable.

The independent five-minute GitHub export-health workflow reads both
`get_dwca_export_queue_health()` and `get_dwca_archive_cleanup_health()`. It
therefore alerts on stuck physical deletion even when the database worker cron
or its Vault configuration is absent and no worker log can be emitted. If either
aggregate cannot be read, the workflow writes a critical summary with queue
values unavailable and a stable monitor code; it never substitutes zero counts.
`catalog_contract_missing` identifies a missing/stale zero-argument PostgREST
routine contract, while other read and response-shape failures remain separate
stable categories.

Migration `20260726230837_scale_dwca_export_continuations.sql` changes only
dispatcher throughput and observability, not step ownership. One synchronous
invocation processes those steps sequentially until a 40-second soft start
cutoff or a 40-step hard ceiling. After each successful advance,
`next_step_at = NOW()` places that job behind older due work; a failed or
contended ID is suppressed for the remainder of the invocation to prevent a
tight retry loop. This turns the existing phase table into a fair durable queue
without concurrently assembling several archives in one Edge isolate.

The same migration adds the service-only aggregate
`get_dwca_export_queue_health()` RPC and an outstanding-job partial index. Every
dispatch logs backlog depth, due count, live/expired claim count, and oldest-due
age. A separate five-minute GitHub workflow reads this aggregate and the
archive-cleanup aggregate, then alerts on age, backlog, or expired leases.

Temporary CSV keys include the active claim token as well as phase and sequence.
A lease-expired worker that resumes after its replacement can therefore neither
overwrite the winner's chunk nor commit an unexpected key to the manifest. Final
archive keys are claim-fenced too. A durably staged archive is reused after
lease recovery rather than regenerated.

The CSV encoder appends one row at a time without page-wide line arrays,
concurrent row expansion, or a final string join. It computes CRC-32 only for
the current bounded 512 KiB-or-smaller chunk. Assembly combines the ordered
durable chunk CRCs with GF(2) composition, making checksum work proportional to
chunk count rather than archive bytes; it also verifies the streamed byte count
for each ZIP entry. Multipart parts are fixed at 8 MiB, and source pages, chunk
responses, and parts are released as they flow. No invocation retains the
complete result set, CSV, or ZIP. R2 XML and Resend responses are byte-capped,
every outbound request has a deadline, failed multipart uploads are aborted
where possible, and S3-compatible `<Error>` documents returned under HTTP 200
are rejected.

Resource limits are an operational input rather than an entitlement to perform
more work. The current
[Supabase Edge Function limits](https://supabase.com/docs/guides/functions/limits)
must be rechecked before changing the 100-row, 256 KiB source, 512 KiB CSV, 8
MiB multipart, 40-step, or archive ceilings. A release must exercise a
maximum-shape export in the hosted environment and inspect function metrics and
546/`CPU Time exceeded` logs; local checksum timing alone cannot establish
production headroom.

Personal exports retain the owner's UUID and can include the owner's precise
coordinates. A reviewed internal global job uses a stable, versioned,
domain-separated HMAC-SHA256 pseudonym from `DWCA_PSEUDONYM_HMAC_KEY_V{n}`;
there is no JWT-secret reuse or literal fallback. Protected taxa still receive
only their public coordinate projection.

## The Edge Moderation Node (`block-user`)

User blocking routes through a dedicated Edge Function to bypass RLS policies
that operate on anonymous IDFV boundaries:

1. iOS validates the active Supabase JWT via `SupabaseManager` and attaches it
   to the request. A missing session throws a `NetworkError` before any API call
   is made.
2. The `{"blocked_id": "..."}` payload is sent via the REST API. The Edge
   Function validates the body with `requireParams(body, ["blocked_id"])` from
   `_shared/http.ts`, returning `HTTP 400` if the field is absent. `blocked_id`
   is additionally validated as a well-formed UUID — a non-UUID string is
   rejected with `HTTP 400` before any database access. A self-block attempt
   (`blocked_id === user.id`) is also rejected with
   `HTTP 400 "Bad Request: You cannot block yourself."`.
3. `supabaseAdmin.from('user_blocks').upsert()` runs with the service role key,
   using `onConflict: "blocker_id,blocked_id"` and `ignoreDuplicates: true`.
   This makes repeated block requests fully idempotent — a second block by the
   same user returns `200 OK` without inserting a duplicate row or throwing a
   unique-constraint error.

## Security & Environment Validation

- The `GEMINI_PAID_API_KEY` is absent from the iOS client bundle (`Info.plist`
  and `.xcconfig`). All LLM calls go through Supabase Edge Functions
  (`identify`, `identify-multimodal`, `enrich-scan`, `insight-chat`, etc.),
  which hold the key server-side.
- Every Edge Function declares `verify_jwt` explicitly in `config.toml`.
  Anonymous Supabase sessions carry user JWTs, and the gateway supports both
  legacy HS256 and asymmetric signing-key JWTs. User-JWT-only routes should
  retain the gateway check; `merge-ghost-profile` therefore uses
  `verify_jwt = true` for both its anonymous prepare phase and permanent-account
  completion phase. `withEdgeHandler` additionally resolves the live Auth user,
  and both transaction RPCs bind authority again with `auth.uid()`. Routes with
  `verify_jwt = false` must have a documented replacement boundary: an
  in-handler `requireAuth`/claims policy, a timing-safe service credential,
  webhook signature verification, or an intentionally public read contract.
  `/identify-multimodal` and `/update-scan-context` use cached ES256 JWKS claims
  verification; other authenticated routes retain their documented `getUser`
  verification. Current intentional cases include:
  - **`request-export-dwca`**: Keeps `verify_jwt = true` because personal data
    exports require a verified authenticated user identity — anonymous users
    have no stable identity to bind an export to.
  - **`species-dictionary`**: Keeps `verify_jwt = false` but intentionally skips
    `requireAuth` because it returns only public species-level dictionary data.
  - **`species-observation-stats`**: Keeps `verify_jwt = false` but returns only
    public species-level iNaturalist aggregates and cache metadata. Its
    replacement boundary is canonical dictionary binding, optional live-user
    verification, daily HMAC IP identity, atomic request/cold-population limits,
    and a fenced database lease. Local Merian observation data is not sent to
    this endpoint.
  - **Internal service-role workers**: Keep `verify_jwt = false` so `pg_net`,
    GitHub Actions, or another trusted server caller can reach the Deno runtime,
    then enforce an exact platform-managed service credential inside Deno with
    `timingSafeCompare`. Boundaries using `_shared/serviceRoleAuth.ts` compare
    against the CI/local `SUPABASE_SERVER_API_KEY`, deploy-synchronized
    `MERIAN_SUPABASE_SERVER_API_KEY`, named `sb_secret_...` values in
    `SUPABASE_SECRET_KEYS`, the singular `SUPABASE_SECRET_KEY` local/manual
    fallback, and the migration-only `SUPABASE_SERVICE_ROLE_KEY` fallback; they
    do not use table reachability or an RLS result as proof. A legacy JWT key
    may be sent as Bearer (normally with the same `apikey`); a current non-JWT
    secret key must be sent only as `apikey`. Conflicting credentials fail
    closed, and accepted request values are never reused as downstream database
    credentials. This internal category includes species refresh,
    reference-image refresh, taxonomy import/status/refresh, consensus
    processing, non-biological purge, `backfill-explore-audio-spectrograms`, and
    `reconcile-ghost-profile-merges` workers.
- **Rule for new Edge Functions**: Every new function directory under
  `services/supabase/functions/` MUST have a corresponding `[functions.<name>]`
  entry in `config.toml` before deployment. Use `verify_jwt = true` for routes
  reached only with user JWTs, including anonymous-user JWTs. Use
  `verify_jwt = false` for deliberately public routes, `pg_net` workers that
  perform their own service-role secret check, webhooks, or a reviewed custom
  verification path. Public unauthenticated routes must document their
  data-exposure boundary in both the function README and
  `docs/backend-and-data/05-api-contracts.md`; internal cron workers must
  document their service-role authorization boundary. Dependency validation and
  the planner test require exact parity between configured function names and
  discoverable entrypoint graphs. Fleet size is derived from those sets; there
  is no numeric count to update when a reviewed route is added.

## Database Indexing & Performance

`00003_performance_indexes.sql` creates the following pipeline-compatible
indexes:

- `idx_species_dict_scientific_name` on `species_dictionary (scientific_name)` —
  species lookup during inference.
- `idx_scans_user_id` on `scans (user_id)` — user streak queries.
- `idx_scans_discovery_feed` on
  `scans (geoprivacy, is_live_capture, timestamp DESC)` — global discovery feed
  fetches.
- `idx_scans_user_species` on `scans (user_id, species_id)` — supports the
  one-time species-ledger backfill, reconciliation diagnostics, and ordinary
  user/species lookup.
- `internal.user_species_scan_counts` primary key on `(user_id, species_id)` —
  serializes one exact owner/species counter and makes existence the distinct
  species unit.
- `user_species_scan_counts_species_idx` on
  `internal.user_species_scan_counts (species_id, user_id)` — supports the
  deferred dictionary foreign-key check after scan `ON DELETE SET NULL`
  transitions.
- `idx_scans_lifecycle` on `scans (timestamp) WHERE image_storage_urls != '{}'`
  — supports media-present scans queries used by public/feed/reference-image
  projections. Additional migration-specific indexes:

- `idx_scans_nonbio_lifecycle` on
  `scans (timestamp) WHERE is_biological_subject = false` — scopes the
  non-biological cleanup worker.
- `idx_species_observation_stats_cache_expires_at` on
  `species_observation_stats_cache (expires_at)` — supports stale/fresh cache
  sweeps and operational inspection for public observation chart payloads.

`20260324000000_add_historical_sync_index.sql` adds:

- `idx_scans_user_id_timestamp` on `scans (user_id, timestamp DESC)` — compound
  index added to accelerate paginated historical sync queries issued by
  `syncHistoricalScansDown`. Without this index, a query of the form
  `WHERE user_id = $1 ORDER BY timestamp DESC LIMIT n OFFSET m` hits the
  single-column `idx_scans_user_id`, fetches all rows for that user, then sorts
  them by `timestamp` in a second pass — O(n log n) per page, O(n² log n) total
  for large libraries. With the compound index, Postgres can satisfy both the
  filter and the `ORDER BY` in a single index-only scan, making each page
  O(page_size) regardless of library size.

All migration-owned index DDL intentionally omits `CONCURRENTLY`. Supabase CLI
`2.109.1` owns migration transaction and history boundaries; new migrations omit
top-level transaction controls so those boundaries cannot be split. Top-level
timeout guards use session `SET` plus matching `RESET`, not `SET LOCAL`, so they
remain effective during fresh replay. The static migration contracts cover the
full migration directory, including dynamic concurrent DDL, transaction aliases,
replay-safe timeout handling, and schema-qualified `SUBSTRING` calls that
incorrectly use the unqualified SQL keyword forms. Qualified calls use ordinary
comma-separated arguments. Zero-downtime index creation on a populated
production table is an explicit, supervised pre-deploy operation. A size-gated
migration may converge with an ordinary index only after it verifies a reusable
index or a relation small enough for the bounded inline path. See the canonical
[migration execution and index contract](./13-server-credentials-and-database-release-safety.md#migration-execution-contract).

## Storage Economics & Evidence Retention

Cloudflare R2 stores biological media bytes. Supabase Postgres stores the
relational scan/post/media rows and URLs that reference those objects. A
surviving URL is not a byte-level backup and must not be treated as proof that
an object remains available.

Biological scan media is intended to be durable regardless of subscription tier.
Migration `20260616130000_disable_free_tier_media_expiration.sql` retired the
earlier free-tier media expiration policy and the targeted domesticated-media
purge. Successful biological sightings keep their image evidence unless the user
deletes the scan, moderation removes the media, or an operator performs an
explicit support action.

**`get-filtered-discovery-feed`**: Applies
`.not("image_storage_urls", "eq", "{}")` to exclude rows with cleared media from
public feeds. It also joins `users!inner(is_shadowbanned)` with
`.eq("users.is_shadowbanned", false)` to exclude shadowbanned content
server-side, since the service role key bypasses RLS. The query uses an explicit
column list rather than `select("*")`, omitting telemetry and analytics columns
(`device_locale`, `current_month`, `time_of_day`, `depth_scale_text`, `llm_*`
token counts, `extracted_visual_traits`, `ai_reasoning`, etc.) that the client
never renders. This reduces per-row payload size by approximately 60% at scale.

**Graceful Degradation**: Scans whose media is missing because of user deletion,
moderation, historical cleanup, or transient CDN failure render the archived
visual placeholder rather than looping on a `ProgressView`. “Archived” is a
presentation fallback, not an R2 archive class and not proof that the object can
be restored from Cloudflare.

### Automated 30-Day Non-Biological Purge

The `auto-purge-nonbio` Edge Function, triggered by `pg_cron` via `pg_net`,
selects non-biological scans for durable erasure after 30 days. A standard
Cloudflare R2 Object Lifecycle rule cannot be used because R2 lifecycle rules
operate on object age and prefix, not on the canonical PostgreSQL
`is_biological_subject = false` flag. The route drains bounded calls to
`request_nonbiological_scan_retention_deletions(integer)`. That routine
discovers candidates oldest first, acquires canonical scan-generation locks in
UUID order, rechecks age, classification, `is_tombstoned = false`,
non-null/non-reserved ownership, and generation-tombstone absence under each row
lock, and commits the permanent deletion fence. Ownerless, reserved-owner, and
rows already tombstoned by account deletion remain exclusively owned by the
account-deletion pipeline. The route never captures media URLs, deletes R2
objects, or deletes scan rows.

The independent `reconcile-scan-deletions` reaper subsequently reloads each
fenced row and performs idempotent external erasure. It accepts only the exact
owner's flat `public_uploads/{free|pro}/{owner}/...` objects; `avatars/`,
`staging/`, `quarantine/`, `exports/`, foreign-owner keys, and malformed URLs
are ineligible. A failed R2 delete compare-before-releases its lease for retry,
and the database row is removed only after media erasure succeeds. This closes
the former race in which a finalizer could append a media URL after retention
selection but before an inline purge deleted the row.

The iOS app mirrors this retention boundary locally.
`ScanRepository.purgeExpiredNonBiologicalScans(modelContainer:)` is invoked on
foreground and when `NonBiologicalScansView` opens. It delegates to
`BackgroundDatabaseActor.purgeExpiredNonBiologicalScans(cutoffDate:)`, which
fetches a bounded batch of expired local non-biological records, deletes rows,
queues `PendingCloudDeletionTask` tombstones, commits SwiftData first, and only
then returns local media paths for `FileIOActor` cleanup.

Explore audio moderation attestations are database metadata, not R2 media.
Deleting a scan or its audio removes the media object and public references but
does not currently delete the global checksum decision, because the row has no
user, URL, post, or scan identity and may protect against repeated submission of
identical bytes. Operators may prune obsolete model/policy generations; old
generations are never reused after the derived policy hash or model changes.

## Token Cost Analytics (`services/supabase/analytics/`)

`services/supabase/analytics/` contains version-controlled SQL queries for LLM
cost observability. These are the authoritative source for API spend analysis —
PostHog owns behavioral metrics (funnel, session, conversion, prompt/action
taps, answer categories, refusals, and feedback submissions); Supabase SQL owns
cost metrics. Scan token counts are persisted to `public.scans`; Insight chat
assistant token counts are persisted to `public.insight_chat_messages`, while
private answer ratings and sheet-level feedback are stored in
`public.insight_chat_message_feedback` and
`public.insight_chat_feature_feedback`.

Run these in **Supabase → SQL Editor → Save** to pin them as named queries:

| File                              | Purpose                                                                                                                                                                                                                                            |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `token_cost_summary.sql`          | Estimated scan inference spend by tier for any date window. Applies current Gemini pricing constants (Flash: $0.30/M input, $0.03/M cached, $2.50/M output; Pro: $1.25/M input, $10/M output) against actual stored token counts.                  |
| `insight_chat_cost_summary.sql`   | Estimated Gemini 2.5 Flash spend for Pro Insight chat assistant replies, using token telemetry persisted on `insight_chat_messages`.                                                                                                               |
| `cache_effectiveness.sql`         | Daily Flash implicit cache hit rate and savings in cents. A hit is any scan where `llm_cached_tokens > 0`. Only meaningful for Flash scans after the system instruction exceeded the 2,048-token caching threshold.                                |
| `thinking_token_distribution.sql` | P50/P90/P95/max thinking token usage by tier, plus `pct_at_budget_ceiling` — the percentage of scans where thinking usage approached the configured budget (2,048 Flash / 5,000 Pro). A high ceiling-hit rate signals the budget should be raised. |
| `daily_cost_trend.sql`            | Per-day API spend by tier for the last 30 days. Use to spot cost anomalies from traffic surges or pricing changes.                                                                                                                                 |
| `token_averages_by_week.sql`      | Weekly averages for all token fields plus cache hit rate. Shows step-changes after system instruction deployments and validates financial model assumptions.                                                                                       |

**Pricing note**: Gemini pricing changes frequently. The constants in these
queries should be audited quarterly against the current Google AI pricing page
and reconciled with actual PostHog `ScanCompleted.llm_cached_tokens` totals.

### Cloudflare R2 Object Lifecycle Rules

The following Object Lifecycle Rules must be configured in the Cloudflare R2
Dashboard under **Settings -> Object Lifecycle** and mirrored in
`docs/r2-lifecycle.json`:

1. **Default Multipart Abort Rule**
   - **Prefix:** `--`
   - **Action:** Abort incomplete multipart uploads after `7` days
2. **Purge staging objects after 1 day**
   - **Prefix:** `staging/`
   - **Action:** Delete objects after `1` day
3. **Purge quarantine objects after 1 day**
   - **Prefix:** `quarantine/`
   - **Action:** Delete objects after `1` day
4. **Purge export objects after 1 day**
   - **Prefix:** `exports/`
   - **Action:** Delete objects after `1` day

Do not add an expiration lifecycle rule for `public_uploads/free/`,
`public_uploads/pro/`, or `avatars/`. Scan images and user profile pictures are
durable public media; deletions occur only through an authorized application
workflow. Deno tests load `docs/r2-lifecycle.json` and reject avatar expiration;
the deployment runbook additionally requires an operator check for all three
durable prefixes.

## Internal Review, Feedback, and Admin Boundary

Users can flag incorrect taxonomy results from `InsightSheetView`:

- **`flag-issue`**: Accepts authenticated POST requests with `scanId`,
  `flagReason`, and `userSuggestion`. Validates `scanId` as a well-formed UUID —
  a non-UUID string is rejected with `HTTP 400` before any database access.
  Validates `flagReason` against the enum
  `["Incorrect species", "Inappropriate content", "Bad image quality", "Other"]`
  — values outside this set are also rejected with `HTTP 400`. Evaluates a
  preemptive DB boundary check, securely hooking into PostgreSQL foreign-key
  constraint violations (`23503`) implicitly converting missing offline
  references into a clean `HTTP 404` rejection stream to properly shield
  downstream logs from transient offline sync race-condition 500 alerts.
- **`flagged_reviews` table** (`00005_flagged_reviews.sql`): Stores
  identification review requests tied to the reviewing `user_id`, defaulting to
  `PENDING_REVIEW`. Explore post-content reports do not use this table.
- **`scans` table update**: Sets `is_flagged = true` and writes review context
  to `human_intervention_notes` when an identification is flagged for review.
  After the internal-admin migration, `is_flagged` is recomputed from whether a
  grouped identification case remains `open` or `in_review`.
- **`explore_post_reports` table**: Stores native Explore post-content reports
  submitted through `/report-explore-post`, without changing `scans.is_flagged`.
- **`explore_comment_reports` table**: Stores comment abuse intake separately
  from post and identification reports.
- **`user_reports` table**: Stores authenticated non-self visible-profile
  reports submitted through `/report-user`. Reporting does not block the target.
- **Duplicate lifecycle**: One row is retained per post and reporter. Repeat
  reports refresh context without resetting a moderator's `DISMISSED` or
  `ACTIONED` status to `PENDING_REVIEW`.
- **Public web boundary**: Anonymous web visitors report by support email with
  the immutable post id; the public web route does not write this queue.

Migration `20260719161112_add_internal_admin_foundation.sql` attaches all four
intake families to one private `internal.review_cases` model. A case is unique
by type/subject, retains immutable source links and append-only notes, supports
assignment/priority/status/resolution, and reopens terminal state only when a
new independent reporter arrives. Reversible post/comment hide/restore is a
separate audited action and never resolves the case automatically.

`apps/admin` is the only product UI for raw queues. It authenticates through
Google OAuth cookies plus TOTP AAL2 and calls narrow `SECURITY DEFINER` RPCs. It
has no service-role key or direct table grants. Analysts receive only
aggregates; moderators and owners may access raw review/feedback/user context;
owners additionally manage memberships, sessions, and audit history. The private
`internal` schema is not a Data API schema and remains inaccessible to browser
roles.

The one-time beta product survey uses a separate feedback path rather than the
moderation queue:

- **`submit-feedback-survey`**: Accepts authenticated survey responses for the
  active `beta_feedback_2026_06` campaign, validates ratings/enums/text caps,
  and stores the response under the JWT user id.
- **`feedback_survey_responses` table**: Stores private product feedback with
  app/build/device context, ratings, selected answers, free text, and
  `created_at`. RLS allows users to insert/read only their own rows.

The admin feedback inbox unifies community feedback, surveys, Field
message-level feedback, and Field feature feedback. Original submissions stay
immutable; private `feedback_state` and append-only `admin_notes` provide
workflow state, assignment, tags, and history.

See [`10-internal-admin.md`](./10-internal-admin.md) for the complete database
and authorization contract and
[`11-internal-admin-operations.md`](./11-internal-admin-operations.md) for
deployment and incident response.

## Account Deletion & Data Preservation (`safe-delete`)

Account deletions use the `apply_user_tombstone` PL/pgSQL function (introduced
by `00006_apply_user_tombstone.sql` and hardened by later forward migrations).
Instead of cascade-deleting retained observations, migration
`20260725041308_ownerless_account_deletion_tombstones.sql` makes those scans
ownerless (`user_id = NULL`) and sets `is_tombstoned = true`. Migration
`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`
installs the current mandatory retention boundary: it clears media, private
free-form notes, custom tags, semantic/public location labels, and device
context, while leaving exact coordinates, elevation, observation time, taxonomy,
identification, environmental, quality, and provenance facts unchanged. A
validated check constraint permits an ownerless scan only when it is tombstoned,
and the anonymous table-read policy explicitly excludes tombstones.

The normative retained-versus-cleared field boundary and its change procedure
are defined in the
[scientific-observation retention contract](./17-scientific-observation-retention.md).

`20260725035737_repair_tombstone_profile_seed.sql` is a no-op compatibility
bridge for production run 1461. The attempted public-only all-zero profile could
not satisfy production's canonical `public.users.id → auth.users.id` foreign
key. The forward migration preserves that relationship with
`ON DELETE RESTRICT`, ensuring an Auth-first delete is rejected until verified
relational cleanup removes the profile, and never creates a synthetic Auth or
public user.

The internal-admin foundation extends this deletion boundary to the append-only
AI ledger. When the `public.users` row is deleted, a protected trigger clears
the matching event's user, scan, conversation, message, source, and identifying
metadata linkage. Token totals, operation/model classifications, and estimated
cost remain available for anonymous aggregate analysis; the ledger cannot be
updated or deleted through ordinary service-role writes.

**Operation order**: Migration `20260725030308_durable_account_deletion.sql`
adds durable deletion intake, and migration
`20260725052337_enforce_account_storage_erasure.sql` completes the private
`pending → storage_pending → auth_pending → completed` state machine. Migration
`20260726041109_fence_storage_erasure_claims.sql` makes that private job the
mandatory authority for every R2 claim. Migration
`20260806203700_durable_apple_provider_revocation.sql` adds a provider substage
inside `auth_pending`; a stored Apple refresh token must be revoked and removed
from Vault before Auth deletion. `/safe-delete` first persists an idempotent
`pending` receipt, then claims it with a five-minute UUID lease. The claim
writes the storage job, invokes `apply_user_tombstone`, verifies that no public
profile or scan still references the user, and commits `storage_pending` in one
database transaction. The Auth Admin API remains forbidden until storage
verification advances the account job to `auth_pending`. This ordering
guarantees that any relational, R2, or provider failure leaves the login
identity available for retry instead of stranding personal data behind an
inaccessible account.

The authenticated `register-apple-revocation-token` route captures Apple's
one-use authorization code after Supabase sign-in, verifies both Apple identity
tokens and their common subject, binds that subject to `auth.identities`, and
stores the refresh token in Vault through one service-only transaction. A
token-free registration receipt makes response-loss retry idempotent. If Vault
persistence fails after exchange, the route attempts immediate compensating
revocation and iOS clears the newly installed local session.

The SQL storage claim inner-joins the corresponding private job at
`storage_pending`, requires completed relational cleanup and incomplete storage,
and rejects the target while a matching `public.users` row or owned
`public.scans` row exists. Historical outbox rows may survive an interrupted old
workflow; queue status, age, due time, or a reset marker alone can never
authorize an account-prefix sweep.

Relational cleanup also clears every compatibility media URL, captured-media
reference, semantic/public-location value, device locale/time-zone context,
free-form note, and custom tag retained on ownerless scientific tombstones while
retaining exact coordinate/elevation and every other scientific fact. Every
claimed retry repeats cleanup and verification before progressing. After storage
verification, the worker calls Apple's idempotent `/auth/revoke` under the
active database claim and destroys the Vault secret transactionally before Auth
becomes reachable. Legacy Apple identities without captured credentials carry an
explicit manual-fallback disposition in the deletion response. A private
deletion-state trigger rejects attempts to recreate `public.users` while a job
is active, including Auth metadata-triggered upserts. The upload signer checks
the same durable state and rejects new staging/public uploads while deletion is
active.

The handler passes only the user ID returned by its verified session. The
database routines are granted only to `service_role`, call
`internal.require_service_role()`, use an empty `search_path`, and expose no
direct job-table privileges to API roles.

**Retry and crash handling**: The request tries its own job immediately and
normally returns `202` while durable R2 work remains. Both success responses
include `manual_provider_revocation_required`. A `200` means relational cleanup,
delayed storage verification, provider disposition, and Auth removal are all
complete. An older binary that does not decode this required field cannot
deliver the manual fallback; publishing the supporting build is not proof that
installed clients adopted it. Production remains blocked until a
minimum-supported-build control or independent server-delivered fallback covers
those clients. The scheduled `reconcile-account-deletions` route leases due
account jobs and storage jobs every five minutes. Each storage claim processes
at most one 50-key keyset page from one of the five canonical user prefixes.
Progress and failures are persisted under a UUID claim token with bounded
backoff.

After the first sweep reaches the end of all prefixes, the job waits at least 25
hours and starts a complete verification sweep. Only an empty delayed pass marks
storage complete and wakes the account job transactionally. A final bounded
account pass may then revoke Apple and remove Auth in the same invocation.
Cleanup, storage, or provider failure never reaches Auth deletion; Auth failure
leaves the fully-erased job at `auth_pending` with bounded backoff. HTTP `404`
and Auth code `user_not_found` are idempotent success, so a lost completion
response is recoverable. Expired claim tokens cannot clear or finish a newer
attempt.

The terminal transition re-verifies cleanup, storage, provider resolution, and
credential absence; records Auth deletion; clears the claim; and sets the
private job's `user_id` to `NULL`. The completed storage receipt remains
available for the terminal gate and operations audit.

**`logStructuredError` alerting requirement**:
`logStructuredError(event, details)` from `_shared/edgeHandler.ts` emits
`JSON.stringify({ ...details, event, ts })` to `console.error`. These structured
logs must be connected to a log drain (Logflare or Datadog) with alerts on
`account_deletion_attempt_deferred`, `account_deletion_reconciliation_deferred`,
and `account_storage_erasure_deferred`.

Migration `20260727001630_monitor_account_deletion_health.sql` supplies the
independent stuck-job boundary: partial indexes support oldest-active,
oldest-due, retry-error, and expired-lease aggregation, and service-only
`get_account_deletion_health()` reports those metrics plus phase/backlog counts,
orphaned storage work, cron activity, and credential readiness. The result
contains no user identifier or raw error. The five-minute
`account-deletion-health-monitor.yml` GitHub schedule is offset from the
database reaper and resolves its server API key through the Management API, not
the reaper's Vault configuration. It therefore reports missing Vault values or a
disabled cron as critical instead of failing with the worker. Default
warning/critical thresholds are 10/30 minutes due age, 27/36 hours end to end,
and 25/100 active jobs. Remediation is to repair the failing cron,
cleanup/R2/Apple/Auth dependency, or credential configuration and let the
claim-fenced job resume—never to delete Auth manually.

The full Apple credential, secret, rotation, fallback, and rollout requirements
are normative in the
[Sign in with Apple account-deletion contract](./20-sign-in-with-apple-account-deletion.md).

Configuration readiness mirrors the worker's exact Vault-first, NULL-only
fallback: a present but blank Vault value is unhealthy and cannot be masked by
the legacy app setting. The boolean proves only that the effective URL and key
are nonblank. Migration `20260727013416_future_proof_server_key_boundaries.sql`
applies one private header builder to installed `pg_net` routines and persisted
cron commands. Opaque `sb_secret_...` values are sent only in `apikey`; legacy
service-role JWTs are sent in both `apikey` and Bearer Authorization. The Edge
route compares either format against its platform-managed environment set.

On `200 OK` or durable `202 Accepted`, the iOS client performs local Supabase
sign-out for the current device, tears down the local SQLite database via
`ScanRepository.shared.purgeAllData()`, and clears all cached image files from
disk. Ordinary in-app sign-out also uses local scope so another simulator or
device session is not revoked.

## Scan Erasure & The Deletion Pipeline (`delete-scan`)

Individual scan deletion severs the record from both Supabase and Cloudflare R2:

1. **Auth**: JWT is extracted and verified manually. Deletion is locked to the
   scan's `user_id`.
2. **Durable Generation Fence**: The service-only
   `request_scan_deletion(scan_id, user_id)` routine locks the scan generation,
   verifies exact ownership, inserts a private deletion tombstone, and
   terminal-marks any noncomplete ingestion job. From that commit onward,
   inserts, updates, provider completion, replay, and owner-row recovery for the
   UUID fail closed.
3. **Owner-bound R2 Deletion**: The function reads canonical source and derived
   media only after the fence. A candidate is deletable only when it is an exact
   HTTPS URL on `media.merian.app` with the flat key
   `public_uploads/{free|pro}/{verified-owner-uuid}/{safe-filename}`. Foreign
   owners, nested/dot paths, query strings, fragments, credentials, staging,
   avatars, and malformed names are rejected before signing. Accepted URLs are
   rewritten to the private R2 API and issued as signed `DELETE` requests via
   `AwsClient` from `aws4fetch`. Every accepted object must return 2xx or
   idempotent 404.
4. **Database Erasure**: `complete_scan_deletion(scan_id, user_id)` rechecks the
   private owner tombstone, removes the scan row, and records completion. The
   tombstone remains indefinitely because the UUID is a deleted generation, not
   a reusable identity.
5. **Independent Completion**: The authenticated request is only the fast path.
   `reconcile-scan-deletions` leases oldest-due pending tombstones every five
   minutes, drains at most 100 with bounded concurrency and a runtime deadline,
   and compare-before-releases failures with exponential backoff. Completion
   clears the owner UUID while retaining the content-free scan-generation fence.
6. **Gamification Projection**: The statement-level scan-delete trigger
   subtracts the deleted rows from `internal.user_species_scan_counts`. If a
   `(user_id, species_id)` row reaches zero, the ledger row is removed and
   `users.total_species_discovered` decreases by one without going below zero. A
   multi-row delete aggregates each affected pair once.

If R2 or database completion fails, the scan row and durable tombstone remain
for both the iOS `PendingCloudDeletionTask` and the independent server reaper to
retry. Database lookup failures are never translated into idempotent not-found
success. The GitHub-backed Scan Media Health Monitor reads
`get_scan_deletion_health()` every 30 minutes and reports aggregate backlog,
oldest-pending age, and expired leases independently of database cron/Vault
dispatch.

Authenticated API roles cannot insert/delete scans or mutate owner, media,
privacy, or inference columns. Current clients write tags and identification
review through fixed-search-path SECURITY DEFINER routines that derive the owner
from `auth.uid()`. A narrow five-column UPDATE grant is retained only as a
rolling-compatibility bridge for already-installed clients; remove it after the
minimum supported iOS release uses the RPCs. Database cardinality and
element-byte constraints bound every still/video/audio URL array, custom tags,
and identification override before any service-role fetch or deletion path.
Migration `20260728151927_declare_scan_data_api_privileges.sql` reconstructs
this ACL explicitly for new and existing Supabase privilege modes: `anon` and
`authenticated` receive RLS-governed reads, `service_role` receives canonical
CRUD, `PUBLIC` receives nothing, and no API role receives
truncate/reference/trigger/maintain authority.

#### V8 Execution Abstractions

- **Deploy-Stable Runtime Imports**: Production deploys rely on a generated
  `deno.json` inside each function directory, which is the config Supabase
  discovers while creating that function graph. The root
  `services/supabase/functions/deno.json` owns reviewed exact pins; generated
  configs copy those aliases and point at the shared frozen `dependencies.lock`.
  Production code imports aliases rather than direct URL, npm, or JSR
  specifiers. New entrypoints call `Deno.serve(...)` directly, and runtime
  base64/hex work uses `_shared/encoding.ts`.
- **`_shared` Utilities**: The `http.ts`, `edgeHandler.ts`, `biology.ts`,
  `external.ts`, `aiQuota.ts`, `entitlement.ts`, `posthog.ts`, `gemini.ts`,
  `aws.ts`, `encoding.ts`, `auth.ts`, and opt-in `claimsAuth.ts` domains cleanly
  separate the core proxy engine natively without polluting the specific Webhook
  routers. All routes resolve the same exact Supabase SDK through generated
  function-local configs and the shared frozen lock. `claimsAuth.ts` stays
  outside `edgeHandler.ts` so unrelated functions retain their established
  `getUser` authentication semantics.

## The Enrichment Node (`enrich-scan`)

Two reliability improvements were made to `enrich-scan`:

**`resolveLookalikesToJoinTable` return type (`enrich-scan/db.ts`)**: The
function now returns `{ lookalikes: LookalikeSummary[]; persisted: boolean }`
(exported as `ResolveResult`) instead of a bare `LookalikeSummary[]`.
`persisted` is `true` only when rows were successfully written to the
`species_lookalikes` join table. Early-exit paths (null kingdom, empty
dictionary match, all-failed kingdom validation) set `persisted: false`. Both
call sites in `enrich-scan/index.ts` destructure `{ lookalikes, persisted }`.

**`lookalikes_flash_attempted` flag gating**: The flag is now set only when
`persisted === true`. Previously the flag was written even when
`resolveLookalikesToJoinTable` returned without writing any rows (e.g., the
null-kingdom early-exit). This permanently locked out future Flash retries for
species whose enrichment was skipped due to replication lag, causing
`similar_species` to never appear. Setting the flag only on a confirmed
join-table write ensures that skipped enrichment paths can be retried on the
next call.

**Singleflight In-Flight Deduplication**: Two module-level maps
(`_enrichmentInFlight`, `_lookalikesInFlight`) prevent thundering herd on
popular species at launch. When multiple concurrent requests target the same
species and scope, late arrivals await the in-flight Promise rather than firing
redundant Gemini calls. Once the first request completes its DB write,
piggybacking requests re-read `species_dictionary`, which will be a cache hit.
This protects against the scenario where hundreds of users simultaneously scan
the same common species and all hit a cache miss within the same ~300–500 ms
Gemini round-trip window.

Each in-flight map stores a `Promise<void>` backed by an explicit
**resolve+reject pair**:
`let resolveFn!: () => void; let rejectFn!: (e: Error) => void`. The leader
calls `resolveFn()` immediately before the success `return jsonResponse(...)`,
and `rejectFn(e)` in the `catch` block. Late-arriving waiters use
`try { await inFlightPromise } catch { /* fall through */ }` — on resolve they
re-read `species_dictionary` and return the cached result; on reject they fall
through and retry the Gemini call themselves. This ensures a failed leader (e.g.
Gemini timeout) does not permanently block waiters in a resolved-but-stale
Promise.

## Collections Sync (`sync-collections`)

The `sync-collections` function receives the full client-side collection state
and applies a diff-based delta against the server. Key bounds and IDOR guards:

- **`MAX_COLLECTIONS = 200`**: Rejects payloads with more than 200 collections
  in a single sync request — prevents V8 heap exhaustion from unbounded upsert
  batches.
- **`MAX_SCAN_IDS_PER_COLLECTION = 5000`**: Each individual collection's
  `scan_ids` array is capped at 5000 entries. A single collection with an
  unbounded `scan_ids` array would create a massive PostgREST `.in()` validation
  query and large membership delta writes. Values over this limit are rejected
  with `HTTP 400` before any DB access.
- **Atomic ownership admission**: service-only
  `upsert_owned_collections(p_user_id, p_collections)` performs the ownership
  decision inside the same `INSERT ... ON CONFLICT ... DO UPDATE` statement as
  the write. New IDs and same-owner IDs are accepted; foreign or concurrently
  colliding IDs are rejected without modifying their rows. Only accepted IDs
  continue to membership hydration and delta calculation. An RPC error throws
  and performs no downstream membership work.
- **`collection_scans` membership delta**: Only the diff (rows to add minus rows
  to remove) is written — the function does not delete and re-insert all
  memberships on each sync. This prevents unnecessary DB churn on large
  collections. Additions use `insert_owned_collection_scans(p_user_id, p_rows)`,
  which joins both parent records to the owner. Missing or foreign scans are
  skipped for eventual offline ordering. Membership reads, inserts, and deletes
  throw on database error rather than swallowing it via `console.error`; the
  controller propagates a `500` so iOS retries rather than confirming a partial
  result.
- **`collection_scans` membership hydration**: Existing memberships for all
  owned incoming collections are fetched through one keyset-paginated
  `.in("collection_id", ownedIds)` query ordered by `(collection_id, scan_id)`.
  Each bounded page resumes strictly after the last composite primary key; no
  progressively slower `.range(...)`/OFFSET walk is used. This avoids the
  previous N+1 latency stack while preventing the theoretical maximum (200
  collections × 5000 scan IDs = 1M rows) from loading into one isolate
  allocation. The existing `PRIMARY KEY (collection_id, scan_id)` supports the
  cursor order.
- **Database enforcement**: an invoker trigger rejects memberships whose
  collection and scan owners differ, including direct service access.
  Authenticated RLS permits own-collection select/delete and requires both an
  own collection and own scan for insert. `service_role` cannot update
  collection ownership directly and has UPDATE only on `name` and `created_at`;
  Ghost merge reparenting remains behind its reviewed privileged function.

## Species Preferred Name Sync

`user_species_preferences` is synced directly by the iOS client through Supabase
PostgREST rather than through an Edge Function. RLS scopes every row to
`auth.uid()`, and the table is keyed by `(user_id, scientific_name)`.

- Active preferences upsert `preferred_common_name` with `deleted_at = NULL`.
- Clears upsert a tombstone (`preferred_common_name = NULL`, `deleted_at = now`)
  so another device can distinguish a deliberate clear from a species that never
  had a preference.
- `SpeciesPreferredNameRepository` reconciles all local SwiftData
  `UserSpeciesPreference` rows plus pending local delete timestamps against the
  remote table on auth restore, foreground activation, and after local edits.
- iOS keeps this reconciliation single-flight inside the `@MainActor`
  repository: duplicate lifecycle/auth/edit triggers await the active sync task
  rather than issuing overlapping remote reads and upserts. If a trigger arrives
  while a sync is running, the repository stores a trailing follow-up request
  and reruns reconciliation until no follow-up remains, so local edits made
  after the active task's local fetch are not left for a later lifecycle event.
  `SpeciesPreferredNameStore.syncDiagnostics` persists last
  attempt/success/status/message and last pushed/pulled counts in `UserDefaults`
  for supportability; these keys are diagnostic only and do not participate in
  conflict resolution.
- Conflict resolution is timestamp based: newer remote active rows update
  SwiftData, newer remote tombstones delete the local row, newer local rows push
  back to Supabase, and pending local clears remain queued until their tombstone
  upsert succeeds.
- A matching normalized active value is already converged even when local and
  remote timestamps differ, and two tombstones are already converged as well.
  The repository clears stale legacy/pending markers without rewriting the
  matching remote row. For a real active-value conflict, the newer timestamp
  wins; local-newer or equal values push, while remote-newer values replace the
  SwiftData row. This avoids two devices repeatedly echoing the same value.

## Privileged Database RPC Boundary

`public` is listed in `services/supabase/config.toml` because PostgREST must
discover application tables and RPCs. Discovery does not grant execution.
Migration `20260723144640_harden_privileged_routine_execution.sql` removes
`PUBLIC`, `anon`, `authenticated`, and `service_role` from every public
`SECURITY DEFINER` function, then grants only the exact reviewed signatures in
`internal.privileged_routine_grants`.

Direct clients therefore have no anonymous privileged RPC surface. Authenticated
execution is limited to RPCs that bind authority inside the database to
`auth.uid()`/`auth.jwt()` or the internal admin authorization helper.
Service-key Edge calls are limited to reviewed worker/maintenance signatures,
and every service-exposed function calls `internal.require_service_role()` even
if an ACL is later broadened by mistake. Internal helpers such as follow
reparenting and database-wide Explore-media refresh receive no Data API role
grant.

Migration `20260727010340_fix_service_role_authorization_guard.sql` keeps the
in-function service check compatible with both supported server-key paths. A
legacy service-role JWT is visible to `auth.role()`. An opaque secret key is not
a JWT; PostgREST instead impersonates `service_role`, which the helper reads
from the protected standard `role` setting. Direct `postgres` or `service_role`
database sessions remain available for migrations and incident repair. The RPC
grant and the in-function check are independent defenses: fixing key-format
compatibility does not broaden the allowlist, and a caller-controlled header or
custom GUC is never an authority source.

Every public definer has `search_path = ''`; application relations, custom
types, and extension operators are schema-qualified. PostgreSQL function
defaults for the `postgres` migration owner are also owner-only, both globally
and in `public`, so a newly created function does not silently inherit API
execution. Static migration tests, a disposable-catalog pgTAP test, and
pre/post-production read-only audits reject drift before Edge deployment.

## Explore Author Identity Maintenance

Explore reads never mutate author identity or post ownership. Feed, author,
comment, notification, map, mention, hashtag, species, and post-detail functions
read the existing public projection only. This keeps read latency predictable
and prevents a popular profile or feed page from creating database writes.

Current `users.public_username` rows and historical mention snapshots have
different temporal contracts. Migration
`20260808144244_expand_reserved_public_username_policy.sql` repairs newly
reserved current handles with neutral deterministic aliases and revalidates the
profile CHECK. It leaves `explore_comment_mentions.mention_username` unchanged
so each snapshot still matches its plain-text `@token`; taps route by
`mentioned_user_id`. Edge and iOS mirror the reserved groups for early feedback,
but PostgreSQL remains authoritative and usernames carry no authorization.

`syncPublicAuthorIdentity(...)` remains the shared Edge helper for public write
paths. It is called when sharing a scan, creating Explore or Field trip
comments, requesting Community identification, and merging a ghost profile. Auth
metadata triggers also refresh the projection at the database boundary. Ghost
merge transfers scan and Explore post ownership before refreshing the target
identity, so the new account owns every denormalized row before the ghost is
purged.

Scan Library quick-share and the full Insight composer both use
`/share-scan-to-explore`, whose first maintenance write is this service-only
author refresh. A logged `service_role authorization required` failure at that
point indicates a server migration/key-path mismatch, not that the signed-in
user lacks permission to share the scan. The compatibility migration must be
present in the target database; no client service key or iOS rebuild is part of
the fix.

Migration `20260720042641_optimize_explore_author_maintenance.sql` defines both
maintenance RPCs as `SECURITY DEFINER SET search_path = ''`, fully qualifies
their relations, revokes execution from `PUBLIC`, `anon`, and `authenticated`,
and grants it only to `service_role`. `refresh_public_author_identity(uuid)`
uses `IS DISTINCT FROM` guards and does not update a converged row;
`repair_explore_post_ownership_for_user(uuid)` updates only rows whose scan
owner matches the requested target. Neither function is a client API.

## Ghost Account Merge (`merge-ghost-profile`)

Normal Apple/Google linking preserves the anonymous UUID and does not call this
merge path. The endpoint exists for the conflict case where the selected
provider identity already belongs to another permanent account.

Only the exact Supabase Auth error `identity_already_exists` enters the merge
fallback. Network errors, timeouts, disabled manual linking, and every other
link failure leave the guest session unchanged and are surfaced to the caller.

The live anonymous source first calls `operation = prepare` with the OAuth
provider and exact token subject. The server generates a 256-bit secret, stores
only its SHA-256 hash, and binds the handoff to `auth.uid()`, that provider
identity, and a 30-day expiry. iOS persists the secret in a versioned,
device-only Keychain queue with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
before switching sessions. Multiple interrupted upgrades cannot overwrite one
another, and the older single-record format is decoded and migrated in place.

After provider sign-in, the permanent destination calls `operation = complete`.
`public.consume_ghost_profile_merge_handoff(...)`:

1. derives the destination exclusively from `auth.uid()`;
2. locks the handoff and source/destination Auth and public-user rows;
3. proves the source is still anonymous and the destination owns the exact
   provider subject selected by the source;
4. verifies every eligible user foreign key has an explicit source-controlled
   merge policy before the first mutating helper runs;
5. resolves known uniqueness conflicts, executes only reviewed ownership moves,
   preserves customized guest identity, and deletes the Ghost public row in one
   transaction;
6. moves scans first so their statement trigger owns species-ledger deltas, then
   checks the exact ledger against scans for both users;
7. fails closed on missing/stale/blocked policy, unsupported composite topology,
   immutable source attribution, or a source reference left behind; and
8. records an idempotent merge receipt.

The private `internal.ghost_profile_merge_reference_policies` manifest separates
referential integrity from merge semantics. Catalog inspection verifies complete
coverage and resolves only reviewed relations; it no longer treats every newly
discovered foreign key as transferable ownership. Audit, administrator, session,
and moderator attribution is preserved rather than rewritten. Explicit handlers
coalesce Community Identify activity actors and normalize RevenueCat state
before conflict-prone references move. Any migration that changes eligible
user-FK topology must update the manifest in the same forward change.

### Release-blocking concurrency and repair invariants

The schema-aware migration establishes the policy manifest, scan-first ordering,
and fail-closed ledger check. The existing-account conflict fallback remains on
release hold until a forward migration and the Edge Function also satisfy all of
these invariants:

- Every operation that can touch merge-sensitive RevenueCat state locks the
  corresponding `public.users` row before the reconciliation queue row. The
  merge already holds the source/destination users before child state, so
  `public.apply_revenuecat_reconciliation(...)` must use the same user-first
  order and revalidate its lease after acquiring the queue lock. A lost lease
  fails closed without applying stale entitlement state.
- Completion unconditionally inserts or updates the destination's
  `internal.revenuecat_reconciliation_queue` row, sets
  `lookup_app_user_id =
  internal.canonical_revenuecat_app_user_id(target_user_id)`,
  makes it due immediately, and clears attempt, claim, and error state. This
  repair cannot depend on a source queue row: anonymous sources may have none,
  and the queue is the durable recovery path for a completely missed provider
  webhook.
- The Community activity handler coalesces only groups that already contain both
  a source and destination actor. It updates the destination collision and
  deletes the redundant source collision; non-colliding source rows remain for
  the reviewed generic reparent pass. It must not insert destination actor rows
  while holding actor locks, because normal activity writers lock the activity
  group before its actor and the inverse order can deadlock.
- Both `ghost_merge_species_ledger_mismatch` and
  `user_species_scan_count_underflow` map to HTTP 503
  `merge_temporarily_unavailable` with the signed-out-profile-data-unchanged
  message. The transaction has already rolled back in either case; exposing an
  unexpected 500 would give the client the wrong operational classification.

The exact proof required to clear this hold is in the
[Ghost Account Merge Security Rollout](./06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).

Only after that database transaction commits does the Edge Function delete the
anonymous Auth user. Failed Auth cleanup returns a retryable response; repeating
the same completion returns the durable receipt and safely retries deletion. The
client removes a proof only after success or terminal
`handoff_expired`/`handoff_invalid`; wrong-destination and transient responses
remain queued.

The service-role-only `reconcile-ghost-profile-merges` worker runs every five
minutes. It marks expired prepared rows, claims pending cleanup receipts with
`FOR UPDATE SKIP LOCKED` plus a ten-minute lease, calls the Auth Admin delete
API, and records the outcome using the claim token. This closes the cleanup gap
when the foreground request or client never returns. The legacy
`public.reparent_user_follows(...)` helper is no longer client executable.

## Required and Optional Edge Function Secrets

For a production deployment, the following required secrets and documented
optional controls are set in the Supabase Edge secret store via the CLI
(`supabase secrets set KEY=VALUE`):

- Supabase automatically provides **`SUPABASE_URL`**, the legacy
  **`SUPABASE_ANON_KEY`** and server-only **`SUPABASE_SERVICE_ROLE_KEY`**, plus
  JSON dictionaries **`SUPABASE_PUBLISHABLE_KEYS`** and
  **`SUPABASE_SECRET_KEYS`** containing the project's named current keys. Do not
  manually overwrite these built-ins. `_shared/publishableKey.ts` resolves the
  public project key for user-scoped clients; `_shared/serviceRoleAuth.ts`
  independently resolves and exactly matches server-only keys. Neither boundary
  accepts the other key class. **`SUPABASE_SECRET_KEY`** is an optional singular
  current-key fallback for local/manual Deno environments; it is not a
  replacement for the hosted plural dictionary.
- **`MERIAN_SUPABASE_SERVER_API_KEY`**: Non-reserved hosted fallback containing
  the exact active project server key selected from the reveal-explicit
  Management API response. The production deploy workflow masks and refreshes it
  before Function deployment; it is not a separate GitHub secret. It closes
  runtime provisioning lag without changing the standard `apikey`/legacy Bearer
  request protocol. A project-key rotation must pass the production deploy
  during overlap before the old key is revoked.
- **`GEMINI_PAID_API_KEY`**: Required for all `gemini-2.5-flash` and
  `gemini-2.5-pro` model inferences. It must come from the approved
  billing-enabled Google Cloud project; deployment validates and synchronizes
  it, and runtime code has no alternate secret fallback.
- **`AI_QUOTA_IP_HASH_SECRET`** (optional override): At least 32 high-entropy
  characters used to HMAC the proxy-observed client address for daily-rotating
  IP rate-limit buckets. When absent, Edge code uses a built-in server-only
  Supabase secret/service-role key with a quota-specific HMAC domain. The
  production workflow validates and synchronizes the override only when it is
  configured; an explicitly weak override fails closed.
- The same **`GEMINI_PAID_API_KEY`** also authenticates the dedicated
  `gemini-2.5-flash` speech/non-speech classifier used by the fail-closed
  Explore audio publication gate. A valid content-addressed attestation can be
  reused while Gemini is unavailable; cache misses remain rejected when this
  secret is absent.
- **`POSTHOG_API_KEY`**: Authenticates server-side ingestion into PostHog.
- **`R2_ACCOUNT_ID` / `R2_BUCKET_NAME`**: Select the exact Cloudflare account
  and production media bucket.
- **`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`**: Grants existing promotion and
  reviewed deletion workers their required bucket access. Do not use these
  values in clients or Cloudflare event consumers.
- **`R2_READ_ACCESS_KEY_ID` / `R2_READ_SECRET_ACCESS_KEY`**: Required
  bucket-scoped Object Read credentials used by `reconcile-explore-media-health`
  for direct signed origin `HEAD`. The worker does not fall back to existing
  promotion/deletion credentials; audit that this token cannot write or delete.
- **`R2_EVENT_WEBHOOK_SECRET`** (optional): At least 32 high-entropy characters
  shared only with the trusted Cloudflare Queue consumer. It accelerates checks
  and is not object-state authority; when absent, event ingress fails closed
  while scheduled reconciliation remains correct.
- **`REVENUECAT_WEBHOOK_SECRET`**: At least 32 random characters used for the
  RevenueCat webhook's configured Authorization header. Constant-time comparison
  is the first ingress check.
- **`REVENUECAT_WEBHOOK_SIGNING_SECRET`**: RevenueCat-generated HMAC signing
  secret used to authenticate the exact raw body and enforce the five-minute
  replay window. There is no unsigned production mode.
- **`REVENUECAT_SECRET_API_KEY`**: Secret server API key used only by
  `revenuecat-webhook` to fetch authoritative CustomerInfo. It must begin with
  `sk_`, is distinct from the public iOS `REVENUECAT_API_KEY`, and must never
  ship in a client.
- **`RESEND_API_KEY`**: The API Key from Resend for sending transactional emails
  (like DwC-A exports).
- **`RESEND_FROM_EMAIL`**: The verified sender identity
  `Naturebook Data Exports <exports@naturebook.earth>`. If absent, it falls back
  to Resend's testing domain `onboarding@resend.dev` which will FAIL unless
  sending to the developer's registered account.
- **`DWCA_PSEUDONYM_HMAC_KEY_V1`**: Required Base64-encoded key that decodes to
  at least 32 random bytes. It is used only for version-1 global-export
  pseudonyms, is validated/synchronized from the GitHub `Production`
  environment, and must never reuse a JWT, service-role, or provider secret.

## 2026-04 Hardening Updates

- Edge telemetry parsing is now centralized through
  `_shared/identify/context.ts`, which keeps month normalization and enum
  clamping identical across image, describe, multimodal, and audio endpoints.
- Audio preprocessing is now shared via `_shared/audioProcessing.ts`, removing
  the old dual-maintenance WAV pipeline between `/audio-spec` and
  `/identify-multimodal`.
- Media body budgets and staged/inline payload resolution are shared through
  `_shared/mediaBudgets.ts` and `_shared/identify/media.ts`. `/identify`,
  `/identify-multimodal`, and `/audio-spec` must reject oversized media JSON
  `Content-Length` headers before body parsing and must not locally duplicate R2
  key, base64, or audio-buffer validation.
- The discovery-feed JS fallback remains strictly secondary to the Postgres RPC
  path and now bounds over-fetch using the current block-list size instead of a
  fixed always-extra query window.
