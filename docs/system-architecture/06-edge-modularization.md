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

## 4. Auxiliary Streams (`storage.ts` & `mail.ts`)

For exceptionally heavy or bespoke routing streams that violate the 10-second Deno isolate timeout window, operations must be cordoned off into domain-specific streams explicitly executed via `runBackground`.

- **`storage.ts`**: Handles heavy `AWS` bindings via native `aws4fetch`. When streaming multimegabyte binaries directly into Cloudflare R2, implementations like `JSZip` must pipe their outputs efficiently into a `ReadableStream` natively chunked into S3 without overloading memory buffers.
- **`mail.ts`**: Aggregates 3rd-party SaaS integrations like the `Resend` Node SDK for transactional email delivery.

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

**`fetchSimilarSpecies` Returns `SimilarSpeciesEntry[]` — Scientific Name + Common Name Pairs:** `fetchSimilarSpecies` in `_shared/biology.ts` returns structured objects `{ scientific_name, common_name }` rather than bare scientific name strings. The Flash model generates both fields in one call at negligible extra token cost. The common name flows through `resolveLookalikesToJoinTable` in three ways:
1. **Dictionary match — runtime**: `LookalikeSummary.common_name` is populated as `dictionary_value ?? flash_value ?? null` — so even species that exist in `species_dictionary` without a `common_names.en` entry return a name immediately.
2. **Dictionary match — persistent back-fill**: For species whose `common_names` column is entirely `NULL` (e.g. added to the dictionary via the enrichment path, never directly scanned), `resolveLookalikesToJoinTable` upserts `{ en: flash_common_name }` into `species_dictionary`. This ensures all future `fetchLookalikesFromJoinTable` calls return a populated name without re-running the Flash call.
3. **No dictionary match — Flash stub**: For lookalike species that have never been scanned and have no `species_dictionary` row, `resolveLookalikesToJoinTable` now appends them as `LookalikeSummary` stubs with `common_name` from Flash and `reference_image_url: null`. The client falls back to the `SimilarSpeciesImageFetcher` (Wikipedia / iNaturalist REST) for thumbnail images when `referenceImageUrl` is null. Previously these species were silently dropped, causing common names to disappear for any lookalike not yet in the dictionary.

The migration path in `index.ts` converts legacy `TEXT[]` entries to `SimilarSpeciesEntry[]` with `common_name: null` before calling `resolveLookalikesToJoinTable` — the back-fill step will still fire for any matched dictionary rows whose column is null, even without a Flash-generated name in the entry.

**`hasLookalikes` Gate — Require at Least One Non-Null Common Name:** The `hasLookalikes` guard in `enrich-scan/index.ts` is defined as `lookalikes.some((l) => l.common_name !== null)`, not `lookalikes.length > 0`. Join table rows from the migration path can have `common_name: null` for every entry when `species_dictionary.common_names` was null at migration time. Using `.length > 0` would treat these as fully enriched and skip the Flash call, leaving all common names permanently null. The `.some(...)` gate ensures Flash re-runs and `resolveLookalikesToJoinTable` back-fills the dictionary whenever all existing entries lack a common name.

**Gemini Flash `thinkingBudget: 0` Rule — Disable Thinking Tokens on Structured-Output Tasks:** All calls to `createFlashModel` (in `_shared/gemini.ts`) pass `thinkingConfig: { thinkingBudget: 0 }`. Gemini 2.5 Flash thinking tokens add ~2–4 s of latency with no accuracy benefit for deterministic, schema-constrained JSON generation tasks (enrichment extraction, lookalike resolution, etc.). Because `thinkingConfig` is not yet a typed field in the SDK version pinned in `_shared/gemini.ts`, it is cast via `as unknown as GenerationConfig`. Do not remove this cast — it is intentional.

```typescript
generationConfig: {
  temperature: 0.1,
  maxOutputTokens,
  thinkingConfig: { thinkingBudget: 0 },
} as unknown as GenerationConfig,
```

This rule applies only to `createFlashModel`. The vision model in `identify/index.ts` (which uses `_genAI.getGenerativeModel` directly) is **not** affected — multi-modal reasoning may benefit from thinking tokens on ambiguous species images.
