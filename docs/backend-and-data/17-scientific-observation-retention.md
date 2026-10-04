# Scientific Observation Retention

This document is the normative product and engineering contract for scientific
observations after Naturebook account deletion. The scientific-coordinate policy
was installed by
`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`;
subsequent review guards and the prepared October 2 history changes also affect
the current account-detachment boundary described below.

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

The legacy tombstone routine uses an explicit clearing list. Unlisted scan
columns are left unchanged by that routine, but row triggers can additionally
clear or reset fields. In particular, owner-bound review authority does not
survive detachment. Every new column needs an explicit privacy/scientific
classification and review of the routine, triggers, tests, policies and this
document; absence from the clearing list is not approval to retain private data.

The prepared observation-history schema does not change this legacy retention
classification. Its private children are removed on account detachment. History
enrollment remains disabled until the RFC's explicit scientific-field allowlist
and acknowledged-state materializer replace this clearing-list approach for
enrolled observations. Copying private result JSON into retained scientific data
is not permitted by that future contract.

| Action                               | Data                                                                                                                                                                                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Detach                               | `user_id` becomes `NULL`; `is_tombstoned` becomes `TRUE`                                                                                                                                                                                                                        |
| Clear from the scan                  | image, video, and audio URL arrays; `captured_media`; semantic location; public location label; device locale and time zone; user observation context; custom tags; free-form human-intervention notes                                                                          |
| Retain unchanged                     | scan identifier; exact and privacy-projected coordinates; coordinate uncertainty; elevation; observation time; taxonomy and taxonomy version; original AI identification and confidence; environmental and biological measurements; scientific quality and provenance facts     |
| Clear or reset through review guards | `ai_identification_review`, `confirmed_species_identity`, `confirmed_species_id`, and `user_identification_override` become null; `user_confirmed_identification` becomes false and `user_review_state` becomes `unreviewed`; the verified identity revision remains            |
| Delete with the account              | public profile and attribution, authentication identity after verified cleanup, Explore/community content, avatars, exports, stored media objects, personal library/collection state, and other account-owned rows governed by their existing foreign keys and cleanup routines |

**Documentation correction — October 2, 2026:** Earlier text described all
confirmation and review state as retained unchanged. That does not match
`internal.guard_scan_verified_species_review()` from the September 29 migration
or `internal.guard_scan_ai_identification_review()` from the October 1
migration. Those existing guards perform the resets above; the history
preparation did not introduce them. Preserving permitted acknowledged
identification facts for the future history model therefore requires an explicit
allowlisted scientific projection before detachment and child cleanup. The
current implementation does not fulfill that future materialization contract,
and enrollment must remain closed. See the
[RFC implementation status](../rfcs/reversible-reanalysis-and-identification-history-2026-10-02.md#implementation-progress).

Exact coordinates, time, and species can remain personal or sensitive
information even after direct account linkage is removed. Internal and public
documentation must call the row **ownerless** or **account-detached**; it must
not claim that every retained observation is necessarily anonymous or
de-identified.

Historical note: older tombstone routines cleared exact coordinates and
elevation. The current migration prevents that clearing for account deletions
processed after deployment, but it cannot reconstruct coordinates already erased
by a previous routine. A `NULL` coordinate on an older tombstone is not evidence
that the current routine violated this contract.

## Durable deletion sequence

Account deletion remains a durable, claim-fenced workflow:

1. `/safe-delete` derives the target solely from the verified user session and
   records or resumes a private deletion job.
2. `complete_account_deletion_cleanup` creates the idempotent storage-cleanup
   outbox row before calling `apply_user_tombstone`.
3. `apply_user_tombstone` locks the owner before touching scans, using the same
   user-first order as deletion, funding, and prepared history operations. It
   detaches scans, clears the account-owned fields above, and deletes
   `public.users` in the same database transaction.
4. The transaction verifies that no profile or scan still references the deleted
   account UUID.
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

`tests/verified_scan_species_review.sql` and
`tests/identification_rejection.sql` cover owner/tombstone review clearing and
matching job backups. The prepared history fixture additionally verifies
private-child removal on account detachment; it does not prove scientific
allowlist materialization. See the
[history verification matrix](../development-guides/08-testing-strategy.md#observation-analysis-history-preparation).

After production deployment, use the catalog query and staging-only deletion
smoke in
[`06-supabase-deployment-runbook.md`](./06-supabase-deployment-runbook.md#durable-account-deletion-release-gate).

## Prepared history evidence erasure

Private history evidence is not scientific retention data. The prepared receipt
table cascades with history on account detachment; its BEFORE DELETE trigger
materializes an independent erasure obligation first. Scan tombstone insertion
likewise queues both in-flight and ready media. The surviving outbox retains
only an opaque random object UUID and cleanup state, without user linkage or
content. Its future worker replaces content with a verified empty marker so
delayed conditional uploads cannot restore it. Markers and completed opaque
erasure receipts are retained for that purpose; they are not retained scientific
facts. No worker is scheduled and no bucket has been provisioned in this
preparation. Account scientific-field allowlist materialization remains an
activation prerequisite and must occur under the account deletion fence before
private history is removed. See the
[protected evidence lifecycle](05-api-contracts.md#prepared-protected-evidence-lifecycle).

## Prepared child-analysis deletion

Private admitted input, drafts, provider-usage snapshots and completion receipts
cascade with observation history on account detachment. A scan deletion fence
also removes those intents. The deletion trigger releases a still-held
complimentary credit and refunds only a never-dispatched quota reservation;
consumed result credits are not restored. It records each child ID as a
completed ownerless generation marker in `internal.scan_deletion_tombstones`. No
account, observation association, private content or pending cleanup claim
survives in that marker. This prevents legacy UUID reuse after the private
intent disappears. These markers are deletion control data, not scientific
facts. V2 photo receipts are pinned while an intent/result remains live, but
parent/account deletion supersedes that pin. Terminal failure queues unused
photo erasure; generation-bound unbound expiry also handles abandoned ready
uploads. No cleanup scheduler is activated. The scientific
allowlist/materialization activation prerequisite remains unchanged.

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
