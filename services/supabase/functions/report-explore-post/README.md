# Report Explore Post

Authenticated moderation ingress for reports about public Explore post content.
This pipeline is deliberately separate from identification review:

- Post-content reports write `public.explore_post_reports`.
- Backward-compatible owner identification disputes write
  `public.flagged_reviews` through `/flag-issue`; current iOS has no dispute
  call site.
- Reporting a post never changes `scans.is_flagged` or
  `scans.human_intervention_notes`.

The current iOS Explore feed, post detail, and Community Identification detail
all use this endpoint for a visible **Report post** action. The Community detail
adapter submits its exact `postId`; it does not submit the backing scan or
request identifier. `/flag-issue` reuses these database helpers only to preserve
the semantics of the exact report signature emitted by older Community clients.

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
post. An administratively hidden post is unavailable and returns `404`.

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

- Native Explore calls this endpoint. Feed/card owners locally remove reported
  content where they already own that collection; Community detail preserves its
  existing screen and confirms success with feedback.
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
