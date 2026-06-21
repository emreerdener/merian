# Identify Edge Function

The `identify` Edge Function is the absolute nexus of the Merian AI
identification pipeline. Because speed is our highest UX priority (optimizing
for Time-To-First-Meaning), this directory is aggressively modularized to keep
the core orchestrator (`index.ts`) as fast, readable, and atomic as possible.

## Directory Structure

The monolith has been broken down strictly by domain responsibility. If you need
to modify the pipeline, modify the exact module below rather than cluttering
`index.ts`:

- **`index.ts`** The main orchestrator. It handles the critical path: routing
  payloads, calling the Vision Model, checking the cache, returning the payload,
  and spinning up the heavy Database Background Task.
- **`schema.ts`** The semantic brain. Contains the massive `systemInstruction`
  prompt sent to Gemini Vision, as well as the strongly-typed
  `merianResponseSchema` defining what the AI is allowed to return. **Modify
  this file when you want to change how the Vision AI specifically behaves or
  interprets subjects.** Dog/cat breed, mix, coat-pattern, and body-type
  display hints belong here as `pet_identification`, not as replacement species
  taxonomy.
- **`types.ts`** The structural contracts. Contains `MerianIdentification` and
  `ClientPayload` to ensure Swift client expectations remain strictly
  synchronized with Edge function output.
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
  length-capped, evidence is capped, confidence is clamped, generic Dog/Cat
  labels are dropped, low-confidence labels are dropped, and non-dog/cat taxa
  never receive pet metadata.
- **`../_shared/tierCache.ts`** The shared tier resolver used before model
  selection. It returns the raw database `subscription_tier` plus
  `effective_tier`, `plan`, and `trial_active` so trial Pro users route to
  `gemini-2.5-pro` and emit `plan = "pro_trial"` without being stored as paid
  Pro. It also reads `subscription_expires_at` so detached paid 7-day passes
  resolve as Pro only while their timed grant is active.

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
    "evidence": ["blue-roan ticking", "black saddle patch", "compact herding-dog build"]
  }
}
```

This object is scan-level display metadata. It is persisted to
`public.scans.pet_identification` and exposed through sync/Explore, but it is
not written to `species_dictionary` and must not alter species common-name
preferences.

## Shared Micro-Agents

If you need to adjust encyclopedic enrichment or similar species data arrays,
they do not live here. Merian uses shared micro-agents available globally:

- `../_shared/external.ts`: GBIF and Wikipedia REST mapping.
- `../_shared/group-tags.ts`: Gemini Flash text agent for categorization tags.
- `../_shared/encyclopedic.ts`: The secondary encyclopedic enrichment (supplying
  `colors` and `hazard_type`).
