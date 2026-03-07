# Supabase Edge and PostgreSQL Engine

Merian employs Supabase implicitly, relying completely on `.xcconfig` obfuscation and Server-Side execution safely decoupled from the physical device.

## Core Schema Structure

The `00001_initial_schema.sql` database file defines the backend architecture.

- **`species_dictionary`**: Tracks every scientifically discovered taxon uniquely mapping directly to native biological descriptors.
- **`scans`**: Logs physical GPS bounds, LLM generated `ai_confidence_score` matrices, UUID bindings, and the corresponding `ecology_type_enum` permanently to the users' streaks.
- **`users`**: Binds the Supabase Auth UUID to strict product schemas natively like `subscription_tier` tracking usage limits statically across Apple devices natively.

## The Edge Inference Node (`identify`)

The Deno `/identify` edge function acts as the universal proxy masking logic entirely:

1. Validates dynamic payloads securely.
2. Prompts `gemini-1.5-flash` natively using a hyper-optimized `.generateContent` system instruction demanding `.json` structured mapping boundaries directly mirroring the `IdentifyResponse` struct expectations.
3. Decodes the taxonomy payload passively and physically executes `supabaseClient.from('species_dictionary').insert()` capturing identical dictionaries.
4. Executes `supabaseClient.from('scans').insert()` binding the identity permanently to the `user.id`.
5. Safely passes the `.json` directly back into the waiting Swift boundary over network lines.
