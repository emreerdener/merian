# community-taxonomy-status

Service-role-only status endpoint for Merian's Community Taxonomy Index and
species enrichment pipeline.

## Purpose

This endpoint is an internal observability surface. It answers the questions
operators need before enabling broader taxonomy imports or coverage UX:

- Which taxonomy version is active?
- How many taxa are Dictionary-backed, GBIF-only, or split by rank/source?
- Which GBIF import/cache runs happened most recently?
- How healthy is the species enrichment queue?
- What coverage targets, such as Birds, have current counts?

## Request

`POST /functions/v1/community-taxonomy-status`

Headers:

- `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`

Body fields are optional:

```json
{
  "import_run_limit": 10,
  "job_limit": 10
}
```

Both limits must be integers from `1` to `50`.

## Response

```json
{
  "success": true,
  "generated_at": "2026-06-22T00:00:00.000Z",
  "active_taxonomy": {
    "id": "taxonomy-version-id",
    "status": "active",
    "source": "merian_dictionary",
    "source_revision": "species_dictionary",
    "node_count": 1000,
    "species_node_count": 600,
    "dictionary_species_count": 240,
    "gbif_only_taxa_count": 360
  },
  "node_counts_by_source": [],
  "node_counts_by_rank": [],
  "latest_import_runs": [],
  "enrichment_jobs": {
    "counts": [],
    "next_jobs": [],
    "recent_failures": []
  },
  "coverage_targets": []
}
```

This function is read-only. It does not claim enrichment jobs, refresh coverage,
or mutate taxonomy rows.
