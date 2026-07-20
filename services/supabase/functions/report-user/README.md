# `report-user` Edge Function

Authenticated Explore viewers can report a visible, non-self author profile.
The function does not block the target, hide content, change abuse state, or
resolve a review case automatically.

## Request

`POST /functions/v1/report-user`

```json
{
  "reported_user_id": "00000000-0000-0000-0000-000000000000",
  "reason": "Harassment",
  "details": "Optional context, at most 1,000 characters."
}
```

Accepted reasons are exactly:

- `Spam`
- `Harassment`
- `Impersonation`
- `Inappropriate profile`
- `Other`

`reported_user_id` and `reason` are required. `details` is optional, trimmed,
and capped at 1,000 characters.

## Response

Success returns HTTP 200:

```json
{
  "success": true,
  "reported_user_id": "00000000-0000-0000-0000-000000000000",
  "message": "Report submitted for moderation."
}
```

Expected failures include:

| Status | Meaning |
|---:|---|
| 400 | Invalid UUID/reason/details or self-report |
| 401 | Missing, invalid, or expired Naturebook authentication |
| 404 | Target is not a reportable profile visible to this viewer |
| 500 | Intake persistence failed |

## Security and persistence

`verify_jwt = false` in `config.toml` because this endpoint uses the repository's
shared custom Edge authentication wrapper; it is not an unauthenticated
function. `withEdgeHandler` validates the request and supplies the authenticated
user plus server-side Supabase client.

Before writing, `requireReportableUser` calls the same
`get_explore_author_profile` database projection used by the profile endpoint.
This prevents arbitrary UUID reporting and applies shadowban, blocking, public
profile discoverability, and post/Field trip visibility rules. Self-reports are
rejected before database access.

The service-role client upserts one `public.user_reports` row per
`(reporter_user_id, reported_user_id)`. The upsert deliberately omits `status`,
so repeat evidence updates `reason`, `details`, and `updated_at` without
resetting a terminal moderator state. The insert trigger attaches a new source
to the grouped private user review case; the review-case reopening rule is based
on an independent reporter, not a repeat submission by the same reporter.

Browser roles have no direct grants on `public.user_reports`.

## Related client contract

`get-explore-author-profile` returns `viewer_can_report = true` only for a
reportable non-self profile. The iOS overflow action displays the reason/detail
form, handles loading/error/success state, and does not automatically block the
reported user.

## Verification

```bash
deno test \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/report-user/db.test.ts
```

Database integration coverage is in
`services/supabase/tests/admin_review_ai.sql`.

