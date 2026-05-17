# Auto Purge Domesticated

An autonomous cron-worker executing nightly on the Edge. It scans for any captures explicitly classified as `ecology_type = 'domesticated'` (e.g., pets, potted plants) originating from users on the `subscription_tier = 'free'`. When these scans age past `90 days`, the script aggregates their binaries, natively purges the Cloudflare R2 images to reclaim bucket space, and statically blanks the PostgreSQL `image_storage_urls` array natively to reflect the purged state.

Unlike `auto-purge-nonbio`, this script intentionally preserves the original database `.id` and SQL row! Domesticated taxonomy (e.g. dogs or houseplants) can still provide immense user telemetry and offline life-list value; we only intend to reclaim the heavy image footprints, not annihilate the specimen history.

## Architecture

- **`index.ts`**: The strict HTTP Webhook orchestrator. It forces POST verbs, validates the incoming `pg_net` cron execution against a `timingSafeCompare` cryptography block using `SUPABASE_SERVICE_ROLE_KEY`, and aggressively intercepts the `.range()` output. It strips out all URL elements explicitly into a batched array (`mediaToWipe`) and chunks Cloudflare `.deleteR2Objects` HTTP evaluations at `500 keys/request` to avoid violating the strict AWS generic constraint (`Max 1000 objects`).
- **`db.ts`**: Implements the raw `users!inner(...)` PostgREST JOIN allowing Edge to identify free-tier users natively within the SQL bounds natively. It also houses the non-destructive `.update({ image_storage_urls: [] })` blanking operation.
