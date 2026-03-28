# Supabase Edge and PostgreSQL Engine

Merian uses Supabase as its backend platform. API keys are kept in `.xcconfig` files and never bundled into the client binary. All LLM and database operations execute server-side in Deno Edge Functions.

## Core Schema Structure

`00001_initial_schema.sql` defines the base backend schema. `00002_user_auth_trigger.sql` handles the auth relationship. All anonymous users are identified by a persistent Keychain-backed `UIDevice.current.identifierForVendor` IDFV.

- **`species_dictionary`**: Stores every tracked taxon with its scientific and biological descriptors.
- **`scans`**: Records GPS bounds, the LLM-generated `ai_confidence_score`, `inference_tier`, UUID references, and the `ecology_type_enum` for each scan, tied to the user's streak.
- **`users`**: Binds the IDFV (or authenticated UUID) to the product schema, tracking usage limits and subscription tier.
- **`unified_species_count_sync` (`20260320132111_unified_species_count_trigger.sql`)**: A unified, idempotent Postgres `AFTER INSERT OR UPDATE OR DELETE ON public.scans` trigger that recalculates `total_species_discovered` in the `users` table via `SELECT COUNT(DISTINCT species_id)`. This replaces the previously split trigger files and eliminates TOCTOU schema drift on moderation updates.

## Shared Edge Utilities (`_shared/`)

Several utilities are shared across all Edge Functions via `supabase/functions/_shared/`:

- **`edgeHandler.ts`**: Wraps endpoints in `withEdgeHandler()`, which handles CORS `OPTIONS` preflights and the `requireAuth` middleware in one place, eliminating boilerplate across all function files. It also exports `jsonResponse(payload, status)` and a `runBackground(task)` utility that calls `EdgeRuntime.waitUntil(task)` in production and falls back gracefully for local development.
- **`gemini.ts`**: Exports the module-level `_genAI` singleton (`GoogleGenerativeAI` instance), `createFlashModel(systemInstruction, maxOutputTokens)` — a factory for all Flash-only background calls — and `extractJson<T>(text)`, which extracts the outermost JSON object from a Gemini response string using `indexOf`/`lastIndexOf`. This eliminates the repeated extraction pattern across `identify`, `enrich-scan`, and `_shared/diagnostic.ts`.
- **`tierCache.ts`**: Exports `getTierForUser(userId, supabaseAdmin)` (5-minute TTL worker-level cache, does NOT cache ghost users), `hasTierCached(userId)` (ghost detection for the background task), and `setTierCache(userId, tier)` (explicit cache write after ghost-user upsert). All three work together to keep tier resolution off the critical path without losing ghost-user upsert correctness.
- **`validation.ts`**: Exports `requireParams(body, fields)` — returns a `400 Response` if any required fields are missing, otherwise `null`. Used by `flag-issue`, `delete-scan`, `block-user`, `merge-ghost-profile`, and `enrich-scan`.
- **`aws.ts`**: Exports `getR2Config()` (creates `AwsClient` + bucket/endpoint), `deleteR2Objects`, `copyR2Object`, `deleteR2Object`, and `generatePresignedPutUrl(config, key, expirySeconds)` — a shared presigned-PUT helper used by `generate-upload-urls`.

## The Edge Inference Node (`identify`)

The `/identify` Edge Function acts as the inference proxy:

1. **Auth**: Receives a structured payload from iOS. The `Authorization` header JWT is verified via `requireAuth` inside `withEdgeHandler`. Merian uses anonymous ES256 sessions (`signInAnonymously`), so the default Supabase `verify_jwt` Edge Middleware is disabled in `supabase/config.toml` (`verify_jwt = false`). Auth is handled manually via the Supabase SDK.
2. **Direct Base64 Transfer**: If the iOS client sends `imageBase64`, the Edge Function decodes it directly into a `Uint8Array` and passes it as `inlineData` to Gemini. This removes the need for an S3 staging round-trip and reduces pipeline latency.
3. **Legacy AWS Fallback (`_shared/aws.ts`)**: If `imageBase64` is absent (e.g., during background `URLSession` uploads where the image was already staged to R2), the function falls back to fetching from R2 via `getR2Config()`. Responses are processed in a serial `for…of` loop: each response body is consumed via `arrayBuffer()` and the running `totalBytes` counter is incremented by `arrayBuffer.byteLength` (the actual byte count after body consumption). If the accumulated total exceeds 5 MB, the function immediately returns HTTP 413. Relying on `Content-Length` headers is intentionally avoided — chunked transfer encoding makes this header absent or unreliable on R2 responses, which would allow arbitrarily large payloads to exhaust the 256 MB Deno V8 heap before any guard fired.
4. **Google Gemini Model Selection**: Pro users use `gemini-2.5-pro` for maximum identification depth (rare species, fossils, subspecies). Free users use `gemini-2.5-flash` for 2–3× lower latency. The model is chosen immediately after the tier SELECT — before the Gemini call — so both tiers receive the correct model. Generation uses `temperature: 0.1` for rigid JSON output. The schema explicitly instructs Gemini to extract Data-as-a-Service (DaaS) parameters: phenology (`life_stage`, `reproductive_condition`), population counts (`individual_count`), and cross-species relationships (`ecological_interactions`) synchronously within this zero-OOM primary pass.
5. **Asynchronous Edge Decoupling**: Heavy background work (the moderation pipeline, GBIF scrape, Wikipedia enrichment, and PostgreSQL UPSERTs) is deferred off the response path via `runBackground(task)` from `_shared/edgeHandler.ts`. The taxonomy payload is returned to the iOS client immediately.
6. **Moderation Pipeline (`moderation.ts`)**: Evaluates Gemini Safety Ratings before any write occurs. Unsafe media sets the user's status to `SHADOWBANNED`, increments abuse strikes, and deletes the R2 object. Safe media falls through to the Rolling Cloud Window storage policy, which selects the appropriate Cloudflare R2 lifecycle bucket based on `.userTier`. `moderation.ts` calls `getR2Config()` once at the top and reuses the resulting `AwsClient` — it no longer calls both `getS3Client()` and `getR2Config()` separately, which previously created two `AwsClient` instances.
7. **R2 Promotion Rollback (Orphan Leak Prevention)**: After `moderation.ts` successfully copies the `1024px` downsampled binaries from `staging/` to `public_uploads/`, the final pipeline step runs the PostgreSQL `scans` `.insert()`. If the Database write fails (e.g. constraints, timeouts), an orchestrated `deleteR2Object()` rollback immediately purges the `public_uploads/` artifacts to absolutely prevent server-side Storage accumulation of untracked UUID blobs.
8. **Enrichment & Reference Imagery**: Wikipedia (deep-linked URLs and paragraph extracts) and GBIF Occurrence (verified field imagery) lookups run concurrently via `Promise.allSettled()` behind `AbortSignal.timeout(2500)` guards. The pipeline *exclusively* sources `reference_image_url` from these verified APIs to prevent LLM hallucinations. All Gemini response parsing uses `extractJson<T>(text)` from `_shared/gemini.ts`, which isolates the outermost JSON object via `indexOf`/`lastIndexOf` — necessary because Gemini occasionally wraps output in markdown fences even with `responseMimeType: "application/json"`. Parse failures return HTTP 422, which tells the iOS client to abort its retry loop rather than deadlock the offline queue. Error messages are generic: Gemini hallucinations surface as `"Processing Error: Malformed AI response."` and schema validation failures as `"AI processing error. Please try again."` — implementation details are not exposed to clients.
8. **Swift `JSONDecoder` Null Protection**: `wikipedia_overview` is a flat `TEXT` column on `species_dictionary` — it can be `null` if Wikipedia has no entry. The iOS decoding struct types this as `let wikipedia_overview: String?`. It is returned directly from the Edge function as `wikipedia_overview` in the API response and stored as `LocalScanRecord.wikipediaOverview`.
9. **Species Dictionary Upsert**: Calls `supabaseAdmin.from('species_dictionary').upsert()` with `{ onConflict: "scientific_name", ignoreDuplicates: false }`. This always merges on conflict rather than skipping, ensuring that locale-miss Cache Misses can add new `common_names` entries to an existing row. To prevent lower-quality Flash-generated data from overwriting previously stored Pro-sourced taxonomy, toxicity, IUCN status, and habitat data, all those fields are written using `??` null-coalescing — existing non-null values are always preserved. Only `common_names` is unconditionally merged, as it is an intentionally keyed dictionary.
10. **Tier Resolution + Ghost Upsert (split critical path / background)**: Tier resolution is split: `getTierForUser(userId, supabaseAdmin)` from `_shared/tierCache.ts` runs on the critical path (before the Gemini call) to choose the model — it hits the 5-minute TTL worker-level cache or falls back to a single lightweight `SELECT subscription_tier`. Ghost users (no row in `users`) default to `"free"` but are intentionally NOT cached, so the background task can call `hasTierCached(userId)` to detect the missing row and issue the `users` upsert (`{ onConflict: "id", ignoreDuplicates: true }`) before the `scans` FK insert. After upserting, the background task calls `setTierCache(userId, "free")` so subsequent warm-isolate requests skip the DB round-trip. `ignoreDuplicates: true` ensures an existing user's `subscription_tier` is never overwritten by the ghost-user path.
11. **Scan Insert**: Calls `supabaseAdmin.from('scans').insert()` using the service role key, binding the scan to the authenticated `user.id`. All environmental telemetry (time of day, month, locale, semantic location, LiDAR depth scale), Google Cloud LLM token metrics (`llm_prompt_tokens`, `llm_candidate_tokens`, `llm_total_tokens` from Gemini's `usageMetadata`), the selected `inference_tier`, `ai_reasoning` (Gemini's 2–4 sentence visual identification justification), and `colors` (1–3 dominant biological colors) are all written in the same insert. `colors` feeds into `semanticTags` on the Swift side for full-text search. `ai_reasoning` is fetched back during historical cloud sync and stored as `LocalScanRecord.aiReasoning`. Note: `group_tags` are stored on `species_dictionary`, not `scans`.
12. **Response format**: Returns `{ success: true, data: { ... } }` to the iOS client via `jsonResponse()`.

## The Webhook Node (`revenuecat-webhook`)

The `revenuecat-webhook` function drives async tier migrations (`pro` ↔ `free`). Because Deno enforces a 10-second processing limit, bulk R2 operations are deferred via `runBackground(task)` from `_shared/edgeHandler.ts`. The webhook secret is validated using `timingSafeCompare()`, a constant-time XOR comparison, rather than plain string equality — this prevents timing attacks. The deferred task queries orphaned `public_uploads/free/` objects from the `scans` table and issues `AWS SDK PUT` copy commands to move them into the `/pro/` bucket. To prevent IDOR attacks on S3 deletes, the function validates that the `originalUserId` parsed from `image_storage_urls` matches the `userId` associated with the webhook trigger.

On `EXPIRATION` (user downgrade), the same process runs in reverse, moving objects from `/pro/` back to `/free/`, returning them to the targeted 90-day domesticated purge cycle.

Before saving `image_storage_urls` to PostgreSQL, the function strips AWS signature query string parameters from the URL to prevent Cloudflare R2 `403 Forbidden` errors when the object key changes. R2 access uses `getR2Config()` from `_shared/aws.ts`.

## The Scientific Export Pipeline (`request-export-dwca` & `export-dwca`)

Researchers export global and personal occurrence data via a two-step queueing architecture that completely bypasses Edge HTTP timeout constraints:

1. **Queue Insertion (`request-export-dwca`)**: The iOS client hits this lightweight proxy, which verifies the user and inserts a job row into the `export_jobs` PostgreSQL queue. To prevent Resend API spam and queue flooding, it enforces a strict **24-hour rate limit** per user. It returns `200 OK` instantly.
2. **Postgres Webhook (`pg_net`)**: The queue insertion fires a native Postgres trigger that posts to `/export-dwca`.
3. **Webhook Worker (`export-dwca`)**: This node receives the job, authenticating via `SUPABASE_SERVICE_ROLE_KEY`. It manages heavy execution:
   - **OOM Streaming**: Uses a `ReadableStream` with AWS `UNSIGNED-PAYLOAD` signatures to stream binary data directly to R2 in chunks, rather than holding a full `JSZip.generateAsync()` blob in the V8 heap.
   - **Cryptographic Geoprivacy**: User IDs are replaced with stable pseudonyms generated via `crypto.subtle.digest` SHA-256 (e.g. `merian_user_a785f2b...`). Scientists can verify user-level streaks without accessing the underlying Supabase token. Exact GPS coordinates are scrubbed for any user data apart from the requesting user.
   - **DaaS Standardization**: Natively maps `life_stage`, `reproductive_condition`, `individual_count`, `estimated_size_cm`, and `ecological_interactions` directly into standard GBIF DwC-A headers (`lifeStage`, `reproductiveCondition`, `individualCount`, etc.).
   - **Asynchronous Delivery**: Once the ZIP reaches R2, it fetches the user's `auth.users` database email and dispatches a secure Resend email containing an expiring `X-Amz-Expires=86400` download link.

## The Edge Moderation Node (`block-user`)

User blocking routes through a dedicated Edge Function to bypass RLS policies that operate on anonymous IDFV boundaries:

1. iOS validates the active Supabase JWT via `SupabaseManager` and attaches it to the request. A missing session throws a `NetworkError` before any API call is made.
2. The `{"blocked_id": "..."}` payload is sent via the REST API. The Edge Function validates the body with `requireParams(body, ["blocked_id"])` from `_shared/validation.ts`, returning `HTTP 400` if the field is absent.
3. `supabaseAdmin.from('user_blocks').insert()` runs with the service role key, bypassing RLS without exposing the table structure to the client.

## Security & Environment Validation

- The `GEMINI_API_KEY` is absent from the iOS client bundle (`Info.plist` and `.xcconfig`). All LLM calls go through the `identify` Edge Function, which holds the key server-side.
- All Edge Functions set `verify_jwt = false` in `config.toml` and perform manual JWT verification via `requireAuth` inside `withEdgeHandler`. This is mandatory: omitting an entry causes Supabase's Kong gateway to default to `verify_jwt = true`, which validates the JWT at the gateway layer before the function code runs and rejects valid ES256 anonymous sessions with `401 Invalid JWT`. The sole exception is `merge-ghost-profile`, which keeps `verify_jwt = true` because it is invoked via the Supabase Swift SDK's `client.functions.invoke()` (which handles JWT attachment at the SDK level) rather than `MerianNetworkClient`'s manual `Authorization` header path.
- **Rule for new Edge Functions**: Every new function directory under `supabase/functions/` MUST have a corresponding `[functions.<name>]` entry with `verify_jwt = false` in `config.toml` before deployment.

## Database Indexing & Performance

`00003_performance_indexes.sql` defines `CREATE INDEX CONCURRENTLY` for the following:

- `idx_species_dict_scientific_name` on `species_dictionary (scientific_name)` — species lookup during inference.
- `idx_scans_user_id` on `scans (user_id)` — user streak queries.
- `idx_scans_discovery_feed` on `scans (geoprivacy, is_live_capture, timestamp DESC)` — global discovery feed fetches.
- `idx_scans_user_species` on `scans (user_id, species_id)` — supports the Postgres trigger computing `COUNT(DISTINCT species_id)`.
- `idx_scans_lifecycle` on `scans (timestamp) WHERE image_storage_urls != '{}'` — scopes the daily storage cleanup cron job to rows that have images, avoiding full-table scans.

`20260324000000_add_historical_sync_index.sql` adds:

- `idx_scans_user_id_timestamp` on `scans (user_id, timestamp DESC)` — compound index added to accelerate paginated historical sync queries issued by `syncHistoricalScansDown`. Without this index, a query of the form `WHERE user_id = $1 ORDER BY timestamp DESC LIMIT n OFFSET m` hits the single-column `idx_scans_user_id`, fetches all rows for that user, then sorts them by `timestamp` in a second pass — O(n log n) per page, O(n² log n) total for large libraries. With the compound index, Postgres can satisfy both the filter and the `ORDER BY` in a single index-only scan, making each page O(page_size) regardless of library size.

## Storage Economics & Lifecycle Syndication

`00004_storage_lifecycle_sync.sql` configures a `pg_cron` job that clears `image_storage_urls` on `subscription_tier = 'free'` rows older than 90 days. It runs at 02:00 UTC daily. The underlying scan row is preserved; only the storage URLs are cleared.

**`get-filtered-discovery-feed`**: Applies `.not("image_storage_urls", "eq", "{}")` to exclude rows with cleared media from public feeds. It also joins `users!inner(is_shadowbanned)` with `.eq("users.is_shadowbanned", false)` to exclude shadowbanned content server-side, since the service role key bypasses RLS. The query uses an explicit column list rather than `select("*")`, omitting telemetry and analytics columns (`device_locale`, `current_month`, `time_of_day`, `depth_scale_text`, `llm_*` token counts, `ai_reasoning`, etc.) that the client never renders. This reduces per-row payload size by approximately 60% at scale.

**Graceful Degradation**: Scans whose R2 media has expired render a `.ultraThinMaterial` glass pane with an `archivebox.fill` icon in `ScansThumbnailView` and `AsyncLocalImageView`, rather than looping on a `ProgressView`.

### Automated 30-Day Non-Biological Purge

The `auto-purge-nonbio` Edge Function, triggered by `pg_cron` via `pg_net`, removes non-biological scans after 30 days. A standard Cloudflare R2 Object Lifecycle rule cannot be used here because R2 lifecycle rules operate on object age and prefix, not on the PostgreSQL `is_biological_subject = false` flag. A bare Postgres `DELETE` without R2 coordination would orphan stored objects. The Edge Function handles both the database deletion and the R2 object removal atomically. Webhook secret validation in this function uses `timingSafeCompare()` for constant-time comparison.

### Targeted 90-Day Domesticated Purge

The `auto-purge-domesticated` Edge Function reclaims heavy storage costs by purging 90-day-old `domesticated` ecology scans from Free tier users without touching valuable `wild` and `invasive` specimens. To safely avoid Deno's wall-clock timeouts when issuing hundreds of network API calls to Cloudflare, the R2 `deleteObjects` requests are batched and executed concurrently using `Promise.all` in chunks of 50. This perfectly balances the V8 event loop against R2's concurrency rate limits. It zeroes out the `image_storage_urls` array rather than dropping the row, ensuring the user's localized text record safely remains in their app gallery.

### Cloudflare R2 Object Lifecycle Rules

The following three Object Lifecycle Rules must be configured in the Cloudflare R2 Dashboard under **Settings → Object Lifecycle**:

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

- **`flag-issue`**: Accepts authenticated POST requests with `scanId`, `flagReason`, and `userSuggestion`.
- **`flagged_reviews` table** (`00005_flagged_reviews.sql`): Stores flagged scan references tied to the reporting `user_id`, defaulting to `PENDING_REVIEW`.
- **`scans` table update**: Sets `is_flagged = true` and writes debug context to `human_intervention_notes` on the parent scan.

## Account Deletion & Data Preservation (`safe-delete`)

Account deletions use the `apply_user_tombstone` PL/pgSQL function (`00006_apply_user_tombstone.sql`). Instead of cascade-deleting scan rows, it reassigns the user's scans to a permanent anonymous tombstone user (`00000000-0000-0000-0000-000000000000`) and sets `is_tombstoned = true`. The original user record and telemetry are then deleted without losing the biological observation data. The tombstone user targets the `current_streak_count` column, not any legacy field.

On `200 OK`, the iOS client calls `supabase.signOut()`, tears down the local SQLite database via `ScanRepository.shared.purgeAllData()`, and clears all cached image files from disk.

## Scan Erasure & The Deletion Pipeline (`delete-scan`)

Individual scan deletion severs the record from both Supabase and Cloudflare R2:

1. **Auth**: JWT is extracted and verified manually. Deletion is locked to the scan's `owner_id`.
2. **R2 Deletion**: The function reads `image_storage_urls` from Supabase. Since these URLs use the public Cloudflare Web domain (`https://media.merian.app/...`), the function rewrites them to the R2 storage domain (`https://<account>.r2.cloudflarestorage.com/<bucket>/...`) before issuing signed `DELETE` requests via `AwsClient` from `aws4fetch`.
3. **Database Erasure**: A `.delete()` call removes the scan row.
4. **Gamification Trigger**: The `decrement_user_species_count()` PL/pgSQL function fires on `AFTER DELETE ON public.scans`. If the deleted scan was the user's last record for that `species_id`, it decrements `users.total_species_discovered` by 1 without going below zero.

#### V8 Execution Abstractions

- **Explicit Deno ES Modules**: To avoid Supabase CLI bundling failures caused by unresolved local import maps, all edge dependencies use direct HTTP module URLs (e.g., `https://esm.sh/@supabase/supabase-js@2.49.1`). The `supabase/functions/deno.json` config includes `"exclude": ["no-import-prefix"]` to suppress the corresponding `deno-lint` warning locally.
- **`_shared` Utilities**: CORS headers, auth validation, `runBackground`, `jsonResponse`, `getR2Config`, `generatePresignedPutUrl`, `_genAI`/`createFlashModel`/`extractJson`, `getTierForUser`/`hasTierCached`/`setTierCache`, and `requireParams` live in `supabase/functions/_shared/`, shared across all function files.
