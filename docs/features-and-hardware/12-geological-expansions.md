# Geological Domain Expansions (Rocks & Minerals)

Merian's core architecture identifies biological species mapped to Linnean taxonomy (`kingdom`, `phylum`, `class`, `order`, etc.). We have researched extending inference to **Geology** (rocks, minerals, fossils).

## Architectural Roadmap & Schema Migrations

If Geology is integrated in the future, the following architectural boundaries must be decoupled and migrated:

### 1. Database Schema `species_dictionary`
Geology breaks the Linnean mapping paradigm. Rocks do not have a `kingdom` or `phylum`.
- **Required Change**: Transform `species_dictionary` into a generic `classification_dictionary`.
- Replace rigid taxonomy columns with a flexible `JSONB` structure (e.g. `classification_metadata`), or introduce generic hierarchical ranks (`rank_1`, `rank_2`, etc.) that can represent `{ "group": "Silicate", "cleavage": "Perfect", "hardness": "7"}` properties.

### 2. Edge Inference Router (`identify`)
Currently, `is_biological_subject` discards non-living matter.
- **Required Change**: Convert the strict Gemini `merianResponseSchema` to handle multiple object domains using conditional definitions.
- Introduce an `identification_domain` ENUM (`biology`, `geology`, `unknown`).
- The Edge function must parse the payload conditionally based on the matched domain before calling `supabaseAdmin.upsert()`, avoiding SQL failures when a rock lacks a `scientific_name` or `genus`.

### 3. Native UI `InsightSheetView`
- **Required Change**: The iOS interface builds horizontal taxonomy ribbons expecting biological structs.
- Build a secondary `GeologyTaxonomyHeader` view that switches into rendering `Hardness`, `Luster`, `Streak`, and `Crystal System` based on the `identification_domain` enum, avoiding crash states on the SwiftUI actor.
