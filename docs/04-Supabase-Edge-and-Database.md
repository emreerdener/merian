# Supabase Edge and PostgreSQL Engine

Merian employs Supabase implicitly, relying completely on `.xcconfig` obfuscation and Server-Side execution safely decoupled from the physical device.

## Core Schema Structure

The `00001_initial_schema.sql` database file defines the backend architecture. A secondary `00002_user_auth_trigger.sql` schema strictly enforces an `AFTER INSERT` trigger pushing generated `auth.users` UUIDs natively into the `public.users` schema. This resolves foreign key violations natively when saving anonymous "Ghost User" profiles that lack email addresses.

- **`species_dictionary`**: Tracks every scientifically discovered taxon uniquely mapping directly to native biological descriptors.
- **`scans`**: Logs physical GPS bounds, LLM generated `ai_confidence_score` matrices, UUID bindings, and the corresponding `ecology_type_enum` permanently to the users' streaks.
- **`users`**: Binds the Supabase Auth UUID to strict product schemas natively like `subscription_tier` tracking usage limits statically across Apple devices natively.

## The Edge Inference Node (`identify`)

The Deno `/identify` edge function acts as the universal proxy masking logic entirely:

2. Prompts `gemini-2.5-flash` natively using a hyper-optimized `.generateContent` system instruction demanding `.json` structured mapping boundaries directly mirroring the `IdentifyResponse` struct expectations. (Note: The `ecology_type` field strictly uses an `enum: ["wild", "urban", "domesticated", "unknown"]` constraint within `SchemaType.STRING` to satisfy Gemini 2.5 constraints without raising a 400 Bad Request.)
3. Decodes the taxonomy payload passively and physically executes a strictly secured `supabaseAdmin.from('species_dictionary').insert()` action. This explicit admin edge execution leverages the backend `SUPABASE_SERVICE_ROLE_KEY` to securely bypass global Row Level Security limits blocking users from vandalizing the biological dictionary table.
4. Drops back down to the iOS User's JWT permission context uniquely, calling `supabaseClient.from('scans').insert()` to bind the scan permanently to the `user_id` in their personal ledger.
5. Safely passes the `.json` directly back into the waiting Swift boundary over network lines.
