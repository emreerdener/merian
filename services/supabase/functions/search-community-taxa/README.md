# search-community-taxa

Authenticated Community Identification taxonomy search.

The endpoint searches the active Community Taxonomy Index first. If local
results are thin and the query is at least three characters, it asks GBIF for
additional suggestions, caches those taxa into `taxon_nodes` / `taxon_names`,
and searches again. GBIF failures are logged and do not block local results.

## Request

```json
{
  "query": "Rosa",
  "limit": 20,
  "taxonomy_version_id": "optional-pinned-version"
}
```

## Response

Each row includes the original search fields plus index provenance:

```json
{
  "taxon_id": "uuid",
  "taxonomy_version_id": "uuid",
  "common_name": "External Rose",
  "scientific_name": "Rosa externa",
  "rank": "species",
  "path": "plantae.tracheophyta.magnoliopsida.rosales.rosaceae.rosa.rosa_externa",
  "species_id": null,
  "gbif_taxon_key": 3000001,
  "source": "gbif",
  "is_in_dictionary": false,
  "accepted_gbif_taxon_key": 3000001,
  "taxonomic_status": "accepted"
}
```

`species_id = null` is valid and means the taxon is known to the Community
Taxonomy Index but has not been materialized into Merian's enriched
`species_dictionary` yet.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/search-community-taxa/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/search-community-taxa/gbif.test.ts
```
