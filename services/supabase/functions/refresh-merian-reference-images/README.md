# refresh-merian-reference-images

Internal cron worker that promotes high-quality, currently published Explore
post media into `species_reference_images` with `source = "merian"`.

The worker is service-role only. `verify_jwt = false` is intentional so
`pg_net` can call it; the function validates
`Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}` with a timing-safe compare.

## Request

All fields are optional:

```json
{
  "quality_threshold": 90,
  "species_confidence_threshold": 0.95,
  "per_species_limit": 8,
  "dry_run": false
}
```

- `quality_threshold`: integer `0...100`, default `90`.
- `species_confidence_threshold`: number `0...1`, default `0.95`.
- `per_species_limit`: integer `1...50`, default `8`.
- `dry_run`: boolean, default `false`.

## Behavior

- Considers only visible Explore posts: shared, not unshared, non-tombstoned,
  media present, non-private geoprivacy, non-shadowbanned author, and resolved
  species present.
- Uses `COALESCE(scans.confirmed_species_id, scans.species_id)`.
- Unnests all non-empty `scans.image_storage_urls`.
- Requires `image_quality_score >= 90` and either
  `ai_confidence_score >= 0.95` or a non-null `confirmed_species_id` by default.
- Dedupes by `(species_id, image_url)`, preferring confirmed-species provenance,
  higher confidence, higher quality score, and then newer `shared_at`.
- Promotes up to 8 Merian images per species by default.
- Writes public rows with:
  - `source = "merian"`
  - `license = "Used with permission via Merian"`
  - `attribution = users.public_author_name`
- Removes Merian public rows when their source post/media is no longer eligible.
- Keeps source scan/post/user provenance in
  `species_reference_image_merian_sources`, which has no anon/authenticated RLS
  read policy. The provenance also stores the raw AI confidence score and
  whether the candidate qualified through AI confidence or confirmed-species
  resolution.

## Response

```json
{
  "success": true,
  "candidate_count": 12,
  "promoted_count": 8,
  "removed_count": 1,
  "species_count": 2,
  "dry_run": false
}
```

## Verification

```bash
deno check services/supabase/functions/refresh-merian-reference-images/index.ts services/supabase/functions/refresh-merian-reference-images/db.ts
deno test --allow-env --allow-net services/supabase/functions/refresh-merian-reference-images/db.test.ts services/supabase/functions/_tests/merianReferenceImagesDb.test.ts
```
