# Auto Purge Non-Bio

An autonomous background worker hooked into the `pg_net` Cron orchestrator. It executes on a scheduled interval to detect stale captures (`timestamp < 30 days`) where `is_biological_subject = false`. It structurally pulls the R2 binaries out of Cloudflare and cascadingly deletes the Postgres row, maintaining a clean cloud footprint for failed ecology detections.

## Architecture

To enforce clean routing boundaries, the logic is decoupled:

- **`index.ts`**: The strict HTTP orchestrator. It blocks non-POST verbs and intercepts the `SUPABASE_SERVICE_ROLE_KEY` Authorization payload via explicit `timingSafeCompare` math from `_shared/security.ts` to block timing attacks attempting to derive API key lengths. It coordinates the date math parsing, extracts the URLs manually, fires `.deleteR2Objects` directly across the Cloudflare bucket using `AwsClient`, and natively wipes the database IDs.
- **`db.ts`**: Houses the strict PostgREST `.limit(500)` pagination boundary necessary to pull candidates without breaking the Deno V8 Isolate memory limits. Also houses the `.delete().in("id", ...)` batch destroyer.
