# Geological Domain Expansions (Rocks & Minerals)

Merian's core architecture natively identifies biological species mapping seamlessly to Linnean taxonomy (`kingdom`, `phylum`, `class`, `order`, etc.). We have actively researched extending inference to **Geology** (rocks, minerals, fossils).

## Architectural Roadmap & Schema Migrations

If Geology is integrated in the future, the following architectural boundaries must be heavily decoupled and migrated natively:

### 1. Database Schema `species_dictionary`
Geology completely breaks the `Linnean` mapping paradigm. Rocks do not have a `kingdom` or `phylum`.
- **Required Change**: Transform `species_dictionary` into a generic `classification_dictionary`.
- Replace rigid taxonomy columns with a flexible `JSONB` structure (e.g. `classification_metadata`), or introduce generic hierarchical ranks (`rank_1`, `rank_2`, etc.) that can natively handle `{ "group": "Silicate", "cleavage": "Perfect", "hardness": "7"}` properties seamlessly.

### 2. Edge Inference Router (`identify`)
Currently, `is_biological_subject` strictly throws out non-living matter.
- **Required Change**: Convert the strict Gemini `merianResponseSchema` to dynamically intercept multiple object domains using conditional definitions natively.
- Introduce an `identification_domain` ENUM (`biology`, `geology`, `unknown`).
- The Edge function must conditionally parse the payload based exactly on the matched domain before instantiating `supabaseAdmin.upsert()`, gracefully avoiding SQL injection failures when a rock lacks a `scientific_name` or `genus`.

### 3. Native UI `InsightSheetView`
- **Required Change**: The iOS interface natively builds horizontal taxonomy ribbons expecting biological structs.
- Build a secondary `GeologyTaxonomyHeader` View natively that gracefully switches into rendering `Hardness`, `Luster`, `Streak`, and `Crystal System` depending on the `identification_domain` enum safely avoiding generic crash states on the SwiftUI actor.
