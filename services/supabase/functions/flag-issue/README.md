# Flag Issue

The identification-review queue ingress. This endpoint is triggered whenever a
user highlights a scan inside the iOS `ReportInsightView` as biologically
incorrect, inappropriate, or malicious.

The module explicitly handles:

1. Inserting an identification-review row into the `flagged_reviews` Postgres
   schema with the reviewer's context mapping.
2. Tagging the global `scans` table row with `is_flagged = true`, applying the
   user's taxonomy suggestion to `human_intervention_notes` for Admin Dashboard
   review.

Explore post-content reports must use `/report-explore-post` and
`explore_post_reports`; they must never call this function or change
`scans.is_flagged`.

## Architecture

To enforce clean routing boundaries, the logic is decoupled:

- **`index.ts`**: The strict HTTP orchestrator. It safely catches `.json()`
  parse anomalies, drops invalid payloads via the centralized `requireParams`
  guard (`scanId` and `flagReason` required), and cascades into the dual
  database writes natively.
- **`db.ts`**: Executes the explicit `insert` onto `flagged_reviews` and the
  `update` query across `scans.is_flagged`. If either schema throws a PostgreSQL
  constraint error, the transaction violently bubbles the failure up to the Edge
  Handler boundary.
