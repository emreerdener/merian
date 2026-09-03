# Enrich Scan Edge Function

The `enrich-scan` Edge Function handles background encyclopedic enrichment for
current and historical biological scans. Each request requires a scientific name
and one scope: `enrichment` for metadata or `lookalikes` for similar species.
The iOS caller requests missing scopes independently and applies each response
as it arrives.

The
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#deno-enrich-scan-edge-node)
defines request validation, scoped responses, quota attribution, and legacy
null/placeholder behavior. Native request ownership and focused checks live in
the
[Core Network guide](../../../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification);
InferenceEngine retains scheduling, bounded lookalike retry, and stale-result
suppression.

## Directory Structure

The module is broken down by domain responsibility to keep the critical HTTP
router readable:

- **`index.ts`** The HTTP orchestrator validates the scoped request, evaluates
  its cache path, and reserves quota before provider work on a miss. Separate
  in-flight maps deduplicate same-species work within each scope on a warm
  isolate. `formatEnrichmentOnlyPayload` and `formatLookalikesOnlyPayload`
  return only the selected scope's fields; there is no combined generation
  branch.
- **`types.ts`** Strict interfaces mapping the `CachedSpeciesData` from
  Postgres, removing dangerous `as any` type-casting from the orchestrator.
- **`db.ts`** Encapsulated database procedures. Safely manages the
  `species_dictionary` lookup and applies targeted UPSERT patching when new AI
  enrichment data resolves.

## Shared Micro-Agents

If you need to adjust what data is generated during an enrichment check, do not
edit `enrich-scan` directly. Merian heavily re-uses atomic AI agents located
globally across the API:

- `../_shared/encyclopedic.ts`: The generative AI prompt that extracts habitat,
  taxonomy, hazard, and color context.
- `../_shared/similar-species.ts`: The AI agent that calculates visual and
  biological lookalikes.
- `../_shared/external.ts`: Wikipedia/GBIF enrichment. Its reference images must
  pass `../_shared/externalImagePolicy.ts` before the response or species cache
  write is built. The current exact rule suppresses iNaturalist media
  `605615444` only; it does not suppress the species or provider.

Provider calls use the model selected by the existing quota reservation. Cache,
provider admission, persistence, and authorization behavior are unchanged by the
native endpoint organization.
