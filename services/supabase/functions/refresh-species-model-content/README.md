# refresh-species-model-content

Scheduled service-role worker for model-heavy species enrichment jobs.

The worker claims `species_enrichment_jobs` for `habitat`, `lookalikes`, and
`group_tags` through one priority-ordered queue. It reuses the same biology
primitives behind `enrich-scan` without pretending a user rescanned the
organism.

Jobs are queued by the `species_dictionary` insert trigger and the sparse-row
backfill in `20260707153931_species_dictionary_enrichment_queue_backfill.sql`,
plus any explicit service-role calls to
`public.enqueue_species_enrichment_jobs(...)`.

## Security

- `verify_jwt = false` in `services/supabase/config.toml` so `pg_net` can invoke
  the function.
- The function still requires one exact current or legacy server key through
  `_shared/serviceRoleAuth.ts`; opaque keys use `apikey` only.
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
- `lookalikes`: calls `fetchSimilarSpecies`, takes at most three candidates,
  resolves every identity to an exact accepted GBIF species (following an exact
  synonym to its accepted identity), and atomically materializes the dictionary
  rows, directional relations, compatibility cache, and provenance. The database
  rechecks kingdom plus order/family and preserves reviewed relations and
  curated provenance.
- `group_tags`: calls `fetchGroupTags`, normalizes up to five lowercase tags,
  and persists through `updateGroupTags`.

An unresolved identity, provider outage, partial candidate failure, stale
dictionary identity, or missing taxonomy is retryable and therefore marks the
job failed. A valid empty model result, a set containing only incompatible or
reviewed-rejected candidates, and a completed write are terminal outcomes.
Confirmed empty outcomes set `lookalikes_flash_attempted` so foreground scans do
not repeat the same model request. A partial result that persists at least one
valid relation also sets that foreground memo while the queue job remains
failed/retryable for its unresolved candidates.

Migration `20260903163744_recover_species_lookalike_enrichment.sql` gives public
legacy species with no nonrejected lookalike relation one new versioned attempt
if an earlier worker recorded an empty success or exhausted all attempts. The
version marker is written only when the new worker claims the job, so installing
the database migration before the worker cannot send legacy work to old code.
Preview uses the same eligibility rules without locks or writes. Normal failed
jobs keep their existing backoff and attempt budget, and running jobs are never
stolen.

New GBIF-verified candidate rows still queue authoritative reference, habitat,
and group-tag hydration. Candidate insertion suppresses recursive lookalike
generation and same-genus fan-out for that transaction; the later explicit
subject-to-candidate write is the only relation created. Ordinary dictionary
inserts keep the established enrichment and same-genus behavior.

## Rollout and Recovery

Apply the database migration before deploying the updated worker. The migration
installs the service-role claim/persistence routines, the legacy-candidate
index, and transaction-scoped trigger guards. It does not reopen legacy work by
itself, so an older worker cannot consume repaired jobs. The new worker requires
those routines and writes the recovery version atomically when it claims an
eligible job.

Use `dry_run: true` with `content_groups: ["lookalikes"]` to preview the same
bounded eligibility order without locks, attempts, version markers, provider
calls, or completion writes. After execution, use the aggregate
`community-taxonomy-status` queue health surface for backlog and failures. An
empty relation set can be a verified terminal result and must not be treated as
a blanket reset condition.

## Local Verification

```sh
deno check --frozen --config services/supabase/functions/refresh-species-model-content/deno.json services/supabase/functions/refresh-species-model-content/index.ts
deno test --frozen --config services/supabase/functions/deno.json --allow-env --allow-read=. services/supabase/functions/refresh-species-model-content/db.test.ts services/supabase/functions/refresh-species-model-content/lookalikeCandidates.test.ts services/supabase/functions/_tests/speciesLookalikeRecoveryMigrationContract.test.ts
make validate-supabase-migrations
make test-supabase-privileged-routines
```

The last target starts a disposable local Supabase catalog and discovers
`services/supabase/tests/species_lookalike_recovery.sql` with every other pgTAP
fixture. A skipped or connection-refused database test is not passing evidence.
