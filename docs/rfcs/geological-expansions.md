# Geological Domain Expansions (Rocks & Minerals)

Merian's core architecture identifies biological species mapped to Linnean taxonomy (`kingdom`, `phylum`, `class`, `order`, etc.). We have researched extending inference to **Geology** (rocks, minerals, fossils).

## Current Implementation (Soft Expansion)

Rather than executing the heavy architectural decoupling outlined in the roadmap below, we implemented a **soft expansion** directly within the LLM prompt. 

Geological subjects (rocks, minerals) are treated as `is_biological_subject = false`. However, Gemini is explicitly instructed to provide `scientific_name` (e.g. "Silicon dioxide") and `common_name` (e.g. "Quartz") for these items, instead of omitting them like it does for generic debris.

Because `is_biological_subject` remains `false`:
- The AI orchestrator bypasses `species_dictionary` hydration, avoiding Linnean column constraint SQL failures.
- It bypasses Wikipedia and GBIF enrichment.
- Scans gracefully route into the `NonBiologicalScansView` graveyard, automatically purging after 30 days without polluting biological records.
- The UI natively extracts `commonName` from the EdgeResponse, displaying "Quartz" in the collection grid rather than reverting to the fallback "Unknown Subject".

---

## Architectural Roadmap & Schema Migrations (For Future Full Integration)

If Geology is fully integrated as a first-class citizen alongside biology, the following boundaries must be deeply migrated:

### 1. Database Schema `species_dictionary`
Geology breaks the Linnean mapping paradigm. Rocks do not have a `kingdom` or `phylum`.
- **Required Change**: Transform `species_dictionary` into a generic `classification_dictionary`.
- Replace rigid taxonomy columns with a flexible `JSONB` structure (e.g. `classification_metadata`), or introduce generic hierarchical ranks (`rank_1`, `rank_2`, etc.) that can represent `{ "group": "Silicate", "cleavage": "Perfect", "hardness": "7"}` properties.

### 2. Edge Inference Router (`identify`)
Currently, `is_biological_subject` discards non-living matter.
- **Required Change**: Convert the strict Gemini `merianResponseSchema` to handle multiple object domains using conditional definitions.
- Introduce an `identification_domain` ENUM (`biology`, `geology`, `unknown`).
- The Edge function must parse the payload conditionally based on the matched domain before calling `supabaseAdmin.upsert()`, avoiding SQL failures when a rock lacks a `scientific_name` or `genus` but has other properties.

### 3. Native UI `InsightSheetView`
- **Required Change**: The iOS interface builds horizontal taxonomy ribbons expecting biological structs.
- Build a secondary `GeologyTaxonomyHeader` view that switches into rendering `Hardness`, `Luster`, `Streak`, and `Crystal System` based on the `identification_domain` enum, avoiding crash states on the SwiftUI actor.
