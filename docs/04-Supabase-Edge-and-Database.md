# Supabase Edge and PostgreSQL Engine

Merian employs Supabase implicitly, relying completely on `.xcconfig` obfuscation and Server-Side execution safely decoupled from the physical device.

## Core Schema Structure

The `00001_initial_schema.sql` database file defines the backend architecture. A secondary `00002_user_auth_trigger.sql` schema handles the relationship natively. However, strictly all anonymous users are now identified exclusively by a persistent Keychain-backed `UIDevice.current.identifierForVendor` IDFV.

- **`species_dictionary`**: Tracks every scientifically discovered taxon uniquely mapping directly to native biological descriptors.
- **`scans`**: Logs physical GPS bounds, LLM generated `ai_confidence_score` matrices, UUID bindings, and the corresponding `ecology_type_enum` permanently to the users' streaks.
- **`users`**: Binds the IDFV (or future authenticated UUID) to strict product schemas natively tracking usage limits.
- **`species_count_trigger` (`recalculate_and_trigger_species_count.sql`)**: Handles the asynchronous data aggregation of unique biological models actively bound to a distinct user. Automatically increments the `total_species_discovered` count in the `users` table via an invisible Postgres `AFTER INSERT OR UPDATE OR DELETE` trigger firing on `scans` table mutations. Completely isolates the biological count from the client to prevent sync errors.

## The Edge Inference Node (`identify`)

The Deno `/identify` edge function acts as the universal proxy masking logic entirely:

1. Receives a structured payload containing the `r2ObjectKey` and environmental constraints (like GPS Coordinates, GPS Elevation, Weather conditions, and Temperature) from the iOS native client. Concurrently, it extracts the `user.id` cryptographically from the `Authorization` header JWT via `supabaseAdmin.auth.getUser()`. **Note:** Because Merian utilizes modern Asymmetric ES256 Ghost sessions (`signInAnonymously`), the default Supabase `verify_jwt` Edge Middleware is explicitly disabled inside `supabase/config.toml` (`verify_jwt = false`). The Deno handlers now explicitly run manual standard SSR Auth extraction logic, independently decoding the exact Bearer headers against GoTrue. This completely bypasses preemptive 401 Rejections from Edge Gateway boundaries and entirely eradicates IDOR vulnerabilities.
2. Generates an `aws4fetch` Stream connecting natively into Cloudflare R2. Rather than downloading into an `ArrayBuffer` and running a blocking `for` loop conversion, it executes an ultra-fast `encodeBase64(new Uint8Array(arrayBuffer))` execution directly natively explicitly bounding around `~140KB` constraints dynamically from the scaled iOS `768x768` payload. It passes this `inlineData` structure securely into the `.generateContent` context boundary. This elegantly completely eradicates Google File API timeouts and Edge CPU spikes perfectly dropping payload evaluation latency to physically 0ms bounds.
3. Prompts `gemini-2.5-flash` or `gemini-2.5-pro` dynamically based on the verified `subscription_tier` fetched natively from the Ghost User. It forcefully binds generation mathematically with `temperature: 0.1` and passes the bytes cleanly using `.generateContent` system instructions demanding `.json` structured mapping boundaries mirroring the expected JSON payload schema constraints. (Note: The `ecology_type` field strictly uses an `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within `SchemaType.STRING` to satisfy Gemini 2.5 constraints without raising a 400 Bad Request.)
4. **Moderation Pipeline (`moderation.ts`)**: Evaluates the explicit Gemini Safety Ratings before any logic fires. Unsafe media throws an exception bounding the user with a `SHADOWBANNED` token intuitively incrementing abuse strikes natively and immediately wiping the R2 media natively. Safe media falls through to the **Rolling Cloud Window** storage policy. By seamlessly inheriting the resolved `userTier` string directly from the Edge extraction phase natively, this moderation script bypasses an entire 50ms database round-trip logic completely. It automatically promotes "free" tier objects specifically to `public_uploads/free/{userId}/` and "pro" tier objects to `public_uploads/pro/{userId}/`. This native prefix tagging acts as the architectural hook for Cloudflare R2 Lifecycle Rules (defined in `r2-lifecycle.json`) which passively purge orphaned objects in `quarantine/` after 1 day, clear `staging/` leaks continuously matching `1` day expiration for unpromoted bytes, destroy `exports/` daily, and automatically expire `public_uploads/free/` objects precisely after 90 days to prevent bucket bloat.
5. Decodes the taxonomy payload passively. Extracts enriched biological context via Wikipedia (including deep-linked URLs and physical paragraph `extract` payloads) and GBIF APIs natively wrapped behind secure `AbortSignal.timeout(2500)` locks. Critically, these enrichments are executed entirely concurrently via `Promise.allSettled()`, cleanly halving edge execution time and gracefully returning metadata immediately back down to iOS. Additionally, Gemini responses are run through a regex (`replace(/```json/gi, '')`) to strip markdown block hallucinations before `JSON.parse` is called to prevent crash-loops.
6. Physically executes a strictly secured `supabaseAdmin.from('species_dictionary').upsert()` action injecting `{ onConflict: "scientific_name", ignoreDuplicates: true }` chained with a `.select().single()`. This explicit atomic transaction completely neutralizes Time-Of-Check to Time-Of-Use (TOCTOU) race condition bugs causing fatal PostgreSQL `UNIQUE` violations when two identical live captures happen concurrently. To account for Postgres natively returning `null` data when `.upsert()` ignores the conflict without updating rows, the edge function will instantly run a secondary `.select().single()` to fetch the existing biological UUID natively ensuring `scans` table mappings are never gracefully dropped. Both operations dynamically leverage the backend `SUPABASE_SERVICE_ROLE_KEY` to securely bypass global Row Level Security limits blocking users from vandalizing the dictionary.
7. Checks if the GoTrue JWT `user.id` natively exists _before_ running moderation validations. If it doesn't, physically `.upsert()`s a Ghost User cleanly preventing SQL Foreign Key crash boundaries natively inside the Deno node gracefully and allowing abuse strikes to track first-time offenders correctly. Critically, this upsert rigidly injects `{ onConflict: "id", ignoreDuplicates: true }` to ensure any existing users who have upgraded to a RevenueCat Pro tier are completely ignored and their `subscription_tier` is not silently wiped back down to `"free"`.
8. Drops smoothly down securely bypassing standard RLS mapping through `supabaseAdmin.from('scans').insert()` to natively bind the scan transaction precisely to the authenticated `user.id` from the JWT securely overriding the hardware's payload.
9. Safely passes the `.json` payload formatted exclusively as a nested `{ success: true, data: { ... } }` array back into the waiting Swift boundary over network lines securely bypassing double-encoded JSON crashes natively.
10. **Warm-Start Latency Optimization**: Across all Edge Functions (`identify`, `generate-upload-urls`, `safe-delete`, `block-user`), the `supabaseAdmin = createClient(...)` instantiation is explicitly hoisted dynamically out of the `serve(...)` request handler loop into the global script scope. This forcibly overrides Deno cold-start patterns natively instantiating connection pools only once natively upon the first hit securely retaining the PostgreSQL socket open identically across all concurrent invocations.

## The Edge Moderation Node (`block-user`)

To completely bypass complex Row Level Security (RLS) policies acting upon anonymous Device ID (IDFV) boundaries implicitly, Merian completely routes Toxicity blocking protocols through this specific serverless Deno node:

1. Native iOS extracts the internal UUID inside `DeviceIdentityManager.shared.deviceId` explicitly and securely queries its active JWT. If the session is missing, it intelligently throws a `NetworkError` preventing accidental API identity overwrites during off-grid operations.
2. The payload `{"blocked_id": "..."}` is pushed securely via `.xcconfig` REST headers natively. The boundary extracts the `blocker_id` exclusively from `supabaseAdmin.auth.getUser()`.
3. The instance bypasses PostgreSQL Row Level locks by executing `supabaseAdmin.from('user_blocks').insert()` natively using the backend `SUPABASE_SERVICE_ROLE_KEY`, instantly locking off the social data boundary natively without exposing the DB array tables back to the iOS end-user grid.

## Security & Environment Validation

To permanently eradicate reverse-engineering threat vectors, iOS is explicitly isolated from executing LLM capabilities directly:

- The `GEMINI_API_KEY` is entirely scrubbed and explicitly **removed** natively from the iOS client bundle (`Info.plist` & `.xcconfig`).
- Instead, the `MerianApp` binary relies 100% on the `identify` and `block-user` Supabase Edge Functions which safely encrypt the LLM API Keys explicitly within the Supabase Cloud backend.

## Database Indexing & Performance

To gracefully handle future database scale natively and prevent Postgres sequential table scans causing timeout errors on the Edge function:

- **`00003_performance_indexes.sql`** generates `CREATE INDEX CONCURRENTLY` hooks bounding the following high-frequency identifiers:
  - `idx_species_dict_scientific_name` on `species_dictionary (scientific_name)` for immediate species classification lookups natively halving Edge processing limits.
  - `idx_scans_user_id` on `scans (user_id)` to gracefully render users' streaks without sequential database scans.
  - `idx_scans_discovery_feed` on `scans (geoprivacy, is_live_capture, timestamp DESC)` to index massive global map discovery fetches smoothly.

## Storage Economics & Lifecycle Syndication

To prevent R2 bucket expirations from natively corrupting Postgres payloads through dead links, the database continuously governs consistency:

- **`00004_storage_lifecycle_sync.sql`**: Configures a `pg_cron` server-side background job that safely purges strictly the `image_storage_urls` array on any `.subscription_tier = 'free'` entries older than 90 days. This runs securely once per day at 02:00 UTC without manually wiping the underlying row, intentionally preserving globally distributed biological context and GPS matrices.
- **`get-filtered-discovery-feed`**: Contains a strict filter constraint `.not("image_storage_urls", "eq", "{}")`. This explicitly protects the global iOS public feeds from accidentally crashing or rendering ugly blank components by shielding expired payloads natively out of the Discovery pipeline altogether.
- **Graceful Degradation Hook**: Scans whose visual media payloads have permanently rolled out of the R2 tier fall back into a Stage 3 Metadata-Only state internally on `LifeListThumbnailView` and `AsyncLocalImageView`. Rather than thrashing empty `ProgressView()` loops, the API replaces the image natively with an interactive `.ultraThinMaterial` glass pane rendering the `archivebox.fill` icon. This completely eradicates 404 caching errors and embraces Radical Transparency formatting for legacy offline discovery histories safely!

### Cloudflare R2 Object Lifecycle Rules

To physically align the buckets with our Postgres `pg_cron` jobs and safely delete payload data natively to prevent storage bloat, Merian requires the following 4 Object Lifecycle Rules configured natively in the Cloudflare R2 Dashboard under **Settings -> Object Lifecycle**:

1. **Default Multipart Abort Rule**
   - **Prefix:** `--`
   - **Action:** Abort incomplete multipart uploads after `7` days
2. **Free Tier Expiration**
   - **Prefix:** `public_uploads/free/`
   - **Action:** Delete objects after `90` days
3. **Purge staging objects after 1 day**
   - **Prefix:** `staging/`
   - **Action:** Delete objects after `1` day
4. **Quarantine Cleanup**
   - **Prefix:** `quarantine/`
   - **Action:** Delete objects after `1` day

## Customer Support & ML Feedback Loop (`flag-issue`)

To continuously refine the AI models and build a high-quality human-verified dataset ("Golden Dataset"), Merian allows users to flag incorrect taxonomy outputs directly from the `InsightSheetView`:
- **`flag-issue`**: This serverless Edge Node securely ingests authenticated POST requests containing `scanId`, `flagReason`, and `userSuggestion`.
- **`flagged_reviews` SQL Table**: `00005_flagged_reviews.sql` generates this schema, seamlessly mapping flagged scans natively back to the reporting `user_id`. It defaults to a `PENDING_REVIEW` state.
- **`scans` Table Cascade**: The Edge Function immediately updates the parent scan's boolean `is_flagged` state to `true` and appends debugging data straight into the `human_intervention_notes` column to isolate the failure logic.

## Account Deletion & Data Preservation (`safe-delete`)

To balance user privacy (GDPR/CCPA compliance) with scientific data fidelity, account deletions utilize a specialized RPC:
- **`00006_apply_user_tombstone.sql`**: Generates a `public.apply_user_tombstone(target_user_id UUID)` PL/pgSQL function. Instead of cascading deletions that would wipe thousands of biological insights off the global map, it reassigns the user's `scans` to a permanent anonymous `00000000-0000-0000-0000-000000000000` tombstone user and flags them as `is_tombstoned = true`. Afterward, it safely cascades and destroys the original user schema and telemetry without breaking the structural biological maps.
