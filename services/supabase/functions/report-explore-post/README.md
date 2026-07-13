# Report Explore Post

Authenticated moderation ingress for reports about public Explore post content.
This pipeline is deliberately separate from identification review:

- Post-content reports write `public.explore_post_reports`.
- Identification disputes write `public.flagged_reviews` through `/flag-issue`.
- Reporting a post never changes `scans.is_flagged` or
  `scans.human_intervention_notes`.

## Request

`POST /functions/v1/report-explore-post`

```json
{
  "post_id": "00000000-0000-0000-0000-000000000001",
  "reason": "Inappropriate content",
  "details": "Optional context, capped at 500 characters"
}
```

Allowed reasons are `Spam`, `Harassment`, `Inappropriate content`, and `Other`.
The shared Edge handler requires a valid user session. The function rejects an
invalid post id, an unavailable/unshared post, and attempts to report one's own
post.

## Persistence and moderation lifecycle

`db.ts` reads the post with the service-role client after authentication and
upserts one row per `(post_id, reporter_user_id)`. A new row defaults to
`PENDING_REVIEW`. A repeat report may refresh its reason, details, author id,
and `updated_at`, but it does not reset an existing `DISMISSED` or `ACTIONED`
status. This preserves moderator decisions and prevents repeat submissions from
reopening completed work.

The table has RLS enabled and grants no access to `PUBLIC`, `anon`, or
`authenticated`; only the service-role-backed Edge Function writes it. Never
expose the service-role key to either iOS or the public web client.

## Client behavior

- Native Explore calls this endpoint and locally removes the reported post
  after a successful response.
- The anonymous public web detail page does not call this endpoint. Its centered
  **Report this post** action opens a support email containing the immutable
  public post id.

## Verification

```bash
deno check services/supabase/functions/report-explore-post/index.ts \
  services/supabase/functions/report-explore-post/db.ts
deno test --allow-read \
  services/supabase/functions/report-explore-post/db.test.ts \
  services/supabase/functions/_tests/migrationMediaContract.test.ts
```

An unauthenticated production request must return `HTTP 401`.
