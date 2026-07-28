# Identify Edge Function

The `identify` Edge Function is the still-image compatibility endpoint for
legacy visual scan requests. The primary shipped inference path is
`identify-multimodal`, but this route remains deployed for older image clients,
shared still-image primitives, and route-parity tests.

Because speed is still the UX priority for this compatibility path, the
directory stays modularized to keep the orchestrator (`index.ts`) readable and
atomic.

## Directory Structure

The monolith has been broken down strictly by domain responsibility. If you need
to modify the pipeline, modify the exact module below rather than cluttering
`index.ts`:

- **`index.ts`** The main orchestrator. It handles the critical path: routing
  payloads, atomically establishing the compatibility ingestion ledger, calling
  the Vision Model, checking the cache, returning the payload, and spinning up
  the heavy Database Background Task. Ledger setup occurs before provider
  dispatch; failure is retryable, fails closed, and refunds unused provider
  quota.
- **`../_shared/identify/contract.ts`** The executable structural contract. It
  owns provider and final response fields, requiredness, nullability, strings,
  arrays, enums, numeric bounds, inferred TypeScript types, and Swift generation
  metadata.
- **`schema.ts`** The semantic brain. Contains the `systemInstruction` prompt
  sent to Gemini Vision and exports the cached Gemini schema generated from the
  shared executable contract. Modify the prompt here when changing Vision
  interpretation; modify `contract.ts` for a response-shape change. Dog/cat
  breed, mix, coat-pattern, and body-type display hints belong in
  `pet_identification`, not as replacement species taxonomy.
- **`types.ts`** Request/database structural types and aliases inferred from the
  executable model/client contract.
- **`media.ts`** The payload resolver. Houses `resolveImagePayloads()`, which
  safely handles `R2` Base64 buffer loading in serial increments through
  `_shared/mediaBudgets.ts` capped stream readers. Declared `Content-Length` is
  a fast reject only; chunked and missing-length R2 bodies are counted while
  streaming so edge heap limits are enforced before full buffers are assembled.
- **`db.ts`** The Postgres transaction wrapper. Isolates heavy, multi-line
  Supabase interactions (like ghost user upserts) to keep the core orchestrator
  perfectly clean.
- **`sanitize.ts`** The response guardrail layer. It normalizes AI output before
  persistence, including `pet_identification`: labels are trimmed and
  length-capped, evidence is required and capped, confidence is clamped, generic
  Dog/Cat labels are dropped, low-confidence or evidence-free labels are
  dropped, and non-dog/cat taxa never receive pet metadata.
- **`../_shared/aiQuota.ts`** The atomic entitlement, quota, rate-limit, model
  selection, and idempotency boundary used before provider dispatch. The
  reservation returns the durable tier telemetry and database-selected model;
  detached passes and trials are evaluated in the same transaction as quota.
- **`../_shared/entitlement.ts`** Durable tier helpers for non-provider checks
  and telemetry. Provider authorization never comes from an isolate-local cache.

## Architecture Guidelines

**1. The Critical Path** The code executed _before_ `return jsonResponse(...)`
in `index.ts` is the **Critical Path**. Every millisecond counts here.

- _Rule:_ Do not execute network calls, nested database updates, or text-LLM
  enrichments on the critical path. Identify the image and respond immediately.

**2. The Background Engine** The `runBackground(...)` block handles everything
else silently _after_ the user receives their fast ID.

- _Rule:_ Offload all encyclopedic text enrichment, GBIF API polling, PostHog
  telemetry inserts, species table caching, and R2 moderation purges into the
  Background Engine.

## Response Contract

JSON extraction is only syntax handling. The extracted Gemini object is parsed
against `merianModelContract` before normalization or database use. After cache
hydration and all server-added fields, the full `{ success, data }` object is
parsed against `identifyWireEnvelopeContract` before persistence or HTTP
success. The parser strips reviewed unknown keys and rejects invalid nested
types, missing required fields, nullability violations, enum drift, excessive
strings/arrays, unsafe integers, and out-of-range numbers.

A final wire-contract failure is logged internally and returns HTTP `502` with
the stable public code `identify_response_invalid`. Never bypass this second
parse to save or return a partially enriched payload.

After an intentional shape change:

```sh
make generate-edge-dto-contract
make validate-edge-dto-contract
```

Review the generated Swift DTO diff; do not hand-edit its marked block.

## Ingestion Durability

Before provider dispatch, this compatibility endpoint records a
`scan_ingestion_jobs` row plus a sanitized `scan_ingestion_intents` row in one
transaction through `_shared/scanIngestionCompatibility.ts`.

- Staged image keys and optional description text are shaped as
  `identify-multimodal` replay payloads so `replay-scan-ingestion` can recover
  retryable failures with the same `client_scan_id`, subject to the shared
  10-claim server replay ceiling.
- Inline image bytes are never stored in the intent. They are counted in
  `redacted_media_counts`, marked `inline_media_redacted = true`, and remain
  client-retry only.
- Successful background insert delegates to the shared completion-last
  finalization RPC; insert/finalization failures retain retryable state, while
  moderation rejection marks the job `failed_terminal`. Staged-image promotion
  supplies the exact storage-key-to-public-URL disposition to finalization.
- `failed_scan_ingestions` is still written as legacy ops history, but
  `scan_ingestion_jobs` / `scan_ingestion_intents` are the primary recovery
  surface for current rows.

## Pet Identification

`common_name` and `scientific_name` remain the authoritative biological result.
For `Canis lupus familiaris` and `Felis catus`, the response may also include:

```json
{
  "pet_identification": {
    "species_group": "dog",
    "label": "Australian Cattle Dog mix",
    "label_type": "breed_mix",
    "confidence_score": 0.82,
    "evidence": [
      "blue-roan ticking",
      "black saddle patch",
      "compact herding-dog build"
    ]
  }
}
```

This object is scan-level display metadata. It is persisted to
`public.scans.pet_identification` and exposed through sync/Explore, but it is
not written to `species_dictionary` and must not alter species common-name
preferences.

## Processed Material Guardrail

Processed or manufactured objects are not biological observations, even when
they are made from biological material. Rugs, kilims, leather goods, wooden
furniture, paper, textiles, prepared food, toys, artwork, ornaments, and species
depictions are normalized to `is_biological_subject=false` before dictionary
lookup or upsert. The result may keep the object common name for the
non-biological Insight, but source-species scientific names, candidates, and
`is_new_to_merian_dictionary` are cleared.

When a valid biological cache miss does write `species_dictionary.common_names`,
the existing `common_names.en` value wins. Scan-level names only fill an empty
English name so a malformed scan cannot rename an existing species row.

## Shared Micro-Agents

If you need to adjust encyclopedic enrichment or similar species data arrays,
they do not live here. Merian uses shared micro-agents available globally:

- `../_shared/external.ts`: GBIF and Wikipedia REST mapping. Returned imagery is
  filtered through `../_shared/externalImagePolicy.ts`; keep its exact-media
  rules aligned with the iOS `ExternalReferenceImagePolicy` and their cleanup
  migrations.
- `../_shared/group-tags.ts`: Gemini Flash text agent for categorization tags.
- `../_shared/encyclopedic.ts`: The secondary encyclopedic enrichment (supplying
  `colors` and `hazard_type`).

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/identify/index.ts services/supabase/functions/_shared/scanIngestionCompatibility.ts services/supabase/functions/_shared/identify/subjectClassification.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/identify/index.test.ts services/supabase/functions/_shared/scanIngestionCompatibility_test.ts services/supabase/functions/_shared/identify/subjectClassification_test.ts services/supabase/functions/_shared/identify/db_test.ts
```
