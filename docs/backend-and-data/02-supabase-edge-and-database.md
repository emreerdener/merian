# Supabase Edge and PostgreSQL Engine

Merian uses Supabase as its backend platform. API keys are kept in `.xcconfig`
files and never bundled into the client binary. All LLM and database operations
execute server-side in Deno Edge Functions.

## Core Schema Structure

`00001_initial_schema.sql` defines the base backend schema.
`00002_user_auth_trigger.sql` handles the auth relationship. All anonymous users
are identified by a persistent Keychain-backed
`UIDevice.current.identifierForVendor` IDFV.

- **`species_dictionary`**: Stores every tracked taxon with its scientific and
  biological descriptors.
- **`scans`**: Records GPS bounds, the LLM-generated `ai_confidence_score`,
  `inference_tier`, UUID references, and the `ecology_type_enum` for each scan,
  tied to the user's streak.
- **`users`**: Binds the IDFV (or authenticated UUID) to the product schema,
  tracking usage limits and subscription tier.
- **`unified_species_count_sync`
  (`20260320132111_unified_species_count_trigger.sql`)**: A unified, idempotent
  Postgres `AFTER INSERT OR UPDATE OR DELETE ON public.scans` trigger that
  recalculates `total_species_discovered` in the `users` table via
  `SELECT COUNT(DISTINCT species_id)`. This replaces the previously split
  trigger files and eliminates TOCTOU schema drift on moderation updates.

## Shared Edge Utilities (`_shared/`)

Several utilities are shared across all Edge Functions via
`services/supabase/functions/_shared/`:

- **`http.ts`**: The unified networking primitive module. Defines `corsHeaders`,
  export tools for `jsonResponse(payload, status)`, strict POST payload
  `requireParams(body, fields)`, and cryptographic `timingSafeCompare(a, b)` for
  secret validation (used heavily by `pg_net` cron workers).
- **`edgeHandler.ts`**: Wraps endpoints natively using `withEdgeHandler()`,
  automatically intercepting CORS `OPTIONS` preflights and Deno SDK JWT
  extraction layers, eliminating boilerplate. Exposes `runBackground(task)` via
  standard `EdgeRuntime.waitUntil`. Also exports
  `logStructuredError(event, details)`, which emits
  `JSON.stringify({ event, ts, ...details })` to `console.error` — all functions
  must use this for alertable operational failures rather than plain
  `console.error` calls.
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
  parallel with occurrence imagery behind a shared `AbortSignal.timeout(2500)`
  guard. The result is normalised to Title Case, deduplicated, and filtered to
  English-only entries before being returned as
  `alternativeCommonNames: string[]`. This array is written to
  `species_dictionary.alternative_common_names` during the Cache Miss enrichment
  pass and served back to the iOS client as `alternative_common_names` on Cache
  Hit.
- **`gemini.ts`**: Contains the physical module-level `_genAI` client wrapper
  initialization and the `extractJson<T>(text)` AST parser string evaluation.
- **`posthog.ts`**: A headless telemetry ingestion pipeline executing
  asynchronous `node-fetch` style queries to log per-scan events to PostHog for
  behavioral analytics (conversion funnel, scan frequency, species discovery
  rate). LLM token cost analytics are NOT owned by PostHog — they are owned by
  Supabase SQL queries in `services/supabase/analytics/` (see below), which query the
  `scans` table directly as the authoritative source.
- **`tierCache.ts`**: Worker-level `_tierCache` Map storing subscription tiers
  with a 5-minute TTL to eliminate DB round-trips on warm isolate reuse.
  **Bounded at 1000 entries**: on overflow, expired entries are swept first
  (pass 1); if the map is still ≥ 75% full after the sweep, the oldest 25% of
  remaining entries are evicted (pass 2). All writes go through `_cacheSet()` —
  both `getTierForUser` and `setTierCache` use this helper. Exported functions:
  `getTierForUser(userId, supabaseAdmin)`, `hasTierCached(userId)` (used by the
  `identify` background task to detect ghost users),
  `setTierCache(userId, tier)` (called after ghost-user upsert and by
  `revenuecat-webhook` after tier change).
- **`aws.ts`**: Exports native `S3/R2` Cloudflare mappings utilizing
  `aws4fetch`. Exposes array batch tools (`deleteR2Objects`, `copyR2Object`)
  used for purging storage footprints. `generatePresignedPutUrl` accepts an
  explicit Content-Type so image and audio staging uploads can be signed with
  the same header the iOS background upload task will send.
- **`mediaBudgets.ts`**: Centralizes Edge media limits and reusable validation
  helpers for endpoint JSON body byte ceilings, image count/raw bytes, inline
  audio base64 length, raw audio bytes, audio clip count, staged R2 key
  ownership, path traversal, and `Content-Length` prechecks. `identify`,
  `identify-multimodal`, `audio-spec`, and `generate-upload-urls` must import
  these helpers rather than redefining byte limits locally.
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
- **`auth.ts`**: The baremetal JWT parser extracting anonymous and authenticated
  keys natively across the `Authorization` header map.

## The R2 Upload URL Node (`generate-upload-urls`)

The `/generate-upload-urls` Edge Function signs direct-to-Cloudflare R2 `PUT`
URLs for background staging. Current clients send a structured `files` manifest
built by `MediaStagingContract` rather than a loose filename array: each entry
includes `fileName`, `mediaKind`, `contentType`, and `sizeBytes`. The Edge
parser rejects unsanitized names, media-kind/content-type mismatches,
over-budget audio or image files, batches above five files, and batches above
two audio files before calling `generatePresignedPutUrl()`. Legacy `fileNames`
remains accepted for older clients only; it is compatibility-only because it
cannot express byte budgets. The limit and content-type contract is pinned in
`docs/contracts/media-staging-upload-manifest.json` and loaded by both Swift and
Deno tests.

## The Edge Inference Node (`identify`)

The `/identify` Edge Function acts as the inference proxy:

1. **Auth**: Receives a structured payload from iOS. The `Authorization` header
   JWT is verified via `requireAuth` inside `withEdgeHandler`. Merian uses
   anonymous ES256 sessions (`signInAnonymously`), so the default Supabase
   `verify_jwt` Edge Middleware is disabled in `services/supabase/config.toml`
   (`verify_jwt = false`). Auth is handled manually via the Supabase SDK.
2. **Direct Base64 Transfer**: If the iOS client sends `imageBase64s`, the Edge
   Function validates the request `Content-Length` and aggregate base64
   character budget before passing the strings as Gemini `inlineData`. It does
   not decode inline images into a second full buffer on the Edge path.
3. **Legacy AWS Fallback (`_shared/aws.ts`)**: If inline images are absent
   (e.g., during background `URLSession` uploads where the image was already
   staged to R2), the function falls back to fetching from R2 through
   `_shared/identify/media.ts`. Responses are processed serially: each response
   body is consumed via `arrayBuffer()` and the running `totalBytes` counter is
   incremented by `arrayBuffer.byteLength` (the actual byte count after body
   consumption). If the accumulated total exceeds 5 MB, the function immediately
   returns HTTP 413. The `Content-Length` header is used as a per-image
   pre-check to reject oversized images _before_ allocating the ArrayBuffer, but
   is not the authoritative guard — chunked transfer encoding makes this header
   absent on some R2 responses, so the post-allocation cumulative byte count
   (`totalBytes`) remains the enforced limit and is always checked after body
   consumption regardless of whether the header was present.
4. **Google Gemini Model Selection**: Pro users use `gemini-2.5-pro` for maximum
   identification depth (rare species, fossils, subspecies). Free users use
   `gemini-2.5-flash` for 2–3× lower latency. The model is chosen immediately
   after the tier SELECT — before the Gemini call — so both tiers receive the
   correct model. Generation uses `temperature: 0.1` for rigid JSON output. The
   schema explicitly instructs Gemini to extract Data-as-a-Service (DaaS)
   parameters: phenology (`life_stage`, `reproductive_condition`), population
   counts (`individual_count`), and cross-species relationships
   (`ecological_interactions`) synchronously within this zero-OOM primary pass.
5. **Asynchronous Edge Decoupling**: Heavy background work (the moderation
   pipeline, GBIF scrape, Wikipedia enrichment, and PostgreSQL UPSERTs) is
   deferred off the response path via `runBackground(task)` from
   `_shared/edgeHandler.ts`. The taxonomy payload is returned to the iOS client
   immediately. **Background ingestion failures are durably captured**: if
   `insertScan()` throws inside `runBackgroundIngestion()` (FK violation, DB
   timeout, network partition), the catch block writes a row to
   `public.failed_scan_ingestions` with the `scan_id`, `user_id`, and
   `error_message`. This dead-letter table lets ops identify and replay affected
   users without scanning log files. Replay is safe because `insertScan` uses
   `ignoreDuplicates: true`.
6. **Moderation Pipeline (`_shared/identify/moderation.ts`)**: Evaluates Gemini
   Safety Ratings before any write occurs. Unsafe media sets the user's status
   to `SHADOWBANNED`, increments abuse strikes, and deletes the R2 object. Safe
   media falls through to the Rolling Cloud Window storage policy, which selects
   the appropriate Cloudflare R2 lifecycle bucket based on `.userTier`. The
   shared moderation module calls `getR2Config()` once at the top and reuses the
   resulting `AwsClient`. **Moderation ERROR guard**: When
   `modResult.status === "ERROR"` (e.g. abuse strike DB write failed or a
   promotion batch fails), background ingestion halts immediately. The scan is
   not inserted, and any already-promoted public objects from that failed batch
   are rolled back before the function returns `ERROR`.
7. **R2 Promotion Rollback (Orphan Leak Prevention)**: After `moderation.ts`
   successfully copies the `1024px` downsampled binaries from `staging/` to
   `public_uploads/`, the final pipeline step runs the PostgreSQL `scans`
   `.insert()`. If the Database write fails (e.g. constraints, timeouts), an
   orchestrated `deleteR2Object()` rollback immediately purges the
   `public_uploads/` artifacts to absolutely prevent server-side Storage
   accumulation of untracked UUID blobs.
8. **Enrichment & Reference Imagery**: Wikipedia (deep-linked URLs and paragraph
   extracts), GBIF Occurrence (verified field imagery), and GBIF vernacular
   names (`alternative_common_names`) lookups run concurrently via
   `Promise.allSettled()` behind `AbortSignal.timeout(2500)` guards. The
   vernacular names result is stored in
   `species_dictionary.alternative_common_names` and returned as
   `alternative_common_names` in the identify response on Cache Hit. The
   ingestion pipeline writes verified image URLs into both the legacy
   comma-separated `species_dictionary.reference_image_url` cache and normalized
   `species_reference_images` rows; public dictionary/Explore readers prefer
   normalized rows and fall back to the legacy cache. These dictionary writes
   also record field-level provenance in `species_content_provenance` so stale
   or low-confidence species content can be refreshed deliberately later. The
   pipeline _exclusively_ sources reference imagery from these verified APIs to
   prevent LLM hallucinations. All Gemini response parsing uses
   `extractJson<T>(text)` from `_shared/gemini.ts`, which isolates the outermost
   JSON object via `indexOf`/`lastIndexOf` — necessary because Gemini
   occasionally wraps output in markdown fences even with
   `responseMimeType: "application/json"`. Parse failures return HTTP 422, which
   tells the iOS client to abort its retry loop rather than deadlock the offline
   queue. Error messages are generic: Gemini hallucinations surface as
   `"Processing Error: Malformed AI response."` and schema validation failures
   as `"AI processing error. Please try again."` — implementation details are
   not exposed to clients. **503 vs 400 for Gemini errors**: The
   `catch (genError)` block wrapping the Gemini call returns HTTP **503**
   (Service Unavailable) for transient Gemini errors — iOS treats 4xx as
   permanent and tombstones the scan, whereas 503 causes the offline queue to
   retain the scan for retry. Non-STOP finish reasons also return 503,
   **except** `SAFETY` and `PROHIBITED_CONTENT` which return 400 (permanent
   content policy failure — no point retrying).
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
    Misses can add new `common_names` entries to an existing row. To prevent
    lower-quality Flash-generated data from overwriting previously stored
    Pro-sourced taxonomy, toxicity, IUCN status, and habitat data, all those
    fields are written using `??` null-coalescing — existing non-null values are
    always preserved. Only `common_names` is unconditionally merged, as it is an
    intentionally keyed dictionary.
11. **Tier Resolution + Ghost Upsert (split critical path / background)**: Tier
    resolution is split: `getTierForUser(userId, supabaseAdmin)` from
    `_shared/tierCache.ts` runs on the critical path (before the Gemini call) to
    choose the model — it hits the 5-minute TTL worker-level cache or falls back
    to a single lightweight `SELECT subscription_tier`. Ghost users (no row in
    `users`) default to `"free"` but are intentionally NOT cached, so the
    background task can call `hasTierCached(userId)` to detect the missing row
    and issue the `users` upsert
    (`{ onConflict: "id", ignoreDuplicates: true }`) before the `scans` FK
    insert. After upserting, the background task calls
    `setTierCache(userId, "free")` so subsequent warm-isolate requests skip the
    DB round-trip. `ignoreDuplicates: true` ensures an existing user's
    `subscription_tier` is never overwritten by the ghost-user path.
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
    captures Gemini's internal reasoning token consumption (thinkingBudget: 2048
    for Flash, 5000 for Pro) and is billed at the output token rate — it is the
    dominant cost driver for Pro scans. `llm_cached_tokens` is non-zero when
    Gemini's implicit context caching served the system instruction prefix from
    cache (Flash only; requires the prefix to exceed 1,024 tokens); cached
    tokens are billed at 75% off the standard input rate. `colors` feeds into
    `semanticTags` on the Swift side for full-text search. `ai_reasoning` is
    fetched back during historical cloud sync and stored as
    `LocalScanRecord.aiReasoning`. Note: `group_tags` are stored on
    `species_dictionary`, not `scans`. **LLM field sanitization bounds**
    (applied in `index.ts` after scientific name sanitization, before the DB
    insert): `colors`, `extracted_visual_traits`, and `ecological_interactions`
    are each capped at 10 items; `ai_reasoning` is truncated to 2000 characters;
    `individual_count` is validated as a positive integer ≤ 99999;
    `estimated_size_cm` (client-supplied) is validated as a positive finite
    number ≤ 50000. **GPS coordinate range validation**: `gpsLatitude` and
    `gpsLongitude` from the client payload are validated against physical bounds
    (`−90 ≤ lat ≤ 90`, `−180 ≤ lon ≤ 180`). Out-of-range values are sanitised to
    `null` (stored as `safeGpsLat`/`safeGpsLon`) rather than rejecting the
    request — location is supplementary metadata and a bad coordinate must not
    abort identification. **`candidates` cap**: the `candidates` array received
    from Gemini is capped at 5 items before `payloadReadyForClient` is built,
    bounding the JSONB column and client decode size. These guards protect the
    V8 heap and SQLite columns from unbounded LLM output.
13. **Response format**: Returns `{ success: true, data: { ... } }` to the iOS
    client via `jsonResponse()`.

## The Public Species Dictionary Node (`species-dictionary`)

The `/species-dictionary` Edge Function is a public read-only projection over
species-level dictionary data. It powers the standalone
`SpeciesDictionaryPageView` opened from Insight similar-species cards and
Explore post detail similar-species cards, and is safe for a future web
frontend.

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
- The response must not include scan IDs, user IDs, Explore post IDs, field
  notes, comments, locations, local user media, per-scan AI reasoning, or
  preferred-name overrides.
- Lookalikes are hydrated with the explicit `species_dictionary!lookalike_id` FK
  hint because `species_lookalikes` has two foreign keys to
  `species_dictionary`.
- V1 does not expose provenance in the API response. Freshness/source data is
  stored separately in `species_content_provenance` for internal refresh
  workflows and future curation surfaces.

See `docs/backend-and-data/05-api-contracts.md` and
`docs/features-and-hardware/16-species-dictionary.md` for the request/response
contract and iOS surface.

## The Scheduled Species Content Refresh Node (`refresh-species-content`)

The `/refresh-species-content` Edge Function is an internal service-role worker
invoked by `pg_cron`/`pg_net`. It consumes
`public.get_species_content_refresh_queue(...)`, batches stale rows by species,
refreshes supported public fields from GBIF/Wikipedia, writes updated dictionary
fields, synchronizes normalized reference imagery through
`public.replace_species_reference_images(...)`, and records fresh provenance
rows.

Key rules:

- `verify_jwt = false` is configured for `pg_net` compatibility, but every
  request must include `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` and
  is checked with `timingSafeCompare`.
- The scheduled job `refresh_species_content_hourly` runs at minute 17 every
  hour with `{ "limit": 25 }`; manual service-role calls may use `dry_run`,
  `as_of`, `limit`, and `content_keys`.
- Per-species refresh work runs with a concurrency cap of 4 to stay within Edge
  runtime bounds without overwhelming GBIF/Wikipedia.
- V1 refreshes only fields backed by authoritative external APIs:
  `alternative_common_names`, `taxonomy`, `wikipedia_url`, `wikipedia_overview`,
  `gbif_taxon_key`, and `reference_images`.
- Unsupported queued keys are reported as skipped rather than overwritten.
  `common_names`, `habitat_description`, `lookalikes`, `group_tags`,
  `iucn_red_list_status`, and `hazard_type` remain reserved for future
  curation/model refresh workflows.
- Reference image refreshes update the legacy comma-separated cache and the
  normalized `species_reference_images` table. Existing license/attribution
  metadata is preserved when a refreshed URL matches an existing row. Merian
  community rows are preserved and ordered separately by the Merian reference
  image worker.

## The Scheduled Merian Reference Image Node (`refresh-merian-reference-images`)

The `/refresh-merian-reference-images` Edge Function is an internal service-role
worker invoked by `pg_cron`/`pg_net`. It promotes high-quality, currently
published Explore media into public species dictionary galleries with
`source = "merian"`.

Key rules:

- `verify_jwt = false` is configured for `pg_net` compatibility, but every
  request must include `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` and
  is checked with `timingSafeCompare`.
- The scheduled job `refresh_merian_reference_images_hourly` runs at minute 37
  every hour with
  `{ "quality_threshold": 90, "species_confidence_threshold": 0.95, "per_species_limit": 8 }`.
- Selection happens transactionally in
  `public.refresh_merian_reference_images(...)`: visible Explore posts only,
  all non-empty image URLs from qualifying scans, `image_quality_score >= 90`,
  `ai_confidence_score >= 0.95` unless `confirmed_species_id` is present,
  species resolution through `COALESCE(confirmed_species_id, species_id)`, and
  up to 8 promoted images per species.
- Public rows store only `url`, `source = "merian"`,
  `license = "Used with permission via Merian"`, and the public author label in
  `attribution`. Source scan/post/user IDs remain in the private
  `species_reference_image_merian_sources` table along with the private
  confidence/provenance snapshot used for promotion.
- If an Explore post is unshared, media is cleared, geoprivacy becomes private,
  the scan is tombstoned, or the author is shadowbanned, the next refresh removes
  the corresponding Merian public reference image.

## The Unified Multi-Modal Inference Node (`identify-multimodal`)

The `/identify-multimodal` Edge Function is the primary client-facing inference
path today. It unifies the image, audio, and text-only request shapes into one
pipeline while the legacy endpoints remain deployed for compatibility.

1. **Payload Assembly**: It accepts `imageBase64s`, image `r2ObjectKeys`, inline
   `audioBase64s`, staged `audioR2ObjectKeys`, and `observation_contexts`
   arrays.
2. **WAV Preprocessing**: Audio data is preflighted before decode/fetch. The
   endpoint rejects oversized request `Content-Length` headers before
   `req.json()`, then delegates inline base64 length, raw byte size, clip count,
   staged-key ownership, R2 `Content-Length`, and `..` traversal checks to
   `_shared/identify/media.ts`. Audio buffers are processed serially via
   `processWAV` (mono mix, silence trim, 16kHz resample) to keep V8 heap
   pressure predictable.
3. **Dynamic Dispatch Logic**: Generates inference payload based on the
   submitted modalities:
   - **Combined Text, Audio & Vision**: Uses
     `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` focusing on comprehensive
     multi-sensory synthesis.
   - **Audio-only (`audioBase64s`)**: Dispatches using
     `BIOACOUSTIC_SYSTEM_INSTRUCTION`, leveraging specific bioacoustic AI
     interpretation.
   - **Vision-only (`imageBase64s`)**: Follows the standard vision
     identification path.
   - **Text-only (`observation_contexts`)**: Follows the legacy sighting
     pipeline utilizing only the user's structured observation text.
4. The current iOS client sends queued images via `r2ObjectKeys`, queued audio
   via `audioR2ObjectKeys`, live foreground audio via inline `audioBase64s`, and
   text via `observation_contexts`. Telemetry on this active path is camelCase
   (`gpsLatitude`, `semanticLocation`, `deviceTimeZone`, etc.); the server also
   accepts legacy snake_case aliases for backward compatibility during offline
   queue replay and staged endpoint migration.
5. Candidate handling on `/identify-multimodal` now matches `/identify`:
   scientific names are sanitized before cache lookup/persistence, `candidates`
   are stripped at `confidence_score >= diagnosticTrigger`, cached English
   common names are attached synchronously when available, and cache misses are
   enriched in the background so the next scan is warm.
6. Persisted multimodal scan imagery still lands in `scans.image_storage_urls`.
   Staged audio is an inference input, not a public media artifact;
   `identify-multimodal` deletes `audioR2ObjectKeys` from staging after
   successful background ingestion.

## The Explore Social Surface

Explore uses a dedicated set of Edge Functions and SQL RPCs rather than sharing
the identify pipeline. The current shipped surface includes:

- feed + detail reads: `get-explore-feed`, `get-explore-post`,
  `get-explore-post-detail`, `get-explore-comments`
- author profile reads: `get-explore-author-profile`, `get-explore-author-posts`
- map reads: `get-explore-map-points`
- mutations: `share-scan-to-explore`, `unshare-explore-post`,
  `update-explore-field-notes`, `set-explore-post-like`, `set-user-follow`,
  `create-explore-comment`, `delete-explore-comment`,
  `toggle-explore-comment-reaction`, `report-explore-comment`
- activity reads: `get-explore-notifications`,
  `get-explore-unread-notification-count`, `mark-explore-notifications-read`
- device registration and delivery: `register-push-device`,
  `send-push-notification`

The in-app notifications feed is backed by `public.explore_post_notifications`,
not by local client state. Like notifications are recomputed from the
authoritative `explore_post_likes` table after each insert/delete so concurrency
cannot drift the aggregate count, comment notifications are created and removed
via triggers on `explore_post_comments`, comment-reaction notifications are
recomputed per `(comment, emoji)` from `explore_comment_reactions`, follow
notifications are created and removed via triggers on `user_follows`,
self-notifications are suppressed server-side, and notification rows are pruned
when a post is unshared, a comment is author-deleted or owner-moderated, a
follow is removed, or either user blocks the other.

`get-explore-post` is an important routing helper for the iOS client and the
public Next.js web app: it returns a single privacy-safe feed-card projection so
notification taps, deep links, and `https://merian.earth/explore/post/{postId}`
pages do not depend on the target post already existing in the currently paged
`ExploreFeedViewModel.posts` array. Public web consumers must treat this as the
maximum public projection and avoid querying private scan/auth tables directly.

Author profile reads are split the same way as feed/detail reads.
`get-explore-author-profile` returns a privacy-scoped profile sheet payload only
when the target author has at least one visible Explore post for the requester.
Aggregates are computed from the author's non-tombstoned scans, while preview
posts are filtered to currently visible Explore posts. It also returns public
follower/following counts plus the requester-specific `viewer_is_following`
flag. `get-explore-author-posts` returns the full published library projection
with stable `(shared_at, post_id)` cursor pagination. Neither endpoint exposes
raw auth metadata, exact coordinates, private scan IDs for achievements,
qualifying achievement scans, or browsable follower/following identities.

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
  `public.get_explore_feed_nearby(...)`, requiring viewer coordinates, reusing
  the same privacy-safe public coordinate rules as the Explore map, filtering to
  a roughly 50-mile radius, and then sorting the resulting posts by recency

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
`get-explore-map-points` adds zoom-aware clustering and returns either clusters
or individual post rows. The current shipped implementation does not store map
coordinates on `explore_posts`. Instead, `public.scans.gps_lat_public` /
`gps_long_public` are normalized by the `trg_sync_scan_public_coordinates`
trigger and backfilled by migration
`20260428213000_fix_explore_map_public_coordinate_fallback.sql`, which also
fixed the regression where newly shared scans with only exact coordinates could
be invisible on the Explore map.

Explore activity now supports optional remote APNs delivery on top of the in-app
feed. The app registers APNs device tokens through `register-push-device`,
stores them in `public.user_push_devices`, and a Postgres trigger on
`public.explore_post_notifications` uses `pg_net` to invoke
`send-push-notification` whenever a visible post-backed notification row is
inserted or a like/comment-reaction aggregate count increases. Follow
notifications are postless, informational, and intentionally skipped by the push
trigger.

## The Webhook Node (`revenuecat-webhook`)

The `revenuecat-webhook` function drives async tier migrations (`pro` ↔ `free`).
Because Deno enforces a 10-second processing limit, bulk R2 operations are
deferred via `runBackground(task)` from `_shared/edgeHandler.ts`. The webhook
secret is validated using `timingSafeCompare()`, a constant-time XOR comparison,
rather than plain string equality — this prevents timing attacks. The deferred
task queries orphaned `public_uploads/free/` objects from the `scans` table and
issues `AWS SDK PUT` copy commands to move them into the `/pro/` bucket. To
prevent IDOR attacks on S3 deletes, the function validates that the
`originalUserId` parsed from `image_storage_urls` matches the `userId`
associated with the webhook trigger. **Concurrent webhook idempotency**
(`storage.ts`): Before issuing a copy for a URL, the function checks whether the
URL already contains the target prefix (e.g., `/pro/`). If it does, the copy is
skipped rather than retried — this handles concurrent webhook retry deliveries
from RevenueCat without creating duplicate objects or spurious `403` errors.
**Tier cache invalidation**: After writing the new tier to the `users` table,
the function immediately calls `setTierCache(userId, tier)` from
`_shared/tierCache.ts` to update the in-process isolate cache. Without this, a
Pro purchaser would receive `gemini-2.5-flash` calls (free tier) for up to 5
minutes while the TTL-based cache holds the stale `"free"` entry.

On `EXPIRATION` (user downgrade), the same process runs in reverse, moving
objects from `/pro/` back to `/free/`, returning them to the targeted 90-day
domesticated purge cycle.

Before saving `image_storage_urls` to PostgreSQL, the function strips AWS
signature query string parameters from the URL to prevent Cloudflare R2
`403 Forbidden` errors when the object key changes. R2 access uses
`getR2Config()` from `_shared/aws.ts`.

## The Scientific Export Pipeline (`request-export-dwca` & `export-dwca`)

Researchers export global and personal occurrence data via a two-step queueing
architecture that completely bypasses Edge HTTP timeout constraints:

1. **Queue Insertion (`request-export-dwca`)**: The iOS client hits this
   lightweight proxy, which verifies the user and inserts a job row into the
   `export_jobs` PostgreSQL queue. To prevent Resend API spam and queue
   flooding, it enforces a strict **24-hour rate limit** per user. The insert is
   idempotent against concurrent duplicate submissions: if a second request
   races in before the first row is committed, the resulting PostgreSQL `23505`
   unique-constraint violation is caught and the function returns
   `429 Too Many Requests` instead of a `500` error, consistent with the
   rate-limit path. Before inserting, the function validates the `exportScope`
   parameter against the enum `["personal", "global"]` — values outside this set
   are rejected with `HTTP 400`. It also validates that
   `includePreciseCoordinates` is a boolean — a non-boolean value is rejected
   with `HTTP 400`. The iOS client always sends
   `includePreciseCoordinates: true` for personal exports — this is intentional:
   users downloading their own data receive full-resolution GPS coordinates. For
   `"global"` scope exports, `export-dwca` scrubs GPS coordinates for all rows
   except the requesting user's own records server-side, regardless of this
   flag. It returns `200 OK` instantly when the job is successfully enqueued.
2. **Postgres Webhook (`pg_net`)**: The queue insertion fires a native Postgres
   trigger that posts to `/export-dwca`.
3. **Webhook Worker (`export-dwca`)**: This node receives the job,
   authenticating via `SUPABASE_SERVICE_ROLE_KEY`. It manages heavy execution:
   - **OOM Streaming**: Uses a `ReadableStream` with AWS `UNSIGNED-PAYLOAD`
     signatures to stream binary data directly to R2 in chunks, rather than
     holding a full `JSZip.generateAsync()` blob in the V8 heap.
   - **RFC 4180-compliant CSV (`csvField()`)**: All occurrence and multimedia
     CSV rows are built using the `csvField(value)` helper in
     `export-dwca/dwca.ts`. Every field is wrapped in double quotes; internal
     double quotes are escaped by doubling them (`"` → `""`); newlines within
     field values are replaced with a space (DwC-A parsers treat `\n` as a row
     terminator). Null and undefined values become empty quoted fields (`""`).
     This ensures the archive is parseable by all standard DwC-A consumers
     without field-boundary ambiguity.
   - **Cryptographic Geoprivacy**: User IDs are replaced with stable pseudonyms
     generated via `crypto.subtle.digest` SHA-256 (e.g.
     `merian_user_a785f2b...`). Scientists can verify user-level streaks without
     accessing the underlying Supabase token. Exact GPS coordinates are scrubbed
     for any user data apart from the requesting user.
   - **DaaS Standardization**: Natively maps `life_stage`,
     `reproductive_condition`, `individual_count`, `estimated_size_cm`, and
     `ecological_interactions` directly into standard GBIF DwC-A headers
     (`lifeStage`, `reproductiveCondition`, `individualCount`, etc.).
   - **Asynchronous Delivery**: Once the ZIP reaches R2, it fetches the user's
     `auth.users` database email and dispatches a secure Resend email containing
     an expiring `X-Amz-Expires=86400` download link.
   - **Stuck-job watchdog (`20260405000004`)**: A `pg_cron` job
     (`expire-stuck-export-jobs`) runs every 5 minutes and tombstones any job
     stuck in `'processing'` for more than 30 minutes (`status = 'failed'`,
     descriptive `error_message`). Without this, a killed Edge function leaves
     the job in `'processing'` permanently and the iOS client shows an infinite
     loading state with no recovery path other than waiting.
   - **Null species guard (`dwca.ts`)**: `scan.species_dictionary` is treated as
     `DBScanRow['species_dictionary']` (typed optional). All property accesses
     use optional chaining (`species?.scientific_name`) and `csvField()` handles
     `undefined` as empty string (`""`). This replaces the previous `|| {}`
     fallback which caused `deno check` type errors on every property access.

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

- The `GEMINI_API_KEY` is absent from the iOS client bundle (`Info.plist` and
  `.xcconfig`). All LLM calls go through Supabase Edge Functions (`identify`,
  `identify-multimodal`, `enrich-scan`, etc.), which hold the key server-side.
- App-facing anonymous-compatible Edge Functions set `verify_jwt = false` in
  `config.toml`. Authenticated endpoints then perform manual JWT verification
  via `requireAuth` inside `withEdgeHandler`. This is mandatory for
  anonymous-compatible routes: omitting an entry causes Supabase's Kong gateway
  to default to `verify_jwt = true`, which validates the JWT at the gateway
  layer before the function code runs and rejects valid ES256 anonymous sessions
  with `401 Invalid JWT`. There are four intentional deviations:
  - **`merge-ghost-profile`**: Keeps `verify_jwt = true` because merging a ghost
    into an unauthenticated session is semantically invalid and a security risk.
    The gateway enforces a fully authenticated session before the function runs.
  - **`request-export-dwca`**: Keeps `verify_jwt = true` because personal data
    exports require a verified authenticated user identity — anonymous users
    have no stable identity to bind an export to.
  - **`species-dictionary`**: Keeps `verify_jwt = false` but intentionally skips
    `requireAuth` because it returns only public species-level dictionary data.
  - **`refresh-species-content`**: Keeps `verify_jwt = false` so `pg_net` can
    invoke the worker, then enforces the service-role bearer header inside Deno
    with `timingSafeCompare`.
- **Rule for new Edge Functions**: Every new function directory under
  `services/supabase/functions/` MUST have a corresponding `[functions.<name>]` entry in
  `config.toml` before deployment. Use `verify_jwt = false` for
  anonymous-compatible app routes, deliberately public routes, and `pg_net`
  workers that perform their own service-role secret check; use
  `verify_jwt = true` only for explicitly authenticated-only routes with no
  anonymous user path. Public unauthenticated routes must document their
  data-exposure boundary in both the function README and
  `docs/backend-and-data/05-api-contracts.md`; internal cron workers must
  document their service-role authorization boundary.

## Database Indexing & Performance

`00003_performance_indexes.sql` defines `CREATE INDEX CONCURRENTLY` for the
following:

- `idx_species_dict_scientific_name` on `species_dictionary (scientific_name)` —
  species lookup during inference.
- `idx_scans_user_id` on `scans (user_id)` — user streak queries.
- `idx_scans_discovery_feed` on
  `scans (geoprivacy, is_live_capture, timestamp DESC)` — global discovery feed
  fetches.
- `idx_scans_user_species` on `scans (user_id, species_id)` — supports the
  Postgres trigger computing `COUNT(DISTINCT species_id)`.
- `idx_scans_lifecycle` on `scans (timestamp) WHERE image_storage_urls != '{}'`
  — scopes the daily storage cleanup cron job to rows that have images, avoiding
  full-table scans.

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

## Storage Economics & Lifecycle Syndication

`00004_storage_lifecycle_sync.sql` configures a `pg_cron` job that clears
`image_storage_urls` on `subscription_tier = 'free'` rows older than 90 days. It
runs at 02:00 UTC daily. The underlying scan row is preserved; only the storage
URLs are cleared.

**`get-filtered-discovery-feed`**: Applies
`.not("image_storage_urls", "eq", "{}")` to exclude rows with cleared media from
public feeds. It also joins `users!inner(is_shadowbanned)` with
`.eq("users.is_shadowbanned", false)` to exclude shadowbanned content
server-side, since the service role key bypasses RLS. The query uses an explicit
column list rather than `select("*")`, omitting telemetry and analytics columns
(`device_locale`, `current_month`, `time_of_day`, `depth_scale_text`, `llm_*`
token counts, `extracted_visual_traits`, `ai_reasoning`, etc.) that the client
never renders. This reduces per-row payload size by approximately 60% at scale.

**Graceful Degradation**: Scans whose R2 media has expired render a
`.ultraThinMaterial` glass pane with an `archivebox.fill` icon in
`ScansThumbnailView` and `AsyncLocalImageView`, rather than looping on a
`ProgressView`.

### Automated 30-Day Non-Biological Purge

The `auto-purge-nonbio` Edge Function, triggered by `pg_cron` via `pg_net`,
removes non-biological scans after 30 days. A standard Cloudflare R2 Object
Lifecycle rule cannot be used here because R2 lifecycle rules operate on object
age and prefix, not on the PostgreSQL `is_biological_subject = false` flag. A
bare Postgres `DELETE` without R2 coordination would orphan stored objects. The
Edge Function handles both the database deletion and the R2 object removal
atomically. Webhook secret validation in this function uses
`timingSafeCompare()` for constant-time comparison.

### Targeted 90-Day Domesticated Purge

The `auto-purge-domesticated` Edge Function reclaims heavy storage costs by
purging 90-day-old `domesticated` ecology scans from Free tier users without
touching valuable `wild` and `invasive` specimens. To safely avoid Deno's
wall-clock timeouts when issuing hundreds of network API calls to Cloudflare,
the R2 `deleteObjects` requests are batched and executed concurrently using
`Promise.all` in chunks of 50. This perfectly balances the V8 event loop against
R2's concurrency rate limits. It zeroes out the `image_storage_urls` array
rather than dropping the row, ensuring the user's localized text record safely
remains in their app gallery.

## Token Cost Analytics (`services/supabase/analytics/`)

`services/supabase/analytics/` contains version-controlled SQL queries for LLM cost
observability. These are the authoritative source for API spend analysis —
PostHog owns behavioral metrics (funnel, session, conversion); Supabase SQL owns
cost metrics (token counts are persisted directly to `public.scans` and are
queryable at the row level without any sampling or event pipeline delay).

Run these in **Supabase → SQL Editor → Save** to pin them as named queries:

| File                              | Purpose                                                                                                                                                                                                                                            |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `token_cost_summary.sql`          | Estimated API spend by tier for any date window. Applies current Gemini pricing constants (Flash: $0.075/M input, $0.01875/M cached, $0.30/M output; Pro: $1.25/M input, $10/M output) against actual stored token counts.                         |
| `cache_effectiveness.sql`         | Daily Flash implicit cache hit rate and savings in cents. A hit is any scan where `llm_cached_tokens > 0`. Only meaningful for Flash scans after the system instruction exceeded the 1,024-token caching threshold.                                |
| `thinking_token_distribution.sql` | P50/P90/P95/max thinking token usage by tier, plus `pct_at_budget_ceiling` — the percentage of scans where thinking usage approached the configured budget (2,048 Flash / 5,000 Pro). A high ceiling-hit rate signals the budget should be raised. |
| `daily_cost_trend.sql`            | Per-day API spend by tier for the last 30 days. Use to spot cost anomalies from traffic surges or pricing changes.                                                                                                                                 |
| `token_averages_by_week.sql`      | Weekly averages for all token fields plus cache hit rate. Shows step-changes after system instruction deployments and validates financial model assumptions.                                                                                       |

**Pricing note**: Gemini pricing changes frequently. The constants in these
queries should be audited quarterly against the current Google AI pricing page
and reconciled with actual PostHog `ScanCompleted.llm_cached_tokens` totals.

### Cloudflare R2 Object Lifecycle Rules

The following three Object Lifecycle Rules must be configured in the Cloudflare
R2 Dashboard under **Settings → Object Lifecycle**:

1. **Default Multipart Abort Rule**
   - **Prefix:** `--`
   - **Action:** Abort incomplete multipart uploads after `7` days
2. **Purge staging objects after 1 day**
   - **Prefix:** `staging/`
   - **Action:** Delete objects after `1` day
3. **Quarantine Cleanup**
   - **Prefix:** `quarantine/`
   - **Action:** Delete objects after `1` day

## Customer Support & ML Feedback Loop (`flag-issue`)

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
- **`flagged_reviews` table** (`00005_flagged_reviews.sql`): Stores flagged scan
  references tied to the reporting `user_id`, defaulting to `PENDING_REVIEW`.
- **`scans` table update**: Sets `is_flagged = true` and writes debug context to
  `human_intervention_notes` on the parent scan.

## Account Deletion & Data Preservation (`safe-delete`)

Account deletions use the `apply_user_tombstone` PL/pgSQL function
(`00006_apply_user_tombstone.sql`). Instead of cascade-deleting scan rows, it
reassigns the user's scans to a permanent anonymous tombstone user
(`00000000-0000-0000-0000-000000000000`) and sets `is_tombstoned = true`. The
original user record and telemetry are then deleted without losing the
biological observation data. The tombstone user targets the
`current_streak_count` column, not any legacy field.

**Operation order**: The `safe-delete` function executes in the following
sequence to minimise the window in which a revoked user can still issue API
calls: (1) **Revoke auth** — `supabaseAdmin.auth.admin.deleteUser(user.id)` is
called first, immediately invalidating the user's JWT; (2) **Tombstone** —
`apply_user_tombstone` RPC reassigns scans and marks the user as deleted; (3)
**Queue storage deletion** — R2 object purges are enqueued for background
processing. Auth is revoked before the tombstone write, not after, so any
race-condition API calls received after deletion begins are rejected at the JWT
verification layer.

**Partial-failure handling**: If `applyUserTombstone` throws after auth has
already been successfully revoked, the function logs a structured error via
`logStructuredError` with `event: "safe_delete_partial_failure"` and
`action_required: "Manually run apply_user_tombstone RPC"`, then re-throws the
error so the response is `500` rather than a false-success `200`. This prevents
silent data-integrity gaps where auth is gone but the tombstone was never
applied. `queueStorageDeletion` failures are intentionally non-throwing —
storage queue failures log a structured error via `logStructuredError` but do
not block account deletion. The JWT has already been revoked and the user
tombstoned at this point, so blocking here would leave a completed deletion
appearing as a `500` to the client; the storage objects will be swept by the
background cleanup cron.

**`logStructuredError` alerting requirement**:
`logStructuredError(event, details)` from `_shared/edgeHandler.ts` emits
`JSON.stringify({ event, ts, ...details })` to `console.error`. These structured
logs must be connected to a log drain (Logflare or Datadog) with an alert
configured on `event: "safe_delete_partial_failure"`. Without this alert,
partial account deletions (auth revoked but tombstone not applied) will silently
accumulate and require manual intervention to detect. All functions that call
`logStructuredError` for operationally critical events must have a corresponding
alert rule.

On `200 OK`, the iOS client calls `supabase.signOut()`, tears down the local
SQLite database via `ScanRepository.shared.purgeAllData()`, and clears all
cached image files from disk.

## Scan Erasure & The Deletion Pipeline (`delete-scan`)

Individual scan deletion severs the record from both Supabase and Cloudflare R2:

1. **Auth**: JWT is extracted and verified manually. Deletion is locked to the
   scan's `owner_id`.
2. **R2 Deletion**: The function reads `image_storage_urls` from Supabase. Since
   these URLs use the public Cloudflare Web domain
   (`https://media.merian.app/...`), the function rewrites them to the R2
   storage domain (`https://<account>.r2.cloudflarestorage.com/<bucket>/...`)
   before issuing signed `DELETE` requests via `AwsClient` from `aws4fetch`.
3. **Database Erasure**: A `.delete()` call removes the scan row.
4. **Gamification Trigger**: The `decrement_user_species_count()` PL/pgSQL
   function fires on `AFTER DELETE ON public.scans`. If the deleted scan was the
   user's last record for that `species_id`, it decrements
   `users.total_species_discovered` by 1 without going below zero.

#### V8 Execution Abstractions

- **Explicit Deno ES Modules**: To avoid Supabase CLI bundling failures caused
  by unresolved local import maps, all edge dependencies use direct HTTP module
  URLs (e.g., `https://esm.sh/@supabase/supabase-js@2.49.1`). The
  `services/supabase/functions/deno.json` config includes
  `"exclude": ["no-import-prefix"]` to suppress the corresponding `deno-lint`
  warning locally.
- **`_shared` Utilities**: The `http.ts`, `edgeHandler.ts`, `biology.ts`,
  `external.ts`, `tierCache.ts`, `posthog.ts`, `gemini.ts`, `aws.ts`, and
  `auth.ts` domains cleanly separate the core proxy engine natively without
  polluting the specific Webhook routers.

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
- **IDOR guard**: `filterOwnedCollections` resolves which incoming collection
  IDs are actually owned by the authenticated user against the existing DB rows.
  All downstream upsert and delete calls receive pre-filtered collections — no
  function re-implements the ownership check independently.
- **`collection_scans` membership delta**: Only the diff (rows to add minus rows
  to remove) is written — the function does not delete and re-insert all
  memberships on each sync. This prevents unnecessary DB churn on large
  collections. All three DB operations inside `syncMembershipDelta` (scan
  validation, membership inserts, membership deletes) throw on error rather than
  swallowing via `console.error` — the controller propagates a `500` so the iOS
  client retries rather than treating a partial failure as confirmed.
- **`collection_scans` SELECT cap**: The membership hydration query is capped at
  `.limit(10000)` to bound V8 heap exposure. The theoretical maximum (200
  collections × 5000 scan IDs = 1M rows) would be unsafe to load in a single
  query; a per-collection streaming refactor remains the long-term solution.

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

## Ghost Account Merge (`merge-ghost-profile`)

When an anonymous (guest) user signs up for a full account, their prior scan
history is merged into the new authenticated identity:

**Operation order** (all steps run before the ghost is purged):

1. `verifyGhostUser` — confirms the target is an anonymous account (not another
   authenticated user). Logs and returns `403` on IDOR attempts.
2. `transferScans` — re-parents all `scans` rows from `ghost_id` to the
   authenticated `user.id`.
3. `transferCollections` — re-parents all `collections` rows. **Must run before
   `purgeGhostUser`**: the `collections` table references
   `auth.users(id) ON DELETE CASCADE`, so deleting the ghost from `auth.users`
   would silently drop all collections if this step is skipped.
4. `purgeGhostUser` — deletes the ghost from `auth.users` (cascades to
   `collections` and `export_jobs` — both already transferred or empty) and then
   explicitly deletes `public.users(ghost_id)`. The `public.users` row has no FK
   to `auth.users` and must be deleted manually; this cascade also cleans up any
   `flagged_reviews` and `user_blocks` tied to the ghost identity, which have no
   value after the merge.

## Required Edge Function Secrets

For a production deployment, the following secrets MUST be set in the Supabase
Vault via the CLI (`supabase secrets set KEY=VALUE`):

- **`GEMINI_API_KEY`**: Authenticates all `gemini-2.5-flash` and
  `gemini-2.5-pro` model inferences.
- **`POSTHOG_API_KEY`**: Authenticates server-side ingestion into PostHog.
- **`CLOUDFLARE_R2_ACCESS_KEY_ID` / `CLOUDFLARE_R2_SECRET_ACCESS_KEY`**: Grants
  backend write access to the R2 Storage bucket.
- **`REVENUECAT_WEBHOOK_SECRET`**: Constant-time verification string ensuring
  webhook triggers originate from RevenueCat.
- **`RESEND_API_KEY`**: The API Key from Resend for sending transactional emails
  (like DwC-A exports).
- **`RESEND_FROM_EMAIL`**: The verified sender domain (e.g.,
  `exports@merian.earth`). If absent, it falls back to Resend's testing domain
  `onboarding@resend.dev` which will FAIL unless sending to the developer's
  registered account.
- **`DWC_A_SECRET_SALT`**: A high-entropy salt used to generate stable but
  anonymized IDs for global exports.

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
