# Domain-Driven Edge Architecture

Naturebook's proxy backend executes exclusively via Deno Edge Functions managed
locally by Supabase CLI. Because Deno isolates strict V8 256MB memory limits and
10-second wall-clock API constraints, the functions must be built with
aggressive scaling bounds.

Historically, Edge Functions were single-file monoliths (`index.ts`). Merian has
been structurally refactored into a **Domain-Driven Modular Architecture**.

_Any new Edge Function created within `services/supabase/functions/` MUST adhere
to the following file-bound separations natively._

## 1. The HTTP Orchestrator (`index.ts`)

The `index.ts` file operates structurally as the "Router". Its singular purpose
is orchestrating networking flow, executing security validation, and gracefully
exiting the process.

**Rules for `index.ts`:**

- **No Native PostgreSQL SQL Strings:** You may not execute `.select()`,
  `.insert()`, `.delete()` directly from the Supabase SDK client inside
  `index.ts`. All database networking must be offloaded to `db.ts`.
- **Aggressive Input Validation:** All payloads must be manually verified using
  `requireParams` pulled natively from `_shared/http.ts`.
- **IDOR Protections:** Direct `user.id` bounding must be evaluated inside
  `index.ts` before allowing `db.ts` to proceed.
- **Async Detachment:** Heavy I/O processing operations matching
  `EdgeRuntime.waitUntil(...)` from `_shared/edgeHandler.ts` are initialized
  here strictly after returning the native HTTP `200 OK` response.
- **Native Deno Serving:** Use `Deno.serve(...)` directly in Edge entrypoints.
  Do not import `serve` from `https://deno.land/std/.../http/server.ts`; every
  remote runtime import becomes a deploy-time graph fetch for every function.

## 2. The PostgreSQL Layer (`db.ts`)

The `db.ts` file acts as the isolated boundary for PostgREST executions. This
encapsulates your data schemas, query configurations, pagination filters, and
relational constraints securely away from your proxy layer.

**Rules for `db.ts`:**

- **Strict Typing:** All Postgres responses must be typed manually or via
  generic Supabase generation bounds (e.g.,
  `export interface DBScanRow { id: string }`). Do not allow `any` typings to
  bubble backwards up to `index.ts`.
- **Query Memory Guards:** To natively defend against Deno V8 memory exhaustion,
  queries pulling arrays (`image_storage_urls`) must mathematically bound
  themselves via `.limit(500)` memory fences inherently within `db.ts` natively.
- **Error Propagation:** All Supabase `{ data, error }` tuples must explicitly
  `throw new Error()` back to the `index.ts` orchestrator rather than attempting
  to return generic `null` responses natively.
- **Complete Field Coverage in Insert Types:** `ScanInsertRow` (and equivalent
  insert interfaces in other functions) must include **every** AI-returned and
  telemetry field that maps to a DB column. Missing a field silently applies the
  column's Postgres `DEFAULT` (e.g., `is_live_capture` defaults to `true` —
  omitting it from `ScanInsertRow` caused all gallery/screen scans to be
  incorrectly flagged as live captures). When adding a new Gemini output field,
  always trace it through `types.ts` → `index.ts` payload → `db.ts` insert
  interface → SQL column in the same PR.

## 3. The API Interfaces (`types.ts`)

The `types.ts` script ensures explicit DTO (Data Transfer Object) mapping parity
directly linking the Swift iOS front-end structs with the Deno V8 isolates
natively.

**Rules for `types.ts`:**

- **Exact Field Matching:** Interface keys must perfectly align with the JSON
  decoder keys evaluated directly inside `InferenceEdgeDTOs.swift`.
- **Oversharing Defense:** Only declare fields strictly consumed by the
  frontend; do not dump generic Postgres wildcard `*` objects out locally to the
  client natively.

**Current key additions (as of V34):**

- `_shared/identify/types.ts`: `ClientPayload` includes
  `alternative_common_names?: string[] | null`; `CachedSpeciesRow` includes
  `alternative_common_names: string[] | null` to mirror `species_dictionary`.
- `enrich-scan/types.ts`: `CachedSpeciesData` includes
  `alternative_common_names: string[] | null`; read by `getCachedSpecies` and
  conditionally written by `updateSpeciesEnrichment`.
- `insight-chat/`: follows the same `index.ts` / `db.ts` / `types.ts` split and
  adds `prompt.ts` for text-only Gemini chat context plus AI quick-prompt
  generation, and `guards.ts` for action, limit, entitlement, prompt-suggestion,
  and deterministic safety checks.
- `field-trips/`: follows the same `index.ts` / `db.ts` split. `index.ts`
  validates the action payload, user identity, UUIDs, cursor pairs, pin arrays,
  habitat tags, comment lengths, and optional preferred-goal pair; `db.ts` is
  the only layer that calls the
  Field trip RPCs and publication/comment tables. The endpoint is intentionally
  action-based because the Field trips endpoint serves catalog, template detail, explicit
  start, Community publications, Recent compatibility, profile pins, scan
  progress, private scan contributions, publication detail, likes, and comments
  from one Field trips-native
  surface without extending Explore feed functions. Catalog/detail can project
  the verified viewer's private `completed_scan_id` through service-role-only
  RPCs; `db.ts` must not copy that field into capture context, public profile,
  publication/challenge, or Explore projections.
- The identify and enrich-scan `db.ts` files include `alternative_common_names`
  in their `SPECIES_SELECT`/select strings and upsert/update payloads. Any new
  column added to `species_dictionary` that is served to the client must be
  added to all four of these locations simultaneously.

## 4. Threshold Constants (`thresholds.ts`)

`services/supabase/functions/_shared/identify/thresholds.ts` is the **canonical
source of truth** for confidence threshold values used across the `identify`
pipeline:

```typescript
export const FLASH_STRONG = 0.95;
export const FLASH_DIAGNOSTIC_TRIGGER = 0.99;
export const PRO_STRONG = 0.85;
export const PRO_DIAGNOSTIC_TRIGGER = 0.99;
export function diagnosticTriggerForTier(tier: "pro" | "flash"): number;
```

`identify/index.ts`, `identify-multimodal/index.ts`, and
`identify-describe/index.ts` import `diagnosticTriggerForTier` from this file so
the candidate-strip gate cannot drift across inference entry points. The iOS
client mirrors these in `MerianConfig.flashConfidence` and
`MerianConfig.proConfidence`; comments in that file point back to
`thresholds.ts` as the source of truth. Any threshold change must be applied in
both places.

## 5. Auxiliary Streams (`storage.ts`, `mail.ts`, `media.ts`, `moderation.ts`)

For exceptionally heavy or bespoke routing streams that violate the 10-second
Deno isolate timeout window, operations must be cordoned off into
domain-specific streams explicitly executed via `runBackground`.

- **`storage.ts`**: Handles heavy `AWS` bindings via native `aws4fetch`. When
  streaming multimegabyte binaries directly into Cloudflare R2, implementations
  like `JSZip` must pipe their outputs efficiently into a `ReadableStream`
  natively chunked into S3 without overloading memory buffers.
- **`_shared/aws.ts`**: Shared Cloudflare R2 helpers. Pre-signed PUT generation
  accepts an explicit `Content-Type`; callers must sign image and audio uploads
  with the same header the client will send. The scan-media reconciliation
  worker uses the shared HEAD/copy/delete helpers to distinguish uploaded
  staging objects from signed-but-never-uploaded rows.
- **`_shared/encoding.ts`**: Local base64 and hex helpers for runtime code. Use
  this instead of importing Deno std encoding modules in deployed functions.
- **`_shared/mediaBudgets.ts`**: Shared media budget and safety checks. Edge
  functions must use this module for endpoint JSON body ceilings, audio clip
  count, inline base64 length, raw byte limits, staged R2 ownership/path
  traversal, allowed staging content types, and `Content-Length` prechecks
  before parsing media bodies or allocating ArrayBuffers. The staging-file cap
  is six so a video scan can sign five sampled inference frames plus one
  playback clip while image, audio, and video sub-limits remain enforced.
  `Content-Length` is only a fast reject: request JSON and R2/HTTP response
  bodies must still flow through `readRequestJsonWithinBudget`,
  `readResponseArrayBufferWithinBudget`, or `readStreamArrayBufferWithinBudget`
  so missing-length and chunked bodies are counted while streaming. Do not
  reintroduce raw `req.json()` or `response.arrayBuffer()` in media-bearing Edge
  handlers.
- **`_shared/concurrency.ts`**: Shared bounded fanout helper. Use
  `mapWithConcurrencyLimit(items, width, fn)` when a handler needs many outbound
  calls but must preserve result order and cap in-flight work. The default APNs
  send path uses width `8`; other call sites should document any wider limit.
- **`_shared/scanMediaAssets.ts`**: Shared scan-media lifecycle helpers.
  `/generate-upload-urls` creates staged upload-session rows for scan media,
  with `scan_id` null until a final scan row exists. `identify-multimodal` marks
  those rows promoted/deleted/failed during finalization, and
  `reconcile-scan-media-assets` repairs or garbage-collects stale staged rows.
  The helpers can recover upload-session ids for a scan's staged media so the
  ingestion ledger can bind retries to the same upload session. Write paths make
  best-effort `refreshScanMediaAssets(...)` calls after scan inserts or video
  repair updates. Composer/status readers prefer ready display/playback
  `scan_media_assets` rows before falling back to `captured_media` and legacy
  media arrays. `scan-media-health` and the scheduled monitor read this
  lifecycle state for operational drift detection without mutating media.
- **`_shared/scanIngestionJobs.ts`**: Shared scan-ingestion lifecycle helpers.
  `identify-multimodal` claims a job with expected media counts, staged object
  keys, upload-session ids, and a normalized manifest checksum; status and
  reconciliation paths use that row as the server-side source of truth for
  in-flight, retryable, completed, and terminal media persistence.
- **`_shared/scanIngestionIntents.ts` /
  `_shared/scanIngestionCompatibility.ts`**: Shared sanitized replay-intent
  helpers. `identify-multimodal` writes `scan_ingestion_intents` with telemetry,
  observation context, media descriptors, staged object keys, upload-session
  ids, and payload checksums, while redacting inline base64 media and marking
  those intents non-resumable. Compatibility scan-producing endpoints
  (`identify`, `identify-describe`, and `audio-spec`) use
  `scanIngestionCompatibility.ts` to claim the same job/intent ledger and shape
  staged image/audio or text-only requests as multimodal replay payloads.
  `replay-scan-ingestion` consumes only resumable staged media/audio/video or
  text-only intents and dispatches them back through the existing multimodal
  endpoint. Replay is capped at 10 claims per sanitized intent; exhausted rows
  become `failed_terminal / server_replay_limit_reached`.

**Structured error logging (`_shared/edgeHandler.ts`)**: In addition to
`withEdgeHandler` and `runBackground`, `edgeHandler.ts` exports
`logStructuredError(event, details)`. This emits
`JSON.stringify({ event, ts, ...details })` to `console.error`. All Edge
Functions must use `logStructuredError` for alertable operational failures (e.g.
post-auth partial deletion, DB write failures that produce false-success
responses) rather than plain `console.error` strings. Structured log lines are
machine-parseable and can trigger alerting pipelines on the ops side.

- **`mail.ts`**: Aggregates 3rd-party SaaS integrations like the `Resend` Node
  SDK for transactional email delivery.
- **`_shared/identify/media.ts`**: Resolves inference media for the Gemini
  calls. Image handling covers R2 key validation, serial R2 reads to avoid heap
  spikes, and `imageBase64s` direct pass-through with size validation. Video
  inference is represented as ordered sampled image frames plus
  `visualMediaItems` metadata; the staged `.mp4` is the upload-bounded playback
  artifact for persistence/sharing and is not sent to Gemini. The client
  normally stages a compressed 720p export, with an original-file fallback only
  when it stays within the hard video byte cap. For video captures, durable
  playback video promotion is a success gate: `identify-multimodal` must promote
  every requested `videoR2ObjectKey` and persist both `video_storage_urls` and a
  video `captured_media` item before returning success; upload-session rows are
  finalized before ready playback rows in `scan_media_assets` are refreshed by
  the DB trigger plus a best-effort Edge refresh call. When the iOS client
  extracts audio from a video clip, that Int16 PCM WAV travels through the same
  audio path with `audioMediaItems` metadata marking it as `video_audio`. Audio
  handling covers inline `audioBase64s` decode guards and staged
  `audioR2ObjectKeys` R2 reads through one shared `resolveAudioBuffers(...)`
  path. Shared by `identify`, `identify-multimodal`, and `audio-spec`.
- **Audio payload rule**: `identify-multimodal` accepts queued audio as
  `audioR2ObjectKeys` and live audio as `audioBase64s`; `audio-spec` accepts one
  staged or inline audio payload. Both endpoints must reject oversized declared
  `Content-Length` request bodies before parsing, then use
  `readRequestJsonWithinBudget` as the authoritative body cap for
  chunked/missing-length JSON. Clip count, base64 length, raw byte length, IDOR
  ownership, and path traversal stay delegated to `_shared/mediaBudgets.ts` /
  `_shared/identify/media.ts` before decode/fetch. Staged audio is an inference
  input and must be deleted after successful ingestion.
- **`_shared/identify/clientPayload.ts`**: Normalizes cache-hit response
  hydration so `identify` and `identify-multimodal` return the same cached
  taxonomy, hazard, habitat, IUCN, GBIF, and synonym fields.
- **`_shared/identify/subjectClassification.ts`**: Normalizes parsed model
  output before biological gates run. Shared by `identify`,
  `identify-multimodal`, and `identify-describe` so processed/manufactured
  materials cannot drift into `species_dictionary` through one route while
  another route blocks them.
- **`_shared/identify/moderation.ts`**: Evaluates Gemini safety ratings, manages
  abuse strikes, and promotes safe media from `staging/` to `public_uploads/` in
  Cloudflare R2. Always runs inside `runBackground` — never on the critical HTTP
  path. Shared by `identify` and `identify-multimodal`. See
  [Safety & Moderation](../development-guides/10-safety-and-moderation.md) for
  the full pipeline specification.

## Architectural Unification

By explicitly decoupling Data mapping from HTTP orchestration natively, the Deno
backend becomes immediately immune to traditional Node.JS monolith
"spaghetti-code" scaling failures. Engineers can formally upgrade complex
PostgREST schemas in `db.ts` without jeopardizing the critical
`timingSafeCompare` JWT block natively inside `index.ts`.

All shared primitives natively driving API functions (`aws.ts`, `biology.ts`,
`concurrency.ts`, `encoding.ts`, `http.ts`, `mediaBudgets.ts`, `posthog.ts`,
`tierCache.ts`) are stored in `services/supabase/functions/_shared/`. For
guidelines regarding the global dependencies, refer directly to
`_shared/README.md`.

**Deploy Dependency Rule — Use Generated Function-Local Deno Configs:** Runtime
Edge code resolves third-party packages through aliases owned by
`services/supabase/functions/deno.json`. That root file is the reviewed source
manifest; `sync_function_deno_configs.ts` copies its import map into every
deployable function's local `deno.json`, and each local config points at the
shared frozen `functions/dependencies.lock`. This matches Supabase's
function-directory config discovery and avoids relying on a parent config that
the remote bundler may not apply. Do not pass the retired `--import-map` flag.
Use exact npm pins behind aliases for packages such as `aws4fetch`, `jszip`,
`@google/genai`, and `@supabase/supabase-js`; production graphs must not contain
direct esm.sh, deno.land, npm, or JSR specifiers. Test-only Deno std assert
imports remain acceptable because they are not bundled into production
functions.

The entire fleet uses one exact `@supabase/supabase-js@2.110.6` dependency.
`_shared/claimsAuth.ts` is still imported only by latency-sensitive routes, but
that isolation protects authentication semantics rather than carrying a second
SDK: the universal `edgeHandler.ts` retains the established Auth-server
`getUser` policy while opted-in routes use cached-JWKS `getClaims` validation.
CI rejects stale generated configs, lock drift, direct runtime specifiers, and
missing or stale `[functions.<name>]` configuration entries.

**PostHog Rule — Fire-and-Forget:** All `trackPostHogEvent(...)` calls in
**all** Edge Functions and `_shared/biology.ts` **must not be `await`-ed**.
Analytics are best-effort and must never add latency to the critical path or the
background ingestion flow. The correct pattern is:

```typescript
trackPostHogEvent(user, "EventName", { ...props }).catch((e) =>
  console.error("PostHog EventName failed:", e)
);
```

**PostgREST Join Rule — Never Use Wildcard Embeds:**
`select("related_table(*)")` fetches every column in the joined table, including
large text blobs, on every row and every page. Always enumerate only the columns
the downstream type actually decodes. Example — `enrich-scan` fetching
lookalikes:

```typescript
// ✗ BAD — fetches all species_dictionary columns
.select("lookalike_id, species_dictionary(*)")

// ✓ GOOD — single embedded join, only decoded fields, unambiguous FK hint
.from("species_lookalikes")
.select("lookalike:species_dictionary!lookalike_id(id, scientific_name, common_names, reference_image_url, iucn_red_list_status)")
.eq("species_id", speciesId)
```

The embedded join syntax resolves two sequential PostgREST round-trips (the old
N+1 `SELECT id → SELECT IN (ids)` pattern) into a single SQL JOIN, cutting
connection-pool acquisitions and Deno isolate latency in half. Public thumbnail
URLs now prefer a second batched lookup against `species_reference_images` keyed
by the hydrated IDs, with `species_dictionary.reference_image_url` kept as the
fallback cache.

**PostgREST FK Disambiguation Rule — Always Use `table!column` Hint on Multi-FK
Tables:** When a join table has two foreign keys that both reference the same
target table, PostgREST cannot determine which FK to follow and returns an
ambiguous-relationship error at runtime. The alias-only shorthand
`"alias:column(fields)"` is insufficient in this case. Always use the full
`"alias:table!column(fields)"` hint to specify both the target table and the FK
column:

```typescript
// ✗ AMBIGUOUS — species_lookalikes has two FKs to species_dictionary;
//               PostgREST cannot determine which one to follow
.select("lookalike:lookalike_id(scientific_name, ...)")

// ✓ UNAMBIGUOUS — explicit table!column hint resolves the correct FK
.select("lookalike:species_dictionary!lookalike_id(scientific_name, ...)")
```

The `species_lookalikes` table (`species_id` and `lookalike_id`, both
referencing `species_dictionary`) is the canonical example. Any future join
table with self-referential or dual-FK relationships to the same table requires
this pattern.

**First-Scan Replication-Lag Rule — Return Raw Flash Names When `speciesId` Is
Null:** When a species is scanned for the first time, `identify` creates a new
`species_dictionary` row in the background task. If
`enrich-scan?scope=lookalikes` fires before that row has propagated to the
Supabase read replica, `getCachedSpecies()` returns `null` and `speciesId` is
`null`. In that case `fetchLookalikesFromJoinTable` and
`resolveLookalikesToJoinTable` are both skipped (they require a `speciesId`). To
prevent `similar_species: null` being returned to the client on the first scan
of every new species, `enrich-scan/index.ts` maps the raw
`SimilarSpeciesEntry[]` from Flash directly to `LookalikeSummary[]` (with
`reference_image_url: null` and `iucn_red_list_status: null`) when `speciesId`
is null but Flash returned results:

```typescript
} else {
  // Replication lag on first scan — return raw Flash names so the client is not left with null.
  lookalikes = similarResult.similar_species.map((e) => ({
    scientific_name: e.scientific_name,
    common_name: e.common_name,
    reference_image_url: null,
    iucn_red_list_status: null,
  }));
}
```

The `SimilarSpeciesGallery` renders these entries immediately (scientific +
common names visible); `SimilarSpeciesImageFetcher` fills in card images via the
Wikipedia/GBIF waterfall. On the next `enrich-scan` call for the same species
(once the row is visible on the replica), `speciesId` resolves normally and the
join table is populated with full data.

**`resolveLookalikesToJoinTable` Null Kingdom Early-Exit:** If `primaryKingdom`
is `null` or `undefined` when `resolveLookalikesToJoinTable` is called, the
function returns the Flash-generated entries as stubs immediately without
writing anything to the `species_lookalikes` join table. Previously, all
lookalike entries passed through unvalidated when no kingdom was available,
risking cross-kingdom contamination in the join table. This early-exit ensures
that kingdom-less enrichment paths (e.g., a very recently inserted species row
not yet replicated) produce a safe, read-only response.

**TEXT[] Fallback Rule — Always Return Scientific Names When Join Table
Resolution Fails:** `resolveLookalikesToJoinTable` may return entries for
species already in `species_dictionary`, plus Flash-generated stubs for species
not yet in the dictionary. However, `formatEnrichmentPayload` applies a
secondary TEXT[] fallback in case the resolution returns completely empty (e.g.
speciesId is null, or the function threw and was caught upstream):

```typescript
const resolvedLookalikes: LookalikeSummary[] = lookalikes.length > 0
  ? lookalikes
  : (cachedSpecies?.similar_species ?? []).map((name) => ({
    scientific_name: name,
    common_name: null,
    reference_image_url: null,
    iucn_red_list_status: null,
  }));
```

This guarantees that clients always receive at least the scientific names rather
than `similar_species: null`. Note that `resolveLookalikesToJoinTable` itself
now handles the "no dictionary matches" case by returning Flash-generated stubs
directly (with `common_name` populated from the Flash response), so this
fallback is a last-resort safety net rather than the primary path for unmatched
species.

**Resolve-and-Return Pattern:** Functions that write to a join table and then
need the hydrated rows should return the resolved species rows directly instead
of re-fetching the join table after the write. This eliminates a redundant third
round-trip on migration or LLM-completion paths. See
`resolveLookalikesToJoinTable` in `enrich-scan/db.ts` for the reference
implementation: the `species_dictionary` query that resolves names to IDs is
expanded to also fetch the hydration columns, and the mapped
`LookalikeSummary[]` is returned directly to the caller. A supplementary batched
`species_reference_images` lookup is allowed for normalized media because image
rows live in a separate table and are keyed by the already-resolved IDs.

**Public Species Projection Rule:** Any endpoint that returns reusable
species-level public data should route its mapping through
`_shared/publicSpeciesProjection.ts` or an equivalent SQL helper. This keeps
common-name fallback, reference-image source mapping, nullable taxonomy shape,
and private-field exclusions consistent across `/species-dictionary`,
`/enrich-scan` lookalikes, Explore detail similar species, and the public web
species mapper. Tests in `_shared/publicSpeciesProjection_test.ts` must fail if scan
IDs, user IDs, field notes, coordinates, AI reasoning, or preference fields leak
into a public species projection.

**Public Species Refresh Rule:** Internal refresh work must consume
`species_enrichment_jobs` or the legacy
`public.get_species_content_refresh_queue(...)` instead of scanning
`species_dictionary` directly. The shipped `refresh-species-content` worker
updates GBIF/Wikipedia-backed fields and writes fresh
`species_content_provenance` rows; `refresh-species-model-content` owns habitat,
lookalikes, and group tags. Common-name overrides, conservation, and hazard data
remain curation-owned. Reference-image refreshes must use
`public.replace_species_reference_images(...)` so normalized media rows stay
aligned while existing rights metadata is preserved.

**`fetchSimilarSpecies` Returns `SimilarSpeciesEntry[]` — Taxonomy-Grounded Name
Pairs:** `fetchSimilarSpecies` in `_shared/biology.ts` accepts an optional
`SpeciesTaxonomy` parameter (`{ kingdom, class, order, family }`). When provided
(always from the `enrich-scan` path, sourced from `cachedSpecies`), the taxonomy
is injected into both the system instruction and user message. The instruction
explicitly forbids cross-kingdom results ("never suggest plants as lookalikes
for animals"). The Flash model generates `{ scientific_name, common_name }`
pairs in one call at negligible extra token cost. The common name flows through
`resolveLookalikesToJoinTable` in three ways:

1. **Dictionary match — runtime**: `LookalikeSummary.common_name` is populated
   as `dictionary_value ?? flash_value ?? null` — so even species that exist in
   `species_dictionary` without a `common_names.en` entry return a name
   immediately.
2. **Dictionary match — persistent back-fill**: For species whose `common_names`
   column is entirely `NULL` (e.g. added to the dictionary via the enrichment
   path, never directly scanned), `resolveLookalikesToJoinTable` upserts
   `{ en: flash_common_name }` into `species_dictionary`. This ensures all
   future `fetchLookalikesFromJoinTable` calls return a populated name without
   re-running the Flash call.
3. **No dictionary match — Flash stub**: For lookalike species that have never
   been scanned and have no `species_dictionary` row,
   `resolveLookalikesToJoinTable` now appends them as `LookalikeSummary` stubs
   with `common_name` from Flash and `reference_image_url: null`. The client
   falls back to the `SimilarSpeciesImageFetcher` (Wikipedia / iNaturalist REST)
   for thumbnail images when `referenceImageUrl` is null. Previously these
   species were silently dropped, causing common names to disappear for any
   lookalike not yet in the dictionary.

The migration path in `index.ts` converts legacy `TEXT[]` entries to
`SimilarSpeciesEntry[]` with `common_name: null` before calling
`resolveLookalikesToJoinTable` — the back-fill step will still fire for any
matched dictionary rows whose column is null, even without a Flash-generated
name in the entry.

**`resolveLookalikesToJoinTable` Return Type (`enrich-scan/db.ts`)**: The
function returns `{ lookalikes: LookalikeSummary[]; persisted: boolean }`
(exported interface: `ResolveResult`) rather than a bare `LookalikeSummary[]`.
`persisted` is `true` only when rows were successfully written to the
`species_lookalikes` join table. Early-exit paths — null kingdom, empty
dictionary match, all-failed kingdom validation — return `persisted: false`.
Both call sites in `enrich-scan/index.ts` destructure
`{ lookalikes, persisted }`.

**`hasLookalikes` Gate — Common Name Presence + Flash Attempt Flag:** The
`hasLookalikes` guard in `enrich-scan/index.ts` is:

```typescript
const hasLookalikes = lookalikes.some((l) => l.common_name !== null) ||
  cachedSpecies?.lookalikes_flash_attempted === true;
```

Two conditions, either of which skips Flash:

1. **`lookalikes.some(...)`**: at least one entry has a known common name — the
   species is enriched.
2. **`lookalikes_flash_attempted`**: Flash was previously attempted for this
   species and returned all-null common names. This covers legitimately obscure
   lookalike species (e.g. rare subspecies, newly described taxa) that have no
   widely-recognised English common name. Without this flag, `.some()` would
   never become true and Flash would re-run on every `enrich-scan` call
   indefinitely, wasting tokens without ever resolving a name.

`lookalikes_flash_attempted` (`BOOLEAN NOT NULL DEFAULT false` on
`species_dictionary`) is set to `true` in `index.ts` after a Flash-sourced
`resolveLookalikesToJoinTable` call completes — **only when
`persisted === true`**. This is a critical guard: the flag must not be written
when the join-table write was skipped (e.g., the null-kingdom early-exit).
Previously the flag was written unconditionally after the function returned,
permanently locking out future Flash retries for species whose enrichment was
skipped due to replication lag. Setting the flag only on a confirmed join-table
write ensures those species are retried on the next `enrich-scan` call. The flag
is also **not** set by the legacy TEXT[] migration path (which passes
`common_name: null` for all entries) so that species with legacy-only data still
trigger Flash at least once.

**Recovery query for species incorrectly flagged before this guard was added**
(covers both the empty-array case and the null-kingdom early-exit case — both
result in the flag being set without any join-table rows):

```sql
UPDATE species_dictionary
SET lookalikes_flash_attempted = false
WHERE lookalikes_flash_attempted = true
  AND id NOT IN (SELECT DISTINCT species_id FROM species_lookalikes);
```

This resets only species where the flag was set but no join-table rows were ever
written, allowing the next `enrich-scan` call to retry Flash.

**`merge_common_name_en_batch` RPC — Batch Locale-Safe Common Name Back-fill:**
`resolveLookalikesToJoinTable` back-fills English common names for matched
`species_dictionary` rows that have a Flash-generated name but no existing
`"en"` key. This uses
`supabaseAdmin.rpc("merge_common_name_en_batch", { p_updates: [...] })` — a
single Postgres round-trip that processes all back-fill candidates atomically
via `jsonb_array_elements`.

The previous implementation called
`supabaseAdmin.rpc("merge_common_name_en", ...)` once per species via
`Promise.allSettled`, which fired N parallel connections from the same V8
isolate. The batch RPC reduces this to exactly 1 pgBouncer connection
acquisition regardless of the number of back-fill candidates (up to 3 lookalike
species per enrichment call).

The RPC uses
`COALESCE(common_names, '{}') || jsonb_build_object('en', p_en_name)` to merge
only the `"en"` key, preserving all other locale entries (`"fr"`, `"de"`, etc.).
The function's `NOT (common_names ? 'en')` WHERE guard makes each row update a
safe no-op if `"en"` was already populated by a concurrent request. The RPC is
`SECURITY DEFINER` so it can write to `species_dictionary` without requiring the
anon role to have a direct UPDATE policy.

The back-fill fires for any matched dictionary row where:

- Flash returned a non-null common name for that species, AND
- The row has no `"en"` key (covers `NULL`, `{}`, and partial-locale objects
  like `{"fr": "..."}`)

This enables the `common_names` column to serve as an ever-growing locale
dictionary per species. When a French user base is added, a
`merge_common_name_locale(p_id, p_locale, p_name)` generalisation of the same
pattern can back-fill `"fr"` entries — or GBIF's `species/{id}/vernacularNames`
endpoint (already fetched for `gbif_taxon_key`) can populate multiple locales in
a single enrichment pass.

The single-species `merge_common_name_en(p_id uuid, p_en_name text)` RPC
(migration `20260330170000`) is preserved for any direct callers outside
`resolveLookalikesToJoinTable`. `resolveLookalikesToJoinTable` exclusively uses
the batch variant (migration `20260330180000`).

**`species_lookalikes` Index — O(log N) Fetch Path:** The UNIQUE constraint on
`(species_id, lookalike_id)` required by the upsert in
`resolveLookalikesToJoinTable` creates a composite index. PostgREST's
`.eq("species_id", speciesId)` in `fetchLookalikesFromJoinTable` may not
efficiently use this composite index at large table sizes depending on the
Postgres planner's cost estimates. A dedicated single-column index
`idx_species_lookalikes_species_id ON species_lookalikes(species_id)` (migration
`20260330190000`) guarantees an O(log N) index scan on the fetch path
independent of table cardinality, without affecting the upsert's conflict
detection which continues to use the composite unique index.

**`enrich-scan` Scoped API — Concurrent Progressive Enrichment:**
`enrich-scan/index.ts` accepts a required `scope` parameter (`"enrichment"` |
`"lookalikes"`). Each scope handles an independent sub-problem and returns only
its own fields:

| Scope          | Fields returned                                     | Flash call                    |
| -------------- | --------------------------------------------------- | ----------------------------- |
| `"enrichment"` | `habitat_description`, `gbif_taxon_key`, `taxonomy` | `fetchStaticEncyclopedicData` |
| `"lookalikes"` | `similar_species`                                   | `fetchSimilarSpecies`         |

The iOS client fires both scopes concurrently via `withTaskGroup` in
`InferenceEngine.fetchAndApplyEnrichment`. Each task group child applies its
fields to `speciesData` as soon as its network call resolves — habitat
description and taxonomy appear independently of similar species cards. Two
separate `@Observable` flags gate their respective loading states:

- `isEnrichmentLoading` — gates the habitat/distribution skeleton in
  `HabitatAndDistributionCard`
- `isLookalikesLoading` — gates the similar species gallery skeleton in
  `BiologicalView`

On a **cache hit** (species already enriched) each scoped call returns after a
single DB round-trip — no behavioral latency difference from the pre-split
design. On a **cold path** the two Flash calls run in parallel Deno isolate
fanout rather than sequentially, so the first resolved scope reaches the client
before the second Flash call completes.

The historic load path (`load(from:)`) computes `needsMetadata` and
`needsLookalikes` separately and forwards them as arguments so only the missing
scope is requested:

```swift
let needsMetadata  = record.habitatDescription == nil || record.gbifTaxonKey == nil
let needsLookalikes = record.lookalikesData == nil || lookalikesHaveNoCommonNames
await fetchAndApplyEnrichment(modelContext:, needsMetadata:, needsLookalikes:)
```

**`EdgeRuntime.waitUntil` for Post-Response Writes (`enrich-scan/index.ts`):**
Each scope defers its `updateSpeciesEnrichment` / `lookalikes_flash_attempted`
write via `EdgeRuntime.waitUntil(...)`. The response payload is fully formed
before either write begins; the client does not need to wait for them. Deferring
these writes removes ~40–60 ms of cumulative Postgres round-trip time from the
cold-path response latency.

**`updateSpeciesEnrichment` Error Visibility:** `updateSpeciesEnrichment` issues
multiple persist operations via `Promise.allSettled`. It inspects every settled
result and calls `console.error` for any rejected promise, making individual
field-write failures visible in Deno edge logs without aborting the other
persist operations. This follows the `Promise.allSettled` pattern mandated for
background writes — a single rejected upsert (e.g., a transient Postgres
timeout) no longer silently swallows the error.

Rule: Any `db.ts` write that is not required to build the response payload
**must** be deferred with `EdgeRuntime.waitUntil`. The
`lookalikes_flash_attempted` flag update and the `updateSpeciesEnrichment` call
are the canonical examples.

**Strategic Thinking Budget Rule — `@google/genai@1.0.0`:** `thinkingConfig` is
a first-class typed field in `@google/genai@1.0.0` (the SDK pinned in
`deno.json`). No cast is needed and `thinkingBudget` is reliably honoured at
runtime. Budgets are set strategically per call type:

| Call site                                                 | `thinkingBudget` | Rationale                                                                                                                                            |
| --------------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `createFlashModel` (encyclopedic, lookalikes, group tags) | `0`              | Deterministic schema-constrained JSON lookups — no visual ambiguity, thinking tokens add latency with no accuracy benefit                            |
| `identify` Flash vision (`gemini-2.5-flash`)              | `2,048`          | Raised from 1,024 after production data showed complex/invasive species hitting 99% utilisation; 2,048 covers observed worst-case with headroom      |
| `identify` Pro vision (`gemini-2.5-pro`)                  | `5,000`          | Covers the hardest observed cases (fossil discrimination, rare cultivars, look-alike subspecies) where extended reasoning directly improves accuracy |

The `@google/genai@1.0.0` SDK exposes `thoughtsTokenCount` in `UsageMetadata`,
making thinking token consumption observable in Edge Function logs. The
`identify` function logs all four counters on every scan:

```
Token Usage [identify | <tier>]: Prompt: X | Candidates: Y | Thinking: Z | Total: W
```

`llm_thinking_tokens` is also forwarded in scan-completion PostHog events for
cost analytics. Multimodal video scans additionally forward `media_type`,
image/video/audio counts, and `video_llm_*_tokens`; those video token fields
mirror the full Gemini request usage because the provider does not split token
counts by sampled video frame or accompanying audio segment. The vision model
call uses `_genAI.models.generateContent()` (not the deprecated
`getGenerativeModel` pattern), with `thinkingConfig` passed inside the `config`
object alongside `systemInstruction`, `temperature`, and `maxOutputTokens`.

## 2026-04 Hardening Updates

- Telemetry-context building, month normalization, and life-stage /
  reproductive-condition / sex clamping now live in
  `_shared/identify/context.ts` and are reused by `identify`,
  `identify-describe`, `identify-multimodal`, and `audio-spec`.
- The WAV preprocessing pipeline is now centralized in
  `_shared/audioProcessing.ts`; `audio-spec` and `identify-multimodal` no longer
  carry two divergent copies of the same decode/trim/resample/encode logic.
- Media request body ceilings, image R2 key validation, and audio buffer
  resolution now live in `_shared/mediaBudgets.ts` and
  `_shared/identify/media.ts`; inference entrypoints should not hand-roll
  `Content-Length`, base64, path traversal, or staged-audio fetch checks.
- Explore interaction handlers now reuse `_shared/http.parseJsonBody`, reducing
  repeated request-body parsing scaffolding while keeping UUID validation and
  domain checks local to the Explore boundary.

## 2026-05 Shared Identify Rule

- Shared orchestration across `identify`, `identify-multimodal`,
  `identify-describe`, and `audio-spec` must live under
  `services/supabase/functions/_shared/identify/` only when the domain purpose
  is identical.
- Keep modality-specific request DTOs, response DTOs, and validation isolated in
  each function. Do not merge them behind conditional flags just to reduce line
  count.
- Candidate enrichment, group-tag resolution, and post-classification helpers
  are safe to share when they consume and produce the same shape. If a helper
  needs modality branching to stay correct, keep that logic local to the
  function.
- Subject-boundary helpers must run before `isIdentifiedBio` or dictionary
  upserts. A processed-material demotion must clear source-species scientific
  names, candidates, biological metadata, and dictionary novelty in every route
  that can produce scan results.
