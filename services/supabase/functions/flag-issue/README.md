# Flag Issue

Backward-compatible identification-dispute ingress. Current iOS has no
`/flag-issue` call site: every visible **Report post** action, including the one
on a Community Identification detail, uses `/report-explore-post` and
`public.explore_post_reports`.

An authenticated owner may still dispute the inference on their own
non-tombstoned scan. `public.submit_owned_flag_issue` admits the review from the
exact owner row, preserves the review-case-before-scan lock order used by Admin,
revalidates ownership under the scan row lock, and commits both mutations
atomically:

1. Insert an identification-review row in `public.flagged_reviews`.
2. Set `public.scans.is_flagged = true` and record the review context in
   `human_intervention_notes`.

The handler derives the reporter from the verified JWT. Legacy `userId` and
`requestId` properties are accepted as untrusted extra fields and never supply
identity or authorization.

## Request

```json
{
  "scanId": "00000000-0000-4000-8000-000000000001",
  "flagReason": "Incorrect species",
  "userSuggestion": "Optional identification context"
}
```

Allowed reasons are `Incorrect species`, `Inappropriate content`,
`Bad image quality`, and `Other`.

## Older Community-client bridge

Older iOS versions sent a Community detail's **Report post** action to this
endpoint with exactly:

- `flagReason = "Inappropriate content"`
- `userSuggestion = "Reported from Community request"`

When the JWT user does not own the scan, only that exact signature can enter the
compatibility bridge. The server resolves the scan's one possible active
Community request, requires its canonical detail projection to be visible to the
viewer, confirms the exact post and scan identifiers, revalidates the post, and
upserts `public.explore_post_reports` through the canonical post-report helper.
It does not insert `flagged_reviews`, set `scans.is_flagged`, or write
`human_intervention_notes`. Any other non-owner request returns `HTTP 404`.

The single-candidate lookup is guaranteed by the schema: `explore_posts.scan_id`
and `explore_community_requests.post_id` are both unique, so one scan can map to
at most one Community request.

## Ownership

- `index.ts` owns bounded JSON parsing, input validation, response mapping, and
  the explicit owner-versus-compatibility routing decision.
- `db.ts` owns the atomic owner-RPC adapter, the exact legacy signature policy,
  and fail-closed Community visibility resolution. It performs no sequential
  scan/review writes.
- `../report-explore-post/db.ts` remains the only Edge owner of post
  reportability validation and `explore_post_reports` upserts.
- `20260831120000_submit_owned_flag_issue_atomically.sql` introduces row
  locking, scan ownership validation, and the atomic identification-review
  mutation.
- `20260901032158_repair_owned_flag_issue_insert_detection.sql` installs the
  final routine definition. It detects the conditional insert through
  `ROW_COUNT`, preserving `service_role`'s INSERT-only access to
  `flagged_reviews`.

## Verification

- `db_test.ts` covers atomic-RPC results and errors, the exact compatibility
  fingerprint, unique request resolution, exact request/post/scan matching, and
  fail-closed lookup/projection failures.
- `_tests/flagIssueMigrationContract.test.ts` locks the transaction, ownership,
  row-lock, and service-only ACL contract.
- `_tests/jsonEndpointSecurityCoverage.test.ts` prevents sequential Edge writes
  and verifies that the compatibility post upsert occurs only after owner and
  Community visibility checks.
- `tests/flag_issue_submission_security.sql` runs on a fully migrated disposable
  catalog and proves execution ACLs, owner/non-owner/tombstone outcomes, review
  grouping, scan context, and rollback of the review plus case when a scan
  update fails.

## Release order

Apply and verify `20260831120000_submit_owned_flag_issue_atomically.sql` and
`20260901032158_repair_owned_flag_issue_insert_detection.sql` before deploying
the changed Function bundle. A source-only or database-skipped test run is not
release evidence. The controlled-target smoke and rollback contract lives in the
[Supabase deployment runbook](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#flag-issue-compatibility-release-order).
