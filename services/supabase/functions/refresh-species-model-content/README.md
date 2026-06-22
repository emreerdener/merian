# refresh-species-model-content

Scheduled service-role worker for model-heavy species enrichment jobs.

The worker claims `species_enrichment_jobs` for `habitat`, `lookalikes`, and
`group_tags`. It reuses the same biology primitives behind `enrich-scan`
without pretending a user rescanned the organism.

## Security

- `verify_jwt = false` in `services/supabase/config.toml` so `pg_net` can invoke
  the function.
- The function still requires
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` and compares it with
  `timingSafeCompare`.
- It is not an iOS or public web endpoint.

## Request

Scheduled call:

```json
{ "limit": 12 }
```

Manual service-role calls may include:

```json
{
  "limit": 6,
  "dry_run": true,
  "as_of": "2026-06-22T00:00:00Z",
  "content_groups": ["habitat", "lookalikes", "group_tags"]
}
```

`limit` defaults to `12` and is capped at `50`. Refreshes run with concurrency
`2` to avoid stampeding Gemini.

## Behavior

- `habitat`: calls `fetchStaticEncyclopedicData` and persists taxonomy/habitat
  through `updateSpeciesEnrichment`.
- `lookalikes`: calls `fetchSimilarSpecies`, validates/resolves rows through
  `resolveLookalikesToJoinTable`, and persists durable lookalike provenance.
- `group_tags`: calls `fetchGroupTags`, normalizes up to five lowercase tags,
  and persists through `updateGroupTags`.

Each job is marked succeeded for refreshed/no-data outcomes and failed for
retryable errors such as missing taxonomy for lookalikes.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/refresh-species-model-content/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/refresh-species-model-content/db.test.ts
```
