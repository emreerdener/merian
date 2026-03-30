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

// ✓ GOOD — single embedded join, only decoded fields
.from("species_lookalikes")
.select("lookalike:lookalike_id(scientific_name, common_names, reference_image_url, iucn_red_list_status)")
.eq("species_id", speciesId)
```
The embedded join syntax resolves two sequential PostgREST round-trips (the old N+1 `SELECT id → SELECT IN (ids)` pattern) into a single SQL JOIN, cutting connection-pool acquisitions and Deno isolate latency in half.

**Resolve-and-Return Pattern:** Functions that write to a join table and then need the hydrated rows must return the result directly from the write query — never call a separate fetch function after the write. This eliminates a redundant third round-trip on migration or LLM-completion paths. See `resolveLookalikesToJoinTable` in `enrich-scan/db.ts` for the reference implementation: the `species_dictionary` query that resolves names to IDs is expanded to also fetch the hydration columns, and the mapped `LookalikeSummary[]` is returned directly to the caller.
