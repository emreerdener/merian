# Get Explore Mention Suggestions

Returns scoped `@username` autocomplete suggestions for the Explore comment
composer.

This endpoint is not a global public-user search. It only returns users the
viewer is allowed to mention in the current comment context.

## Request

```json
{
  "post_id": "uuid",
  "parent_comment_id": "uuid",
  "query": "as",
  "limit": 8
}
```

- `post_id` is required.
- `parent_comment_id` is optional. When present, it must be a visible top-level
  comment on the same post.
- `query` is optional and normalized by the database helper.
- `limit` is optional and capped server-side.
- Authentication is resolved by `withEdgeHandler`; the request body cannot
  choose `self_id`.

## Eligibility

Suggestions can include:

- the post author
- visible participants in the current post or reply thread
- users the viewer follows, only when `query` has enough typed characters

Suggestions exclude:

- the current viewer
- blocked users in either direction
- shadowbanned users
- users whose public profile is not visible to the viewer
- arbitrary public users outside the post/thread/following scope

For replies, thread-participant suggestions are scoped to the selected top-level
comment and its visible replies. This prevents a reply composer from browsing
unrelated participants elsewhere on the post.

## Response

```json
{
  "data": [
    {
      "user_id": "uuid",
      "username": "ash_b",
      "display_name": "Ash B.",
      "avatar_url": "https://...",
      "source": "thread"
    }
  ]
}
```

`source` is one of:

- `post_author`
- `thread`
- `following`

Suggestions always expose the user's current policy-valid public handle. When a
comment is saved, the resolver stores that selected handle with the durable user
ID as a historical snapshot. Later handle changes do not rewrite the plain-text
comment or its stored snapshot; comment reads continue matching the old token
while profile taps route by user ID. See
[`23-explore-comment-mentions.md`](../../../../docs/features-and-hardware/23-explore-comment-mentions.md)
for the durable rendering contract.

## Local Verification

```sh
deno fmt --check services/supabase/functions/get-explore-mention-suggestions
deno lint --config services/supabase/functions/deno.json services/supabase/functions/get-explore-mention-suggestions
deno check --config services/supabase/functions/deno.json services/supabase/functions/get-explore-mention-suggestions/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase,apps/ios services/supabase/functions/_tests/publicUsernamePolicyMigrationContract.test.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreMentionsDb.test.ts
```

The DB integration tests skip live assertions when the local Supabase Postgres
instance is not running at `127.0.0.1:54322`.
