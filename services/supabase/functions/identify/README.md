# Identify Edge Function

The `identify` Edge Function is the absolute nexus of the Merian AI identification pipeline. Because speed is our highest UX priority (optimizing for Time-To-First-Meaning), this directory is aggressively modularized to keep the core orchestrator (`index.ts`) as fast, readable, and atomic as possible.

## Directory Structure

The monolith has been broken down strictly by domain responsibility. If you need to modify the pipeline, modify the exact module below rather than cluttering `index.ts`:

- **`index.ts`**
  The main orchestrator. It handles the critical path: routing payloads, calling the Vision Model, checking the cache, returning the payload, and spinning up the heavy Database Background Task.
- **`schema.ts`**
  The semantic brain. Contains the massive `systemInstruction` prompt sent to Gemini Vision, as well as the strongly-typed `merianResponseSchema` defining what the AI is allowed to return. **Modify this file when you want to change how the Vision AI specifically behaves or interprets subjects.**
- **`types.ts`**
  The structural contracts. Contains `MerianIdentification` and `ClientPayload` to ensure Swift client expectations remain strictly synchronized with Edge function output.
- **`media.ts`**
  The payload resolver. Houses `resolveImagePayloads()`, which safely handles `R2` Base64 buffer loading in serial increments through `_shared/mediaBudgets.ts` capped stream readers. Declared `Content-Length` is a fast reject only; chunked and missing-length R2 bodies are counted while streaming so edge heap limits are enforced before full buffers are assembled.
- **`db.ts`**
  The Postgres transaction wrapper. Isolates heavy, multi-line Supabase interactions (like ghost user upserts) to keep the core orchestrator perfectly clean.

## Architecture Guidelines

**1. The Critical Path**
The code executed *before* `return jsonResponse(...)` in `index.ts` is the **Critical Path**. Every millisecond counts here. 
- *Rule:* Do not execute network calls, nested database updates, or text-LLM enrichments on the critical path. Identify the image and respond immediately.

**2. The Background Engine**
The `runBackground(...)` block handles everything else silently *after* the user receives their fast ID.
- *Rule:* Offload all encyclopedic text enrichment, GBIF API polling, PostHog telemetry inserts, species table caching, and R2 moderation purges into the Background Engine.

## Shared Micro-Agents
If you need to adjust encyclopedic enrichment or similar species data arrays, they do not live here. Merian uses shared micro-agents available globally:
- `../_shared/external.ts`: GBIF and Wikipedia REST mapping.
- `../_shared/group-tags.ts`: Gemini Flash text agent for categorization tags.
- `../_shared/encyclopedic.ts`: The secondary encyclopedic enrichment (supplying `colors` and `hazard_type`).
