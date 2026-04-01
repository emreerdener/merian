# Domain-Driven Edge Architecture

Merian's proxy backend executes exclusively via Deno Edge Functions managed locally by Supabase CLI. Because Deno isolates strict V8 256MB memory limits and 10-second wall-clock API constraints, the functions must be built with aggressive scaling bounds.

Historically, Edge Functions were single-file monoliths (`index.ts`). Merian has been structurally refactored into a **Domain-Driven Modular Architecture**. 

_Any new Edge Function created within `supabase/functions/` MUST adhere to the following file-bound separations natively._

## 1. The HTTP Orchestrator (`index.ts`)

The `index.ts` file operates structurally as the "Router". Its singular purpose is orchestrating networking flow, executing security validation, and gracefully exiting the process.

**Rules for `index.ts`:**
- **No Native PostgreSQL SQL Strings:** You may not execute `.select()`, `.insert()`, `.delete()` directly from the Supabase SDK client inside `index.ts`. All database networking must be offloaded to `db.ts`.
- **Aggressive Input Validation:** All payloads must be manually verified using `requireParams` pulled natively from `_shared/http.ts`.
- **IDOR Protections:** Direct `user.id` bounding must be evaluated inside `index.ts` before allowing `db.ts` to proceed.
- **Async Detachment:** Heavy I/O processing operations matching `EdgeRuntime.waitUntil(...)` from `_shared/edgeHandler.ts` are initialized here strictly after returning the native HTTP `200 OK` response.

## 2. The PostgreSQL Layer (`db.ts`)

The `db.ts` file acts as the isolated boundary for PostgREST executions. This encapsulates your data schemas, query configurations, pagination filters, and relational constraints securely away from your proxy layer.

**Rules for `db.ts`:**
- **Strict Typing:** All Postgres responses must be typed manually or via generic Supabase generation bounds (e.g., `export interface DBScanRow { id: string }`). Do not allow `any` typings to bubble backwards up to `index.ts`.
- **Query Memory Guards:** To natively defend against Deno V8 memory exhaustion, queries pulling arrays (`image_storage_urls`) must mathematically bound themselves via `.limit(500)` memory fences inherently within `db.ts` natively.
- **Error Propagation:** All Supabase `{ data, error }` tuples must explicitly `throw new Error()` back to the `index.ts` orchestrator rather than attempting to return generic `null` responses natively.
- **Complete Field Coverage in Insert Types:** `ScanInsertRow` (and equivalent insert interfaces in other functions) must include **every** AI-returned and telemetry field that maps to a DB column. Missing a field silently applies the column's Postgres `DEFAULT` (e.g., `is_live_capture` defaults to `true` — omitting it from `ScanInsertRow` caused all gallery/screen scans to be incorrectly flagged as live captures). When adding a new Gemini output field, always trace it through `types.ts` → `index.ts` payload → `db.ts` insert interface → SQL column in the same PR.

## 3. The API Interfaces (`types.ts`)

The `types.ts` script ensures explicit DTO (Data Transfer Object) mapping parity directly linking the Swift iOS front-end structs with the Deno V8 isolates natively.

**Rules for `types.ts`:**
- **Exact Field Matching:** Interface keys must perfectly align with the JSON decoder keys evaluated directly inside `InferenceEdgeDTOs.swift`.
- **Oversharing Defense:** Only declare fields strictly consumed by the frontend; do not dump generic Postgres wildcard `*` objects out locally to the client natively. 

## 4. Auxiliary Streams (`storage.ts`, `mail.ts`, `media.ts`, `moderation.ts`)

For exceptionally heavy or bespoke routing streams that violate the 10-second Deno isolate timeout window, operations must be cordoned off into domain-specific streams explicitly executed via `runBackground`.

- **`storage.ts`**: Handles heavy `AWS` bindings via native `aws4fetch`. When streaming multimegabyte binaries directly into Cloudflare R2, implementations like `JSZip` must pipe their outputs efficiently into a `ReadableStream` natively chunked into S3 without overloading memory buffers.
- **`mail.ts`**: Aggregates 3rd-party SaaS integrations like the `Resend` Node SDK for transactional email delivery.
- **`media.ts`** (`identify/` only): Resolves the image payload for the Gemini vision call. Handles two paths — R2 key fetch (downloads staging objects serially to avoid heap spikes) and `imageBase64s` direct pass-through (validates size limits). Extracted from `index.ts` to keep the HTTP orchestrator lean and to isolate the heap-safety logic for independent testing.
- **`moderation.ts`** (`identify/` only): Evaluates Gemini safety ratings, manages abuse strikes, and promotes safe media from `staging/` to `public_uploads/` in Cloudflare R2. Always runs inside `runBackground` — never on the critical HTTP path. See [Safety & Moderation](../development-guides/10-safety-and-moderation.md) for the full pipeline specification.

## Architectural Unification

By explicitly decoupling Data mapping from HTTP orchestration natively, the Deno backend becomes immediately immune to traditional Node.JS monolith "spaghetti-code" scaling failures. Engineers can formally upgrade complex PostgREST schemas in `db.ts` without jeopardizing the critical `timingSafeCompare` JWT block natively inside `index.ts`.

All shared primitives natively driving API functions (`aws.ts`, `biology.ts`, `http.ts`, `posthog.ts`, `tierCache.ts`) are stored in `supabase/functions/_shared/`. For guidelines regarding the global dependencies, refer directly to `_shared/README.md`.

**PostHog Rule — Fire-and-Forget:** All `trackPostHogEvent(...)` calls in **all** Edge Functions and `_shared/biology.ts` **must not be `await`-ed**. Analytics are best-effort and must never add latency to the critical path or the background ingestion flow. The correct pattern is:
```typescript
trackPostHogEvent(user, "EventName", { ...props }).catch((e) =>
  console.error("PostHog EventName failed:", e)
);
```

**PostgREST Join Rule — Never Use Wildcard Embeds:** `select("related_table(*)")` fetches every column in the joined table, including large text blobs, on every row and every page. Always enumerate only the columns the downstream type actually decodes. Example — `enrich-scan` fetching lookalikes:
```typescript
// ✗ BAD — fetches all species_dictionary columns
.select("lookalike_id, species_dictionary(*)")

// ✓ GOOD — single embedded join, only decoded fields, unambiguous FK hint
.from("species_lookalikes")
.select("lookalike:species_dictionary!lookalike_id(scientific_name, common_names, reference_image_url, iucn_red_list_status)")
.eq("species_id", speciesId)
```
The embedded join syntax resolves two sequential PostgREST round-trips (the old N+1 `SELECT id → SELECT IN (ids)` pattern) into a single SQL JOIN, cutting connection-pool acquisitions and Deno isolate latency in half.

**PostgREST FK Disambiguation Rule — Always Use `table!column` Hint on Multi-FK Tables:** When a join table has two foreign keys that both reference the same target table, PostgREST cannot determine which FK to follow and returns an ambiguous-relationship error at runtime. The alias-only shorthand `"alias:column(fields)"` is insufficient in this case. Always use the full `"alias:table!column(fields)"` hint to specify both the target table and the FK column:
```typescript
// ✗ AMBIGUOUS — species_lookalikes has two FKs to species_dictionary;
//               PostgREST cannot determine which one to follow
.select("lookalike:lookalike_id(scientific_name, ...)")

// ✓ UNAMBIGUOUS — explicit table!column hint resolves the correct FK
.select("lookalike:species_dictionary!lookalike_id(scientific_name, ...)")
```
The `species_lookalikes` table (`species_id` and `lookalike_id`, both referencing `species_dictionary`) is the canonical example. Any future join table with self-referential or dual-FK relationships to the same table requires this pattern.

**TEXT[] Fallback Rule — Always Return Scientific Names When Join Table Resolution Fails:** `resolveLookalikesToJoinTable` may return entries for species already in `species_dictionary`, plus Flash-generated stubs for species not yet in the dictionary. However, `formatEnrichmentPayload` applies a secondary TEXT[] fallback in case the resolution returns completely empty (e.g. speciesId is null, or the function threw and was caught upstream):
```typescript
const resolvedLookalikes: LookalikeSummary[] =
  lookalikes.length > 0
    ? lookalikes
    : (cachedSpecies?.similar_species ?? []).map((name) => ({
        scientific_name: name,
        common_name: null,
        reference_image_url: null,
        iucn_red_list_status: null,
      }));
```
This guarantees that clients always receive at least the scientific names rather than `similar_species: null`. Note that `resolveLookalikesToJoinTable` itself now handles the "no dictionary matches" case by returning Flash-generated stubs directly (with `common_name` populated from the Flash response), so this fallback is a last-resort safety net rather than the primary path for unmatched species.

**Resolve-and-Return Pattern:** Functions that write to a join table and then need the hydrated rows must return the result directly from the write query — never call a separate fetch function after the write. This eliminates a redundant third round-trip on migration or LLM-completion paths. See `resolveLookalikesToJoinTable` in `enrich-scan/db.ts` for the reference implementation: the `species_dictionary` query that resolves names to IDs is expanded to also fetch the hydration columns, and the mapped `LookalikeSummary[]` is returned directly to the caller.

**`fetchSimilarSpecies` Returns `SimilarSpeciesEntry[]` — Taxonomy-Grounded Name Pairs:** `fetchSimilarSpecies` in `_shared/biology.ts` accepts an optional `SpeciesTaxonomy` parameter (`{ kingdom, class, order, family }`). When provided (always from the `enrich-scan` path, sourced from `cachedSpecies`), the taxonomy is injected into both the system instruction and user message. The instruction explicitly forbids cross-kingdom results ("never suggest plants as lookalikes for animals"). The Flash model generates `{ scientific_name, common_name }` pairs in one call at negligible extra token cost. The common name flows through `resolveLookalikesToJoinTable` in three ways:
1. **Dictionary match — runtime**: `LookalikeSummary.common_name` is populated as `dictionary_value ?? flash_value ?? null` — so even species that exist in `species_dictionary` without a `common_names.en` entry return a name immediately.
2. **Dictionary match — persistent back-fill**: For species whose `common_names` column is entirely `NULL` (e.g. added to the dictionary via the enrichment path, never directly scanned), `resolveLookalikesToJoinTable` upserts `{ en: flash_common_name }` into `species_dictionary`. This ensures all future `fetchLookalikesFromJoinTable` calls return a populated name without re-running the Flash call.
3. **No dictionary match — Flash stub**: For lookalike species that have never been scanned and have no `species_dictionary` row, `resolveLookalikesToJoinTable` now appends them as `LookalikeSummary` stubs with `common_name` from Flash and `reference_image_url: null`. The client falls back to the `SimilarSpeciesImageFetcher` (Wikipedia / iNaturalist REST) for thumbnail images when `referenceImageUrl` is null. Previously these species were silently dropped, causing common names to disappear for any lookalike not yet in the dictionary.

The migration path in `index.ts` converts legacy `TEXT[]` entries to `SimilarSpeciesEntry[]` with `common_name: null` before calling `resolveLookalikesToJoinTable` — the back-fill step will still fire for any matched dictionary rows whose column is null, even without a Flash-generated name in the entry.

**`hasLookalikes` Gate — Common Name Presence + Flash Attempt Flag:** The `hasLookalikes` guard in `enrich-scan/index.ts` is:
```typescript
const hasLookalikes =
  lookalikes.some((l) => l.common_name !== null) ||
  cachedSpecies?.lookalikes_flash_attempted === true;
```
Two conditions, either of which skips Flash:
1. **`lookalikes.some(...)`**: at least one entry has a known common name — the species is enriched.
2. **`lookalikes_flash_attempted`**: Flash was previously attempted for this species and returned all-null common names. This covers legitimately obscure lookalike species (e.g. rare subspecies, newly described taxa) that have no widely-recognised English common name. Without this flag, `.some()` would never become true and Flash would re-run on every `enrich-scan` call indefinitely, wasting tokens without ever resolving a name.

`lookalikes_flash_attempted` (`BOOLEAN NOT NULL DEFAULT false` on `species_dictionary`) is set to `true` in `index.ts` after a Flash-sourced `resolveLookalikesToJoinTable` call completes — **only when `lookalikes.length > 0`**. This is a critical guard: Flash can return `similar_species: []` (an empty array) for species it does not recognise (e.g. hybrid cultivars, newly described taxa with no well-known confusables). In JavaScript, `[]` is truthy, so the outer `if (similarResult?.similar_species && speciesId)` block fires regardless. Without the `lookalikes.length > 0` check the flag would be written after every empty-array response, permanently locking out future Flash retries for that species and causing similar-species cards to never appear. It is **not** set by the legacy TEXT[] migration path (which passes `common_name: null` for all entries) so that species with legacy-only data still trigger Flash at least once.

**Recovery query for species incorrectly flagged before this guard was added:**
```sql
UPDATE species_dictionary
SET lookalikes_flash_attempted = false
WHERE lookalikes_flash_attempted = true
  AND id NOT IN (SELECT DISTINCT species_id FROM species_lookalikes);
```
This resets only species where the flag was set but no join-table rows were ever written, allowing the next `enrich-scan` call to retry Flash.

**`merge_common_name_en_batch` RPC — Batch Locale-Safe Common Name Back-fill:** `resolveLookalikesToJoinTable` back-fills English common names for matched `species_dictionary` rows that have a Flash-generated name but no existing `"en"` key. This uses `supabaseAdmin.rpc("merge_common_name_en_batch", { p_updates: [...] })` — a single Postgres round-trip that processes all back-fill candidates atomically via `jsonb_array_elements`.

The previous implementation called `supabaseAdmin.rpc("merge_common_name_en", ...)` once per species via `Promise.allSettled`, which fired N parallel connections from the same V8 isolate. The batch RPC reduces this to exactly 1 pgBouncer connection acquisition regardless of the number of back-fill candidates (up to 3 lookalike species per enrichment call).

The RPC uses `COALESCE(common_names, '{}') || jsonb_build_object('en', p_en_name)` to merge only the `"en"` key, preserving all other locale entries (`"fr"`, `"de"`, etc.). The function's `NOT (common_names ? 'en')` WHERE guard makes each row update a safe no-op if `"en"` was already populated by a concurrent request. The RPC is `SECURITY DEFINER` so it can write to `species_dictionary` without requiring the anon role to have a direct UPDATE policy.

The back-fill fires for any matched dictionary row where:
- Flash returned a non-null common name for that species, AND
- The row has no `"en"` key (covers `NULL`, `{}`, and partial-locale objects like `{"fr": "..."}`)

This enables the `common_names` column to serve as an ever-growing locale dictionary per species. When a French user base is added, a `merge_common_name_locale(p_id, p_locale, p_name)` generalisation of the same pattern can back-fill `"fr"` entries — or GBIF's `species/{id}/vernacularNames` endpoint (already fetched for `gbif_taxon_key`) can populate multiple locales in a single enrichment pass.

The single-species `merge_common_name_en(p_id uuid, p_en_name text)` RPC (migration `20260330170000`) is preserved for any direct callers outside `resolveLookalikesToJoinTable`. `resolveLookalikesToJoinTable` exclusively uses the batch variant (migration `20260330180000`).

**`species_lookalikes` Index — O(log N) Fetch Path:** The UNIQUE constraint on `(species_id, lookalike_id)` required by the upsert in `resolveLookalikesToJoinTable` creates a composite index. PostgREST's `.eq("species_id", speciesId)` in `fetchLookalikesFromJoinTable` may not efficiently use this composite index at large table sizes depending on the Postgres planner's cost estimates. A dedicated single-column index `idx_species_lookalikes_species_id ON species_lookalikes(species_id)` (migration `20260330190000`) guarantees an O(log N) index scan on the fetch path independent of table cardinality, without affecting the upsert's conflict detection which continues to use the composite unique index.

**`enrich-scan` Scoped API — Concurrent Progressive Enrichment:** `enrich-scan/index.ts` accepts a required `scope` parameter (`"enrichment"` | `"lookalikes"`). Each scope handles an independent sub-problem and returns only its own fields:

| Scope | Fields returned | Flash call |
|---|---|---|
| `"enrichment"` | `habitat_description`, `gbif_taxon_key`, `taxonomy` | `fetchStaticEncyclopedicData` |
| `"lookalikes"` | `similar_species` | `fetchSimilarSpecies` |

The iOS client fires both scopes concurrently via `withTaskGroup` in `InferenceEngine.fetchAndApplyEnrichment`. Each task group child applies its fields to `speciesData` as soon as its network call resolves — habitat description and taxonomy appear independently of similar species cards. Two separate `@Observable` flags gate their respective loading states:
- `isEnrichmentLoading` — gates the habitat/distribution skeleton in `HabitatAndDistributionCard`
- `isLookalikesLoading` — gates the similar species gallery skeleton in `BiologicalView`

On a **cache hit** (species already enriched) each scoped call returns after a single DB round-trip — no behavioral latency difference from the pre-split design. On a **cold path** the two Flash calls run in parallel Deno isolate fanout rather than sequentially, so the first resolved scope reaches the client before the second Flash call completes.

The historic load path (`load(from:)`) computes `needsMetadata` and `needsLookalikes` separately and forwards them as arguments so only the missing scope is requested:
```swift
let needsMetadata  = record.habitatDescription == nil || record.gbifTaxonKey == nil
let needsLookalikes = record.lookalikesData == nil || lookalikesHaveNoCommonNames
await fetchAndApplyEnrichment(modelContext:, needsMetadata:, needsLookalikes:)
```

**`EdgeRuntime.waitUntil` for Post-Response Writes (`enrich-scan/index.ts`):** Each scope defers its `updateSpeciesEnrichment` / `lookalikes_flash_attempted` write via `EdgeRuntime.waitUntil(...)`. The response payload is fully formed before either write begins; the client does not need to wait for them. Deferring these writes removes ~40–60 ms of cumulative Postgres round-trip time from the cold-path response latency.

Rule: Any `db.ts` write that is not required to build the response payload **must** be deferred with `EdgeRuntime.waitUntil`. The `lookalikes_flash_attempted` flag update and the `updateSpeciesEnrichment` call are the canonical examples.

**Gemini Flash `thinkingBudget: 0` Rule — Disable Thinking Tokens on Structured-Output Tasks:** All calls to `createFlashModel` (in `_shared/gemini.ts`) pass `thinkingConfig: { thinkingBudget: 0 }`. Gemini 2.5 Flash thinking tokens add ~2–4 s of latency with no accuracy benefit for deterministic, schema-constrained JSON generation tasks (enrichment extraction, lookalike resolution, etc.). Because `thinkingConfig` is not yet a typed field in the SDK version pinned in `_shared/gemini.ts`, it is cast via `as unknown as GenerationConfig`. Do not remove this cast — it is intentional.

```typescript
generationConfig: {
  temperature: 0.1,
  maxOutputTokens,
  thinkingConfig: { thinkingBudget: 0 },
} as unknown as GenerationConfig,
```

This rule applies only to `createFlashModel`. The vision model in `identify/index.ts` (which uses `_genAI.getGenerativeModel` directly) is **not** affected — multi-modal reasoning may benefit from thinking tokens on ambiguous species images.
