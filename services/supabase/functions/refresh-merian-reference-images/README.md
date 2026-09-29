# refresh-merian-reference-images

Internal cron worker that promotes high-quality, currently published Explore
post media into `species_reference_images` with `source = "merian"`.

The worker is service-role only. `verify_jwt = false` is intentional so `pg_net`
can call it; the function timing-safely validates one exact platform-managed
current or legacy server key. Opaque keys use `apikey` only.

## Request

All fields are optional:

```json
{
  "quality_threshold": 80,
  "species_confidence_threshold": 0.95,
  "per_species_limit": 8,
  "dry_run": false
}
```

- `quality_threshold`: integer `0...100`, default `80`.
- `species_confidence_threshold`: number `0...1`, default `0.95`.
- `per_species_limit`: integer `1...50`, default `8`.
- `dry_run`: boolean, default `false`.

## Behavior

- Considers only visible Explore posts: shared, not unshared, non-tombstoned,
  media present, non-private backing scan geoprivacy, non-shadowbanned author,
  and resolved species present. This promotion gate is stricter than ordinary
  Explore post visibility: a post-level `private` location setting can keep the
  post visible without public location, but private backing scans are not
  promoted into Merian species reference imagery.
- Uses the validated effective Explore species association. Legacy rows retain
  their prior confirmed/original-ID behavior. Explicit rows require original
  species rank and the same original/effective species; a broader/community
  label cannot invent a species association.
- Unnests all non-empty `scans.image_storage_urls`.
- Requires `image_quality_score >= 80` and `ai_confidence_score >= 0.95` by
  default. Only legacy rows retain the confirmed-ID confidence exception;
  explicit verified taxonomy selection is not proof of photographic correctness
  and cannot bypass the original score or become a confirmed-image priority.
- Both dry-run and live selection require an exact compatible Gemini execution
  or historical absence of provenance. Unknown profiles are excluded even when a
  species is confirmed: confirmation does not qualify a new image-quality scale.
  Existing source records are disqualified by the next normal refresh.
- Dedupes by `(species_id, image_url)`, preferring confirmed-species provenance,
  higher confidence, higher quality score, and then newer `shared_at`.
- Promotes up to 8 Merian images per species by default.
- Writes public rows with:
  - `source = "merian"`
  - `license = "Used with permission via Naturebook"`
  - `attribution = users.public_author_name` (`public_username` remains the
    handle and is not used as media attribution unless the user's default/alias
    display label is the username)
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
deno check --config services/supabase/functions/deno.json services/supabase/functions/refresh-merian-reference-images/index.ts services/supabase/functions/refresh-merian-reference-images/db.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/refresh-merian-reference-images/db.test.ts services/supabase/functions/_tests/merianReferenceImagesDb.test.ts
```
