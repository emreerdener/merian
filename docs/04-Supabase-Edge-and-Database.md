# Supabase Edge and PostgreSQL Engine

Merian employs Supabase implicitly, relying completely on `.xcconfig` obfuscation and Server-Side execution safely decoupled from the physical device.

## Core Schema Structure

The `00001_initial_schema.sql` database file defines the backend architecture. A secondary `00002_user_auth_trigger.sql` schema handles the relationship natively. However, strictly all anonymous users are now identified exclusively by a persistent Keychain-backed `UIDevice.current.identifierForVendor` IDFV.

- **`species_dictionary`**: Tracks every scientifically discovered taxon uniquely mapping directly to native biological descriptors.
- **`scans`**: Logs physical GPS bounds, LLM generated `ai_confidence_score` matrices, UUID bindings, and the corresponding `ecology_type_enum` permanently to the users' streaks.
- **`users`**: Binds the IDFV (or future authenticated UUID) to strict product schemas natively tracking usage limits.

## The Edge Inference Node (`identify`)

The Deno `/identify` edge function acts as the universal proxy masking logic entirely:

1. Receives a structured payload containing the `r2ObjectKey` and environmental constraints (like GPS and Weather) from the iOS native client.
2. Generates an `aws4fetch` Stream connecting natively into Cloudflare R2, fetching the full image object. The stream is natively decoded into an `ArrayBuffer` and encoded into Base64 using `deno.land/std/encoding/base64.ts`, completely bypassing V8 string limits and OOM crashes.
3. Prompts `gemini-2.5-flash` passing the bytes cleanly using `.generateContent` system instructions demanding `.json` structured mapping boundaries mirroring the expected JSON payload schema constraints. (Note: The `ecology_type` field strictly uses an `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within `SchemaType.STRING` to satisfy Gemini 2.5 constraints without raising a 400 Bad Request.)
4. **Moderation Pipeline (`moderation.ts`)**: Evaluates the explicit Gemini Safety Ratings before any logic fires. Unsafe media throws an exception bounding the user with a `SHADOWBANNED` token intuitively incrementing abuse strikes natively and immediately wiping the R2 media natively.
5. Decodes the taxonomy payload passively. Extracts enriched biological context via Wikipedia and GBIF APIs natively wrapped behind secure `AbortSignal.timeout(2500)` locks cleanly ignoring 3rd party hangs natively returning payloads fast natively to iOS.
6. Physically executes a strictly secured `supabaseAdmin.from('species_dictionary').insert()` action. This explicit admin edge execution leverages the backend `SUPABASE_SERVICE_ROLE_KEY` to securely bypass global Row Level Security limits blocking users from vandalizing the biological dictionary table. Hallucinations are actively intercepted dropping non-biological images securely without corrupting the DB physically.
7. Checks if the IDFV `UIDevice` binding UUID natively exists. If it doesn't, physically `.upsert()`s a Ghost User cleanly preventing SQL Foreign Key crash boundaries natively inside the Deno node gracefully.
8. Drops smoothly down securely bypassing standard RLS mapping through `supabaseAdmin.from('scans').insert()` to natively bind the scan transaction precisely to the hardware's `user_id` inside the payload.
9. Safely passes the `.json` payload formatted exclusively as a nested `{ success: true, data: { ... } }` array back into the waiting Swift boundary over network lines securely bypassing double-encoded JSON crashes natively.
