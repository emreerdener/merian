# Enrich Scan Edge Function

The `enrich-scan` edge function handles background encyclopedic enrichment for
historical scan records initially captured under the "Free/Flash" tier. If a
user subsequently interacts with a legacy scan, or upgrades to Pro and gains
access to deeper Insight cards, this function fills out the missing fields.

## Directory Structure

The module is broken down by domain responsibility to keep the critical HTTP
router readable:

- **`index.ts`** The main orchestrator router. Evaluates existing
  `species_dictionary` Postgres cache hits, and concurrently spins up
  encyclopedic and similar-species micro-agents on cache misses. Unifies the AI
  response via `formatEnrichmentPayload` to strictly guarantee uniform JSON
  contracts.
- **`types.ts`** Strict interfaces mapping the `CachedSpeciesData` from
  Postgres, removing dangerous `as any` type-casting from the orchestrator.
- **`db.ts`** Encapsulated database procedures. Safely manages the
  `species_dictionary` lookup and applies targeted UPSERT patching when new AI
  enrichment data resolves.

## Shared Micro-Agents

If you need to adjust what data is generated during an enrichment check, do not
edit `enrich-scan` directly. Merian heavily re-uses atomic AI agents located
globally across the API:

- `../_shared/encyclopedic.ts`: The Flash 2.5 generative AI prompt that extracts
  habitat, taxonomy, hazard, and color context.
- `../_shared/similar-species.ts`: The Flash 2.5 AI agent that calculates visual
  and biological lookalikes.
- `../_shared/external.ts`: Wikipedia/GBIF enrichment. Its reference images must
  pass `../_shared/externalImagePolicy.ts` before the response or species cache
  write is built. The current exact rule suppresses iNaturalist media
  `605615444` only; it does not suppress the species or provider.
