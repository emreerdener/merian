# Safe Account Deletion

Executes the irreversible account-deletion protocol for the user established by
the verified request session. It deletes account-owned data while preserving
mandatory ownerless Scientific Data. The caller cannot nominate another user ID.

The normative retained-versus-cleared field boundary and its change procedure
live in the
[scientific-observation retention contract](../../../../docs/backend-and-data/17-scientific-observation-retention.md).

## Durable state machine

Migration `20260725030308_durable_account_deletion.sql` replaces the former
Auth-first sequence with a private `internal.account_deletion_jobs` state
machine. Migration `20260725052337_enforce_account_storage_erasure.sql` makes
verified R2 erasure a required durable phase: Migration
`20260806203700_durable_apple_provider_revocation.sql` adds a claim-fenced
provider substage after storage and before Auth.

Migration `20260813053000_add_account_deletion_recovery_capabilities.sql` adds
an identity-free recovery proof for the request/response crash boundary. The
server stores only a SHA-256 hash, binds it to the deletion job in the same
transaction as intake, and exposes recovery through the separate public
`/recover-account-deletion` route. The proof never identifies or selects an
account.

Migration `20260810034953_guard_empty_ghost_account_cleanup.sql` adds a second,
operator-only intake for prelaunch anonymous shells. It does not change this
state machine or expose `/safe-delete` to arbitrary UUIDs. After an offline
review and live GET-only RevenueCat proof, the service-only intake reruns an
exhaustive database blocker check, records identity-free operator evidence, and
atomically performs steps 1–3 below. It must stop at `storage_pending`; this
worker remains the only path through delayed R2 verification and eventual Auth
deletion. RevenueCat customer deletion is a later, separate orphan-shell
operation and is never performed by the guarded intake.

Migration `20260725035737_repair_tombstone_profile_seed.sql` is an explicit
executable no-op compatibility bridge for production run 1461. Its superseded
public-only sentinel insert could not satisfy production's
`public.users.id → auth.users.id` foreign key. Migration
`20260725041308_ownerless_account_deletion_tombstones.sql` is the forward fix:
retained scans become ownerless tombstones and no synthetic Auth or public user
is created. Migration
`20260731154139_retain_scientific_coordinates_after_account_deletion.sql`
supersedes its coordinate-clearing routine: exact coordinates, elevation, time,
taxonomy, identification, environmental, quality, and provenance facts are now
mandatory retained Scientific Data. A validated constraint permits a null scan
owner only for a tombstone. The public profile's restrictive Auth foreign key
also rejects any Auth-first delete until cleanup has removed that profile. The
scan-ingestion replay worker treats an ownerless tombstone as terminal and never
dispatches another AI request for it.

1. `request_account_deletion_with_recovery(user_id, secret_hash)` inserts or
   returns the active `pending` job and atomically binds the caller's
   server-hashed recovery proof. Legacy callers retain the service-only
   `request_account_deletion(user_id)` compatibility path. This durable receipt
   is always the first mutation. It records Apple provider work as `pending`,
   `manual_required`, or `not_required` and returns the durable manual-fallback
   disposition. It first locks the Auth user and rejects either side of a bound
   sign-out purchase handoff with `409 purchase_continuity_pending`; no deletion
   job is written in that case. An unbound proof does not strand deletion if its
   device is lost: deletion may win before binding, and the reciprocal bind path
   then rejects the active deletion job before any RevenueCat identity mutation.
2. `claim_account_deletion_jobs(...)` assigns a five-minute UUID lease using
   `FOR UPDATE SKIP LOCKED`.
3. Every account claim, including a later `auth_pending` retry, calls
   `complete_account_deletion_cleanup(job_id, claim_token)`. It writes the
   idempotent storage job, first locks and detaches any stable purchase
   principal in the resolver's principal-first order, clears the deleting
   account as grant owner, and permanently freezes provider-promotion import.
   Account-owned grants are erased; the non-identifying StoreKit principal
   remains available to the same installation after signed-out resolution.
   Cleanup then calls `apply_user_tombstone` and verifies that no public profile
   or scan still references the user. Tombstoning clears every scan media
   URL/manifest, semantic location and public label, device context, custom tag,
   and free-form intervention field before making the retained observation
   ownerless. Exact coordinates and all other scientific facts are left
   unchanged. Until storage is verified the job is `storage_pending`, with no
   account-worker lease.
4. `claim_pending_storage_deletions(...)` leases bounded R2 prefix pages. The
   worker claims at most four rows per Edge invocation, deletes at most 50 keys
   per page with eight deletes in flight, and traverses the user's free/pro
   media, staging, avatar, and export prefixes. The four-page ceiling keeps
   provider timeout waves within the Edge wall-clock budget; later cron runs
   resume remaining rows. Cursor advancement is claim-fenced and monotonic.
5. After the first complete sweep, the outbox waits 25 hours—longer than any
   pre-intake staging PUT signature—then repeats all five prefixes as a
   verification sweep. New upload signatures are denied while deletion is
   active. Only an empty terminal verification may mark storage `completed` and
   transactionally wake the account job as `auth_pending`.
6. If the job has a stored Apple credential, `auth_pending` first returns
   `provider_revocation_pending`. The worker reads the Vault refresh token only
   under the active UUID claim, calls Apple's `/auth/revoke`, and accepts only
   HTTP `200`. One database transaction then deletes the credential mapping,
   token-free registration receipts, and Vault secret before marking the
   provider stage complete. Failure preserves both token and Auth for retry.
   Legacy Apple accounts without a captured token are marked `manual_required`;
   this is an explicit fallback disposition, not an automatic-revocation claim.
7. Only an `auth_pending` claim with completed storage and resolved provider
   disposition, and with no remaining Apple credential, may call
   `supabaseAdmin.auth.admin.deleteUser`. HTTP `404` and exact Auth code
   `user_not_found` are idempotent success.
8. `finish_account_deletion_attempt(...)` independently rechecks the completed
   storage receipt and provider fence, then either records `completed` and
   erases the terminal job's direct user UUID, or releases the lease with
   bounded database-calculated backoff.

The initiating request tries the relational phase synchronously. A new request
normally returns `202` because delayed storage verification is deliberately
asynchronous; `200` is possible only when an already verified idempotent job can
finish immediately. Both are successful responses and contain the required
boolean `manual_provider_revocation_required`. The iOS client persists a legacy
Apple notice before it signs out locally and purges its local store. Before
dispatch, supporting clients atomically persist and verify distinct 256-bit
recovery and acknowledgement capabilities. They persist
`capability_preparation_pending`, invoke the non-destructive v2 prepare, persist
`capability_prepared_pending`, then persist `capability_intake_pending` before
commit. A crash before commit publicly cancels the preparation as
`not_committed` without signing out or erasing local data. A received durable
receipt advances the marker to `capability_cleanup_pending`; only then may iOS
sign out locally and purge SwiftData. After both finish, the public recovery
route records acknowledgement, iOS advances to `capability_retirement_pending`,
read-after-delete verifies Keychain removal, and finally clears the marker. The
Edge boundary hashes the two v2 values in separate recovery and acknowledgement
domains; neither hash can be replayed through the legacy v1 namespace or through
the other v2 operation. For legacy v1, `500`, transport failure, public-recovery
`404`, or unknown proof never proves that intake failed: the database mutation
may still be committing, so the client retains both proof and barrier. In v2, an
unknown proof proves no commit because destructive intake requires the
preparation. If another device commits first, the deletion-job insert trigger
converts only still-live preparations into receipts. Expired proof hashes move
to a permanent identity-free tombstone and can never be reused. An expired
preparation with no committed deletion returns `not_committed`; one retired
during another device's deletion commit returns the distinct fail-closed
`410 account_deletion_recovery_preparation_expired`, which does not authorize
local erasure. Only a 180-day capability actually bound to a job returns
`410 account_deletion_recovery_expired`; that positive match permits
conservative local erasure but not pre-cleanup inspection. Post-cleanup
acknowledgement uses only the independent second proof, remains valid after
expiry, and converts the row to a permanent replay receipt. Late duplicate
authenticated intake returns that permanent receipt without clearing
acknowledgement or extending its original expiry. Only explicit
`409 purchase_continuity_pending` proves this intake did not win. iOS first
persists `capability_rejection_retirement_pending`, then read-after-delete
verifies removal of the unused proof before removing the marker. Relaunch from
that phase performs no local sign-out or data purge. Pre-capability
`intake_pending` and `cleanup_pending` markers remain supported for
installed-client compatibility.

This response addition is not usable by older binaries that do not decode the
boolean. They can accept the deletion response while silently omitting Apple's
manual-removal notice. Public rollout is therefore blocked until either a
minimum-supported-build control gives those clients a clear update path back to
in-app deletion, or an independent server-delivered fallback durably supplies
the instructions. Publishing the supporting build alone is not rollout evidence.

The scheduled `reconcile-account-deletions` function resumes due account jobs
and storage pages every five minutes. It performs a bounded account pass,
bounded storage pass, then a second account pass only when storage completed in
that invocation. Its bounded preparation pass writes both hashes from every
selected expired non-destructive preparation to the permanent identity-free
tombstone ledger before removing the preparation. The exact authenticated
`{ "dry_run": true }` mode returns before creating a database client or invoking
any of those workers and is reserved for deployment validation. Recovery hashes
bound to jobs are permanent idempotency receipts: an acknowledgement response
can be lost, so neither acknowledged nor expired proofs are age-pruned. The
table is capped at eight hashes per deletion job, contains no raw proof or
account identity, and a completed parent job has already removed its user UUID.
This lets an arbitrarily offline client receive a stable replay instead of an
ambiguous missing-proof response. A crashed worker cannot clear or finish
another worker's claim, and a lost success response is safe: the reaper sees
either a completed row or an `auth_pending` job whose already-deleted Auth
identity resolves as idempotent success.

An internal `BEFORE INSERT` trigger rejects recreation of `public.users` while a
deletion job is active. This prevents Auth metadata synchronization or a trusted
backend upsert from resurrecting a profile between verified cleanup and the
external Auth deletion.

## Authorization and data minimization

All account and storage state-machine RPCs plus `apply_user_tombstone(uuid)` are
public-schema discovery names, not client-callable APIs. Execution is revoked
from `PUBLIC`, `anon`, and `authenticated`; only the reviewed `service_role`
allowlist can execute them, and every routine calls
`internal.require_service_role()`. The private job and outbox tables have RLS
enabled and no direct API-role privileges. The same controls cover
`internal.account_deletion_recovery_capabilities`,
`internal.account_deletion_recovery_preparations`,
`internal.account_deletion_expired_preparation_proofs`, and their prepare,
commit, recover, acknowledge, prune, and aggregate-health RPC surfaces. The
public recovery Edge route accepts only one high-entropy proof and its exact
operation; it never accepts Auth, account, job, or provider identifiers.

The same denial applies to `internal.apple_sign_in_revocation_credentials` and
`internal.apple_sign_in_credential_registrations`. The former references
`auth.users` with `ON DELETE RESTRICT`, so Auth Admin cannot bypass provider
revocation. Apple registration, claimed token read, and provider completion are
available only through four in-body-authorized, service-role-allowlisted RPCs.

Do not accept a target UUID from either HTTP body. `/safe-delete` derives it
only from the verified session; the service reaper claims targets only from the
database. Active jobs retain the UUID only while work remains. Completion sets
the job's `user_id` to `NULL`; the storage-cleanup outbox retains the identifier
only for its separate cleanup lifecycle.

## Operations

The independent `.github/workflows/account-deletion-health-monitor.yml` schedule
is the primary stuck-job/SLA alert. It calls the aggregate service-only
`get_account_deletion_health()` and `get_account_deletion_recovery_health()`
RPCs rather than the reconciler itself and does not use the reaper's Vault
values. Its defaults are:

- warning at 10 minutes and critical at 30 minutes for oldest claimable work;
- warning at 27 hours and critical at 36 hours for oldest active deletion,
  allowing for the mandatory 25-hour delayed storage verification;
- warning at 25 and critical at 100 active jobs;
- warning when any job has eight active recovery proofs and critical above that
  invariant, or when any unacknowledged proof has exceeded its recovery window;
- critical when the cron is disabled, its URL/service credential is absent, or
  an active storage row has no valid private deletion owner; and
- warning when a retry error or expired lease is present.

The workflow fails on warning by default and uploads bounded JSON and Markdown
summaries without user identifiers. Treat a failed scheduled run itself as an
operational alert; GitHub scheduling is intentionally independent of the
database reaper.

Credential handling follows the same key-format policy on both paths. The
database cron reads the effective server key from Vault and
`internal.server_api_request_headers(text)` sends a current `sb_secret_...`
value only in `apikey`, or a validated legacy HS256 `service_role` JWT in both
`apikey` and Bearer Authorization. The independent monitor uses the same rule. A
publishable, anon/user, malformed, or blank value fails closed rather than being
formatted as privileged transport. A blank Vault value also wins over the legacy
app-setting fallback and is reported as critical. The aggregate
`reaper_credentials_configured` value verifies nonblank effective values, not a
successful request. Manually dispatch the monitor after deployment and inspect
recent reaper cron requests to validate both independent paths.

Structured log alerts remain useful for immediate dependency failures:

- `account_deletion_attempt_deferred`
- `account_deletion_reconciliation_deferred`
- `account_storage_erasure_deferred`

Provider dependency failures appear under `account_deletion_attempt_deferred`
with stage `provider`. They remain in the existing `auth_pending` health
envelope and contribute to the retry-error aggregate. The immediate handler and
reaper use the identity-safe logging boundary: account, job, storage-deletion,
provider-customer, token, URL, and raw error values are never emitted.

Do not manually delete an Auth user to recover a pending job. Repair the
underlying cleanup failure and invoke the service reaper. For a legacy
Auth-first incident that predates this migration, an operator may create a
durable job for the recorded UUID through the service-only intake RPC, then run
the reaper. Review the target and current relational state before doing so. Do
not create an all-zero Auth/profile sentinel or weaken the profile foreign key;
ownerless tombstones are the only supported retained-observation state.

The permanent scientific record is a condition of submitting a scan, not an
account-deletion option. The retained row has no account UUID and remains
excluded from personal and broad anonymous scan policies. Exact coordinates are
available only through reviewed backend scientific access; public and export
projections continue to apply geoprivacy and sensitive-taxon rules.

## Source layout

- `index.ts` owns verified-session and POST-only routing.
- `protocol.ts` owns the exact legacy/capability request union and proof syntax.
- `handler.ts` persists intake and maps immediate versus queued success.
- `worker.ts` owns cleanup-before-provider-before-Auth ordering, retries, and
  claim recovery.
- `db.ts` owns account/provider RPC wrappers and idempotent Auth Admin deletion.
- `../register-apple-revocation-token/` owns authenticated authorization-code
  exchange and Vault registration; `../_shared/appleSignIn.ts` owns Apple JWT,
  token exchange, and revocation transport.
- `storageDb.ts` owns claim-fenced storage-outbox RPC wrappers.
- `storageWorker.ts` owns bounded R2 list/delete/verification processing.
- `reconcile-account-deletions/handler.ts` owns service authentication, exact
  non-mutating deployment dry-run parsing, and the scheduled bounded account,
  storage, and expired-preparation passes; its `index.ts` is only the server
  entrypoint.
- `../recover-account-deletion/` owns public proof recovery and acknowledgement
  without an Auth session.
- `../../scripts/monitor_account_deletion_health.ts` reads the aggregate health
  RPC, applies deletion-SLA policy, and writes bounded operator evidence.

Focused source, migration-contract, and pgTAP tests live in
`functions/_shared/appleSignIn_test.ts`,
`functions/register-apple-revocation-token/handler_test.ts`,
`functions/_tests/safeDelete.test.ts`,
`functions/_tests/accountDeletionCoverage.test.ts`,
`functions/_tests/accountDeletionMigrationContract.test.ts`, and
`tests/account_deletion_security.sql`. Request parsing, adapter hashing, and
public recovery behavior are covered by `safe-delete/protocol_test.ts`,
`safe-delete/db_recovery_test.ts`, and
`recover-account-deletion/handler_test.ts`. The authenticated no-work reaper
probe and ordinary bounded invocation are covered by
`reconcile-account-deletions/handler_test.ts`. R2 page and deadline behavior is
covered by `_shared/aws_test.ts` and `safe-delete/storageWorker_test.ts`;
monitor parsing, thresholds, severity, and recovery guidance are covered by
`scripts/monitor_account_deletion_health_test.ts`.

See the
[canonical Sign in with Apple deletion contract](../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md)
for secret provisioning, rotation, client rollout, and production smokes.
