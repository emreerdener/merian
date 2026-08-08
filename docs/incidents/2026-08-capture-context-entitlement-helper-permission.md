# Capture Context Entitlement Helper Permission Failure

**Date:** 2026-08-08  
**Severity:** High capture-experience degradation; not a media-durability loss  
**Affected flow:** New-account Capture open/foreground refresh, Field trip Scan
indicator, and first-scan diagnosis  
**Repository status:** Remediated in source  
**Hosted status:** Open until the forward migration and exact-SHA smoke are
complete

## Summary

The supplied Supabase error export contains 23 failed calls to
`get_field_trip_capture_context`. Every HTTP 403 is paired with PostgreSQL
`42501 permission denied for function user_has_effective_pro`.

The complimentary-Pro migration rewrote the capture-context projection from a
raw paid-tier comparison to the server-owned functional-entitlement predicate.
The outer projection deliberately remained `SECURITY INVOKER` and executable
only by `service_role`, while the new private predicate revoked execution from
that same role. PostgreSQL therefore rejected the transitive call before the
projection could return a capture goal.

Candidate validation run 1668 for source SHA
`10f14e19be06e0babce6c2f780212305015bf2e2` applied the helper repair and then
exposed the next missing invoker edge: the database integration test switched
to `SET LOCAL ROLE service_role` and failed with PostgreSQL `42501 permission
denied for table field_trip_checklist_items`. The complete disposable-database
gate stopped. It used no production environment, secrets, or mutations.

Capture remained available because `ActiveCaptureGoalStore` treats this fetch
as non-blocking enrichment and retains the last successful account-scoped
snapshot. New accounts had no cached snapshot, however, so they lost the
starter outing indicator and retried the broken enrichment on later lifecycle
refreshes. That made the most important screen feel unreliable and added noisy
403 traffic while the user was already dealing with a failed first scan.

## Supplied Evidence Classification

The export spans roughly four and a half hours and contains four distinct
failure families. Identifiers, headers, coordinates, and request bodies are
intentionally omitted.

| Paired or grouped evidence | Count | Classification |
| --- | ---: | --- |
| `get_field_trip_capture_context` 403 + `user_has_effective_pro` 42501 | 23 pairs | Confirmed database ACL defect fixed by this incident |
| `reserve_ai_quota` rejection + `ai_consent_required` | 6 pairs | Separate first-scan policy failure; no entitlement or provider quota was consumed |
| `apply_or_stage_scan_context` + `scan ingestion not found` | 2 pairs | Expected early-context race while no ingestion claim existed; local durable context remains authoritative for retry |
| `/auth/v1/user` 403 burst | 14 requests | Session rejection evidence without enough fields to attribute to this scan; do not infer a database ACL cause |

The screenshot shows the saved observation and its local environmental context
behind a **Network timeout** result. The six consent failures are the only
provider-admission failures in the export and occur before Gemini dispatch.
Current source maps the exact handler-owned `403 ai_consent_required` to the
account-scoped disclosure repair instead of automatic retry; that separate
resolution is documented in
[First-Scan Consent-Policy Retry Loop](./2026-08-first-scan-consent-policy-retry-loop.md).

The two deferred-context misses do not mean the observation or media was lost.
`update-scan-context` is permitted to race ahead of server ingestion, returns a
retryable conflict in that state, and the offline queue retains the same context
for a later owner-scoped attempt.

## Root Cause

Migration `20260802235833_three_complimentary_pro_scans.sql` created
`internal.user_has_effective_pro(uuid)`, revoked it from every API role, and
then rewrote functional Field trip gates to call it. Most rewritten callers are
`SECURITY DEFINER` and execute the private predicate as their owner. The capture
projection is intentionally different:

- `public.get_field_trip_capture_context(uuid)` is `SECURITY INVOKER`;
- only `service_role` may execute the public projection; and
- the projection now calls `internal.user_has_effective_pro(uuid)` under that
  invoker role.

The migration preserved the outer RPC grant but omitted both kinds of privilege
needed by its invoker body: `EXECUTE` on the private helper and `SELECT` on the
six source relations. Existing integration coverage called the projection as
the migration owner, whose implicit privileges hid both missing production-role
edges. Once the first forward migration restored helper execution and the test
used the deployed role chain, PostgreSQL correctly stopped at the first missing
source-table read.

## Resolution

Forward migration
`20260808215410_restore_field_trip_capture_entitlement_helper_access.sql`:

1. verifies that the public projection still exists as an invoker and still
   depends on the expected private definer predicate;
2. fails closed if either routine or security shape drifted;
3. revokes the helper from `PUBLIC`, `anon`, `authenticated`, and
   `service_role`; then
4. grants only `EXECUTE` back to `service_role`.

Forward migration
`20260808230028_restore_field_trip_capture_context_source_reads.sql`:

1. verifies the projection still exists, remains an invoker, calls the expected
   entitlement helper, and names the expected source relations;
2. fails closed if its routine, security mode, source shape, or execute ACL has
   drifted; and
3. grants `service_role` only `SELECT` on `users`, `user_field_trips`,
   `field_trip_templates`, `field_trip_levels`,
   `user_field_trip_item_completions`, and `field_trip_checklist_items`.

The repairs do not expose `internal` through the Data API, broaden the public
RPC, add table mutation privileges, change a response payload, duplicate
entitlement logic, or convert the outer projection to `SECURITY DEFINER`.

## Regression Coverage

- The static migration contracts fix the exact helper dependency and six-table
  read allowlist, reject additional `service_role` grants, and reject a
  redefinition of the outer projection.
- The complimentary-entitlement pgTAP fixture requires helper execution for
  `service_role` and denies it to `anon` and `authenticated`.
- The capture-context database integration test now switches to
  `SET LOCAL ROLE service_role` before invoking the projection, then verifies
  all six source reads in the catalog. This reproduces the deployed role chain
  instead of relying on owner privilege.
- The existing payload assertions continue to exclude scan IDs, media,
  locations, notes, and completed species evidence.

## Release Verification

Do not mark this incident released until one exact candidate proves:

1. full migration replay and the static, pgTAP, privileged-routine, and capture
   context database gates pass on disposable PostgreSQL 17;
2. `anon` and `authenticated` cannot execute either the private helper or the
   public capture projection;
3. `service_role` has `SELECT` on all six reviewed source relations and can
   execute the public projection through the real invoker chain for a newly
   enrolled account;
4. the authenticated `field-trips` `capture_context` action returns HTTP 200
   with the fixed handler marker and no private evidence;
5. a clean-install first scan separately proves authoritative consent upload,
   refetch, exactly one provider dispatch, and a usable saved result; and
6. aggregate logs no longer contain the paired helper-permission signature
   after propagation.

Applying the migration is a hosted production mutation and remains part of the
reviewed GitHub deployment workflow; repository implementation alone does not
prove customer recovery.
