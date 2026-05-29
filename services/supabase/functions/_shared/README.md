# `_shared` Directory

The `_shared` repository contains the core abstraction domains that power
Merian's globally isolated Deno Edge Functions.

Rather than fragmenting logic recursively through every function directory, the
shared dependencies are grouped by domain. Keep new shared code here only when
multiple functions need the same behavior and the ownership boundary is clear.

## Infrastructure Map

- **`edgeHandler.ts`**: Authenticated user-facing function wrapper, preflight
  handling, background task dispatch, and structured operational logging.
- **`http.ts`**: CORS headers, JSON responses, parameter validation, JSON-body
  parsing, body-size checks, and constant-time comparison helpers.
- **`auth.ts`**: Supabase user/session validation helpers.
- **`aws.ts`**: Cloudflare R2/S3-compatible presigned upload, object fetch, and
  batch deletion helpers. `deleteR2Objects` uses `mapWithConcurrencyLimit`
  internally so lifecycle workers do not run unbounded delete fanout. Prefix
  helpers classify `staging/`, `quarantine/`, and `exports/` as temporary,
  `public_uploads/free|pro/` as scan media, and `avatars/` as durable profile
  media. Scan purge flows must use `deleteScanMediaR2Objects(...)`; avatar
  replacement must use `deleteAvatarR2Object(...)` with the owning user ID.
- **`mediaBudgets.ts`**: Shared media byte ceilings, allowed staging content
  types, inline/staged audio and image validation, clip-count limits, and
  `Content-Length` prechecks. Request and response bodies that may be chunked or
  omit `Content-Length` must be consumed through `readRequestJsonWithinBudget`,
  `readResponseArrayBufferWithinBudget`, or `readStreamArrayBufferWithinBudget`
  so the byte counter rejects oversized streams before V8 can allocate past the
  Edge heap budget.
- **`concurrency.ts`**: Ordered promise mapping with a fixed worker width. Use
  `mapWithConcurrencyLimit` for fanout work such as APNs delivery or remote
  object operations where unbounded `Promise.all(...)` could spike sockets,
  heap, provider throttles, or Postgres writes.
- **`audioProcessing.ts`**: Shared WAV decode/trim/resample/encode pipeline used
  by `audio-spec` and `identify-multimodal`.
- **`external.ts`**: Wikipedia and GBIF enrichment helpers used by identify,
  enrichment, species refresh, and dictionary paths.
- **`gemini.ts`**: Global `GoogleGenAI` client setup plus structured-output and
  JSON extraction helpers.
- **`biology.ts`**: Shared structured biological generation helpers retained for
  functions that still need text-only ecological generation.
- **`posthog.ts`**: Best-effort PostHog HTTP capture helpers.
- **`tierCache.ts`**: Short-lived user-tier resolver/cache to avoid repeated
  Supabase lookups inside hot Edge paths. Exposes both the compatibility
  `getTierForUser(...)` helper and the richer `resolveTierForUser(...)` contract
  used by scan telemetry: `effective_tier`, `plan`, `subscription_tier`,
  `trial_active`, and `user_exists`.
- **`explore.ts`**: Explore UUID/hashtag validation, public author identity
  sync, feed-card hashtag/pro-badge/username hydration, and shared
  social-surface helpers.
- **`publicSpeciesProjection.ts`**: Public species projection sanitizer that
  prevents private scan/user fields from leaking into dictionary and Explore
  responses.
- **`speciesContentProvenance.ts`**: Provenance mapping for scheduled species
  content refresh outputs.
- **`taxonomy.ts`**: Taxonomic normalization helpers and test-backed taxonomy
  transformations.

## Identify Subdomain

`_shared/identify/` is the shared inference stack used by `identify`,
`identify-multimodal`, `identify-describe`, and `audio-spec` where behavior is
identical:

- **`clientPayload.ts`**: Cache-hit payload hydration shared by identify
  endpoints.
- **`context.ts`**: Telemetry context normalization, month/time handling, and
  ecological field clamping.
- **`db.ts`**: Scan insert/update helpers, species cache writes, and shared
  database boundaries.
- **`media.ts`**: Image/audio media resolution from inline payloads and R2
  staging keys.
- **`moderation.ts`**: Gemini safety evaluation, abuse strikes, and safe media
  promotion.
- **`schema.ts`**: Gemini response schema definitions.
- **`thresholds.ts`**: Tier-specific confidence thresholds mirrored by
  `MerianConfig`.
- **`types.ts`**: Shared TypeScript DTOs for the identify family.
