# Get Explore Species Posts

Returns viewer-visible Explore cards for one exact canonical Species Dictionary
UUID. The endpoint powers the in-app **Community sightings** preview and its
paginated grid without adding viewer-sensitive posts to the cacheable
`species-dictionary` response.

## Contract

First page:

```json
{ "species_id": "uuid", "limit": 6 }
```

Follow-up pages send the prior response cursor as flat request fields:

```json
{
  "species_id": "uuid",
  "limit": 30,
  "before_image_quality_score": 94,
  "before_shared_at": "2026-07-14T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

`before_image_quality_score` may be omitted for the unscored tier, but
`before_shared_at` and `before_post_id` must always appear together. Responses
return the normal Explore card projection and an optional `next_cursor`:

```json
{
  "data": [],
  "next_cursor": {
    "image_quality_score": null,
    "shared_at": "2026-07-14T12:00:00.000Z",
    "post_id": "uuid"
  }
}
```

Rows sort by image quality descending, then by newest share timestamp and post
UUID. Unscored rows sort after scores 0 through 100. The backing
`public.get_explore_species_posts(...)` RPC uses the visibility-safe Explore
projection, exact confirmed/community-resolved species membership, and is
callable only by `service_role` through this authenticated Edge Function.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-species-posts
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-species-posts
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-species-posts/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/get-explore-species-posts/request.test.ts services/supabase/functions/get-explore-species-posts/response.test.ts services/supabase/functions/_tests/exploreSpeciesPostsDb.test.ts
```
