# Scientific Observation Retention

This document is the normative product and engineering contract for scientific
observations after Naturebook account deletion. It describes the current
database behavior installed by
`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`.

## Product invariant

Every scan submitted for identification contributes a scientific observation to
the Naturebook database. Retaining the scientific observation is a mandatory
condition of submission and use of the Service. It has no separate opt-in or
opt-out and does not use a parallel retention table.

Account deletion removes the account, account attribution, account-owned
content, and stored media. It does not delete the contributed scientific facts.
The existing `public.scans` row becomes an ownerless tombstone and remains in
the restricted backend.

Individual scan deletion is a separate user action. Under the current product
contract, that workflow generation-fences the scan, erases its media, and
deletes the scan row. This document governs account deletion, not explicit
individual scan deletion.

## Account-tombstone data boundary

The tombstone routine uses an explicit clearing list. Every unlisted scan column
is retained unchanged. New scan columns therefore default to scientific
retention until their privacy and scientific classification is reviewed and the
routine, tests, policies, and this document are deliberately updated.

| Action | Data |
| --- | --- |
| Detach | `user_id` becomes `NULL`; `is_tombstoned` becomes `TRUE` |
| Clear from the scan | image, video, and audio URL arrays; `captured_media`; semantic location; public location label; device locale and time zone; user observation context; custom tags; free-form human-intervention notes |
| Retain unchanged | scan identifier; exact and privacy-projected coordinates; coordinate uncertainty; elevation; observation time; taxonomy and taxonomy version; identification, confidence, confirmation, and review state; environmental and biological measurements; scientific quality and provenance facts |
| Delete with the account | public profile and attribution, authentication identity after verified cleanup, Explore/community content, avatars, exports, stored media objects, personal library/collection state, and other account-owned rows governed by their existing foreign keys and cleanup routines |

Exact coordinates, time, and species can remain personal or sensitive
information even after direct account linkage is removed. Internal and public
documentation must call the row **ownerless** or **account-detached**; it must
not claim that every retained observation is necessarily anonymous or
de-identified.

Historical note: older tombstone routines cleared exact coordinates and
elevation. The current migration prevents that clearing for account deletions
processed after deployment, but it cannot reconstruct coordinates already
erased by a previous routine. A `NULL` coordinate on an older tombstone is not
evidence that the current routine violated this contract.

## Durable deletion sequence

Account deletion remains a durable, claim-fenced workflow:

1. `/safe-delete` derives the target solely from the verified user session and
   records or resumes a private deletion job.
2. `complete_account_deletion_cleanup` creates the idempotent storage-cleanup
   outbox row before calling `apply_user_tombstone`.
3. `apply_user_tombstone` detaches scans, clears the account-owned fields above,
   and deletes `public.users` in the same database transaction.
4. The transaction verifies that no profile or scan still references the
   deleted account UUID.
5. The storage worker cursor-sweeps all canonical R2 prefixes and completes a
   delayed empty verification pass.
6. Only verified `auth_pending` work can delete the Supabase Auth identity.
7. The scheduled reconciler resumes interrupted jobs, while the independent
   health monitor alerts on missing configuration, expired leases, failures,
   overdue work, and backlog.

The backend does not delete the Supabase Auth identity before relational cleanup
and storage erasure have been verified. A transient failure leaves durable work
for the reaper rather than changing the scientific-retention boundary.

## Generation-race protection

An account deletion can encounter a scan that already has an individual-scan
deletion fence. `internal.reject_deleted_scan_generation_mutation()` permits
only one account-detachment transition in that state:

- the old owner is non-null and the new owner is null;
- the new row is tombstoned;
- every account-owned field is empty or null; and
- complete `OLD` and `NEW` rows are identical after subtracting only the
  account-detachment columns.

This complete-row comparison fails closed for current and future scientific
columns. After detachment, delayed updates cannot rewrite exact coordinates or
other retained facts. The individual-deletion fence is terminalized without an
owner, so a delayed individual-deletion completion is idempotent and cannot
delete the retained observation.

## Authorization and visibility

`public.apply_user_tombstone(UUID)` is `SECURITY DEFINER`, has an empty fixed
`search_path`, uses schema-qualified objects, and calls
`internal.require_service_role()`. `EXECUTE` is revoked from `PUBLIC`, `anon`,
and `authenticated`; only `service_role` receives the explicit grant. The
generation trigger function is executable by no API role.

`public.scans` keeps RLS enabled. The broad anonymous/open scan policy requires
`is_tombstoned = FALSE`, so ownerless tombstones do not appear through ordinary
anonymous or authenticated table reads, personal libraries, public Explore
surfaces, or account attribution. Service/secret keys remain backend-only
because they bypass RLS.

Geoprivacy controls public presentation and distribution; it does not mutate or
erase the retained exact backend coordinates. Sensitive-taxon, public-map,
research-export, and partner-sharing boundaries must continue to project or
withhold coordinates independently. The launch-disabled DwC-A feature remains
subject to its separate release gate before any archive generation or delivery
is enabled.

## Change procedure

Any change to the tombstone boundary must update one release unit:

1. a forward migration replacing the affected routine or trigger;
2. service-only authorization and explicit function ACLs;
3. fresh-catalog pgTAP behavior and static migration contracts;
4. Terms, Privacy Policy, Privacy Choices, location permission, and deletion
   confirmation copy;
5. schema, API, architecture, operational, testing, and changelog documents;
6. App Store privacy disclosures and qualified counsel review where applicable;
   and
7. production catalog and staging-account smoke evidence.

Do not edit an applied migration, introduce an all-zero synthetic user, move
exact coordinates into a public projection, weaken tombstone RLS, or add a
parallel retention table to work around the current contract.

## Verification

Run the repository contracts:

```bash
make validate-supabase-migrations

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/scripts,services/supabase/tests/account_deletion_security.sql,services/supabase/config.toml,.github/workflows \
  services/supabase/functions/_tests/accountDeletionMigrationContract.test.ts \
  services/supabase/functions/_tests/accountDeletionCoverage.test.ts

node --test apps/web/lib/scientificRetentionContract.test.ts
```

Fresh-catalog CI must also execute `tests/account_deletion_security.sql`. Its
fixture verifies retained exact coordinates, elevation, uncertainty, time,
weather, and confidence; cleared account fields and media; tombstone exclusion
from anonymous reads; service-only ACLs; collision-fence behavior; rejected
stale coordinate writes; and idempotent delayed individual-deletion completion.

After production deployment, use the catalog query and staging-only deletion
smoke in
[`06-supabase-deployment-runbook.md`](./06-supabase-deployment-runbook.md#durable-account-deletion-release-gate).

## Related documents

- [Supabase Edge and database architecture](./02-supabase-edge-and-database.md)
- [Database schema](./04-database-schema.md)
- [API contracts](./05-api-contracts.md)
- [Supabase deployment runbook](./06-supabase-deployment-runbook.md)
- [Server credentials and database release safety](./13-server-credentials-and-database-release-safety.md)
- [Terms counsel and release review](../legal/terms-counsel-review.md)
- [Public Terms of Service](../../apps/web/app/terms/page.tsx)
- [Public Privacy Policy](../../apps/web/app/privacy/page.tsx)
- [Public Privacy Choices](../../apps/web/app/privacy-choices/page.tsx)
