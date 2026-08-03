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
  the Vision Model, checking the cache, promoting required media, inserting and
  rereading the exact owner row, and synchronously attempting response-aware
  finalization before returning the payload. Ledger setup occurs before provider
  dispatch; failure is retryable, fails closed, and refunds unused provider
  quota. Stored completion or an exact reconstructible owner row is checked
  before media/quota work; a lost-response retry returns marked idempotent `200`
  without another provider call and may retain a retryable canonical ledger.
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
  Supabase interactions (including the Auth-backed, merge-aware scan-user
  profile prerequisite) to keep the core orchestrator clean.
- **`sanitize.ts`** The response guardrail layer. It normalizes AI output before
  persistence, including `pet_identification`: labels are trimmed and
  length-capped, evidence is required and capped, confidence is clamped, generic
  Dog/Cat labels are dropped, low-confidence or evidence-free labels are
  dropped, and non-dog/cat taxa never receive pet metadata.
- **`../_shared/aiQuota.ts`** The atomic entitlement, quota, rate-limit, model
  selection, and idempotency boundary used before provider dispatch. The
  reservation returns the durable tier telemetry and database-selected model,
  carries the original analysis and optional complimentary linkage, and derives
  Flash fallback from the parsed evidence shape. Paid passes and the active
  rollout mode are evaluated in the same user-first transaction as quota.
- **`../_shared/entitlement.ts`** Durable tier helpers for non-provider checks
  and telemetry. Provider authorization never comes from an isolate-local cache.

## Architecture Guidelines

**1. The Required Path** The code executed _before_ successful
`return jsonResponse(...)` in `index.ts` is the durability promise consumed by
Insight, Field Chat, Explore, field trips, and owner sync.

- _Rule:_ Keep provider inference, required moderation/media promotion, profile
  prerequisites, exact-owner insertion, and the synchronous user-first
  entitlement completion orchestration here. An orchestration failure may
  degrade to the narrow owner-row fallback only after exact-owner insertion was
  proved durable.

**2. The Background Engine** The `runBackground(...)` block handles everything
nonessential after the user receives a durable ID.

- _Rule:_ Offload all encyclopedic text enrichment, GBIF API polling, PostHog
  telemetry inserts, group tags, and candidate enrichment into the Background
  Engine. Required scan/media writes and moderation cleanup are not optional
  background work.

## Response Contract

After entitlement cutover, public calls require
`X-Merian-Entitlement-Protocol: 2`; missing/obsolete callers receive
`426 client_update_required` before provider dispatch. The canonical
`client_scan_id` is the complimentary-ledger linkage. Paid Pro wins, otherwise
an available credit creates/reuses one hold; after exhaustion only a
Flash-compatible single-evidence request can use the independent daily free
policy.

Successful envelopes can add optional `entitlement` metadata with the owner,
`plan_used`, consumed funding status, and a versioned post-settlement snapshot.
Completion uses the user-first entitlement orchestrator; valid non-biological
results consume, proven terminal failures release, and retryable/ambiguous
outcomes remain held. Provider counters remain charged after attempted calls.
See the normative
[`complimentary scan contract`](../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

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
- The awaited insert delegates to the user-first entitlement completion
  orchestrator. A failure before exact-owner insertion returns retryable 503. If
  only finalization or bookkeeping fails after that row committed, this
  compatibility route may return its already validated response while leaving
  the ledger and hold retryable for same-UUID canonical reconciliation. A
  moderation rejection uses the user-first terminal orchestrator; lower-level
  code cannot write `failed_terminal` or settle the hold directly. Staged-image
  promotion supplies the exact storage-key-to-public-URL disposition to
  finalization.
- Every insert settles through `_shared/scanPersistence.ts`. A returned database
  rejection plus a definitive missing-owner read permits quota/media cleanup; a
  lost response or unavailable exact-owner verification preserves committed
  quota and promoted media and returns retryable 503.
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

The normative joined success, replay, recovery, and rollout contract is
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).
