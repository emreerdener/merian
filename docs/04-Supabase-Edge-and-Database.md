# Supabase Edge and PostgreSQL Engine

Merian employs Supabase implicitly, relying completely on `.xcconfig` obfuscation and Server-Side execution safely decoupled from the physical device.

## Core Schema Structure

The `00001_initial_schema.sql` database file defines the backend architecture. A secondary `00002_user_auth_trigger.sql` schema handles the relationship natively. However, strictly all anonymous users are now identified exclusively by a persistent Keychain-backed `UIDevice.current.identifierForVendor` IDFV.

- **`species_dictionary`**: Tracks every scientifically discovered taxon uniquely mapping directly to native biological descriptors.
- **`scans`**: Logs physical GPS bounds, LLM generated `ai_confidence_score` matrices, UUID bindings, and the corresponding `ecology_type_enum` permanently to the users' streaks.
- **`users`**: Binds the IDFV (or future authenticated UUID) to strict product schemas natively tracking usage limits.

## The Edge Inference Node (`identify`)

The Deno `/identify` edge function acts as the universal proxy masking logic entirely:

1. Receives a structured payload containing the `r2ObjectKey` and environmental constraints (like GPS and Weather) from the iOS native client. Concurrently, it extracts the `user.id` cryptographically from the `Authorization` header JWT via `supabaseAdmin.auth.getUser()`, entirely bypassing IDOR (Insecure Direct Object Reference) vulnerabilities caused by client-side payload spoofing.
2. Generates an `aws4fetch` Stream connecting natively into Cloudflare R2. Rather than downloading into an `ArrayBuffer` (which previously consumed the readable stream entirely, forcing RAM bloat and crashing Google File API limits), it extracts the file size dynamically via `r2Response.headers.get("content-length")` binding it directly to `X-Goog-Upload-Header-Content-Length`. It natively pipes the raw `readableStream` directly into the Google `generativelanguage.googleapis.com/upload/v1beta/files` File API endpoint mapping `duplex: "half"` seamlessly. It then cleanly extracts a `fileUri` to pass into the `.generateContent` context boundary securely bypassing memory crashes natively. Crucially, the Gemini execution is mapped inside a strict `try...finally` block. This guarantees the temporary Google data file is dynamically deleted via a native REST API call explicitly inside the `finally` hook, cleanly preserving physical project quota bytes even if the AI drops an exception or rate-limit.
3. Prompts `gemini-2.5-flash` passing the bytes cleanly using `.generateContent` system instructions demanding `.json` structured mapping boundaries mirroring the expected JSON payload schema constraints. (Note: The `ecology_type` field strictly uses an `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within `SchemaType.STRING` to satisfy Gemini 2.5 constraints without raising a 400 Bad Request.)
4. **Moderation Pipeline (`moderation.ts`)**: Evaluates the explicit Gemini Safety Ratings before any logic fires. Unsafe media throws an exception bounding the user with a `SHADOWBANNED` token intuitively incrementing abuse strikes natively and immediately wiping the R2 media natively.
5. Decodes the taxonomy payload passively. Extracts enriched biological context via Wikipedia and GBIF APIs natively wrapped behind secure `AbortSignal.timeout(2500)` locks. Critically, these enrichments are executed entirely concurrently via `Promise.allSettled()`, cleanly halving edge execution time and gracefully returning metadata immediately back down to iOS. Additionally, Gemini responses are run through a regex (`replace(/```json/gi, '')`) to strip markdown block hallucinations before `JSON.parse` is called to prevent crash-loops.
6. Physically executes a strictly secured `supabaseAdmin.from('species_dictionary').insert()` action. This explicit admin edge execution leverages the backend `SUPABASE_SERVICE_ROLE_KEY` to securely bypass global Row Level Security limits blocking users from vandalizing the biological dictionary table. Hallucinations are actively intercepted dropping non-biological images securely without corrupting the DB physically.
7. Checks if the IDFV `UIDevice` binding UUID natively exists _before_ running moderation validations. If it doesn't, physically `.upsert()`s a Ghost User cleanly preventing SQL Foreign Key crash boundaries natively inside the Deno node gracefully and allowing abuse strikes to track first-time offenders correctly. Critically, this upsert rigidly injects `{ onConflict: "id", ignoreDuplicates: true }` to ensure any existing users who have upgraded to a RevenueCat Pro tier are completely ignored and their `subscription_tier` is not silently wiped back down to `"free"`.
8. Drops smoothly down securely bypassing standard RLS mapping through `supabaseAdmin.from('scans').insert()` to natively bind the scan transaction precisely to the hardware's `user_id` inside the payload.
9. Safely passes the `.json` payload formatted exclusively as a nested `{ success: true, data: { ... } }` array back into the waiting Swift boundary over network lines securely bypassing double-encoded JSON crashes natively.

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
