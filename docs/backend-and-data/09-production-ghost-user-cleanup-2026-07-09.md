# Production Ghost User Cleanup - 2026-07-09

## Summary

On 2026-07-09, production Supabase anonymous ghost users were audited and old
empty ghosts were removed using the guarded audit and cleanup scripts in
`services/supabase/scripts/`.

No active anonymous users or real accounts were targeted. The cleanup criteria
required every deleted user to be:

- anonymous in Supabase Auth
- older than 30 days
- classified as `likely_empty_ghost_candidate_30d`
- not allowlisted
- without email or non-anonymous provider identity
- without paid/pass state
- without scans, collections, Explore activity, follows/blocks, feedback, chat,
  field trips, ingestion jobs, or other audited activity
- without custom public identity

This historical run predates the secure account-upgrade handoff table. Current
cleanup has two additional mandatory protections: the audit treats prepared
handoffs and merged receipts awaiting Auth cleanup as activity, and execute mode
acquires a live tokenized reservation under the same advisory lock as handoff
issuance. Never reuse the 2026-07-09 script revision against the current schema.

## Production Counts

| Step | Total rows | Real accounts | Active ghosts | Likely empty ghosts | Old empty candidates | Recent empty ghosts |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Initial audit | 518 | 6 | 123 | 389 | 378 | 11 |
| After first 10 deletes | 508 | 6 | 123 | 379 | 368 | 11 |
| After next 50 deletes | 458 | 6 | 123 | 329 | 318 | 11 |
| After next 100 deletes | 358 | 6 | 123 | 229 | 218 | 11 |
| Final audit | 140 | 6 | 123 | 11 | 0 | 11 |

## Cleanup Batches

| Batch | Snapshot candidates | Selected | Auth users deleted | Public users deleted | Failures |
| --- | ---: | ---: | ---: | ---: | ---: |
| Batch 1 | 378 | 10 | 10 | 0 | 0 |
| Batch 2 | 368 | 50 | 50 | 0 | 0 |
| Batch 3 | 318 | 100 | 100 | 41 | 0 |
| Final batch | 218 | 218 | 218 | 217 | 0 |
| Total | 378 | 378 | 378 | 258 | 0 |

Note: the first batch was run before cleanup reporting was tightened and its
terminal output over-counted public cleanup requests. Those first 10 candidates
were auth-only (`public_user=no`), so the table above records the corrected
public-row deletion count. The final database state is verified by the final
audit.

## Local Artifacts

The production run wrote local audit and cleanup artifacts under `/tmp/`:

- `/tmp/ghost-users-final.md`
- `/tmp/ghost-users-final.csv`
- `/tmp/ghost-users-final.json`
- `/tmp/ghost-cleanup-result.json`
- `/tmp/ghost-cleanup-result-50.json`
- `/tmp/ghost-cleanup-result-100.json`
- `/tmp/ghost-cleanup-result-final.json`

These files may contain production user IDs and should not be committed.

## Follow-Up

- Keep the Debug-simulator production Supabase warning enabled. It is
  intentionally diagnostic rather than blocking, so developers must still use
  local/staging for routine work and avoid fresh installs or cleared sessions
  during production smoke tests.
- Set `MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1` only for a
  deliberate production smoke run. The override suppresses the warning; it does
  not prevent anonymous-user creation or redirect writes.
- Use staging or local Supabase for routine simulator testing.
- Leave the 11 recent empty ghosts alone until they age past the threshold and a
  fresh audit confirms they remain empty.
- Re-run the audit before any future cleanup batch.
- Use only the current guarded cleanup implementation. Confirm
  `list_protected_ghost_profile_merge_sources`,
  `reserve_ghost_user_bulk_cleanup`, and `finish_ghost_user_bulk_cleanup` are
  service-role-only before execute mode.
