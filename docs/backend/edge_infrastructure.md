# Deno Edge Infrastructure & Database Ecosystem

Merian utilizes Supabase's hosted PostgreSQL engine alongside globally distributed Deno Edge Functions to prevent application bloat, secure sensitive taxonomic analysis tools, and orchestrate telemetry.

## Edge Nodes (Functions)

- **[`identify`](/supabase/functions/identify/)**: The AI Processing Core.
  - Accepts a transient Gemini File URI (already directly uploaded from the physical iPhone to bypass the Edge payload RAM limit of 15MB).
  - Appends explicit physical weather constraints (WeatherKit), season tags, and LiDAR offsets.
  - Maps directly natively back to a validated JSON biological schema natively conforming to iOS `SpeciesData` rendering expectations.
- **[`generate-upload-urls`](/supabase/functions/generate-upload-urls/)**: Security Abstraction.
  - Takes raw Cloudflare R2 Access Keys from the Supabase Secure Secret Vault and compiles transient AWS S3 v4 "Pre-Signed URLs" (PUT/GET).
  - Pushes these temporary 15-minute URLs physically down to the iOS client so it can securely dump images into Quarantine.
- **[`safe-delete`](/supabase/functions/safe-delete/)**: Garbage Collection.
  - Scans the `pending_storage_deletions` table to physically rip biological telemetry out of the Cloudflare R2 grid complying instantly to European GDPR "Right-to-be-forgotten" laws.
- **[`export-dwca`](/supabase/functions/export-dwca/)**: Academic Extraction.
  - Orchestrates Darwin Core Archive (DwC-A) CSV formats explicitly excluding Domesticated subjects (e.g. houseplants) from physical academic distribution.

## Postgres Row-Level-Security (RLS)

Merian relies heavily natively on `auth.uid()` bindings.

- Physical `scans` table entries map natively to the uuid token.
- **Open Access Layer**: All scans designated with the `geoprivacy = 'open'` enum and `is_live_capture = true` correctly appear naturally via Global Discovery feeds physically bypassing privacy constraints.
- **Restricted**: Any `private` scans natively reject `.select()` operations exclusively unless the HTTP bearer token physically corresponds to the original scanner natively mapping the row.

## The Cloudflare R2 "Quarantine" Cycle

1. Images natively land in a Cloudflare bucket inside a `quarantine/` prefix automatically.
2. The `identify` Edge edge checks explicitly if the image contains explicit/biological safety deviations via Gemini LLMOps thresholds natively.
3. Once clean, the file physically receives a verified tag and allows general Deno `.get()` public distributions.
