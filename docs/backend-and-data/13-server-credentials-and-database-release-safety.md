# Server Credentials and Database Release Safety

**Status (2026-07-27):** Canonical repository contract. Repository corrections
are complete; the production exit checks in this document are still required.

This document is the source of truth for Supabase project-key selection,
credential transport, internal Edge Function authentication, exposed-schema
security, migration execution, identity-lifecycle indexes, destructive queue
triage, and the backend release gate. Detailed endpoint payloads remain in
[`05-api-contracts.md`](./05-api-contracts.md), and executable operator commands
remain in
[`06-supabase-deployment-runbook.md`](./06-supabase-deployment-runbook.md).

## Credential and Header Matrix

Key class and HTTP transport are separate decisions. Do not infer transport from
the destination, a successful capability probe, or the length of a credential.

| Credential                                           | Authority                                            | `apikey`                                             | `Authorization`             |
| ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | --------------------------- |
| Current publishable project key (`sb_publishable_…`) | Identifies the project; never privileged             | Yes                                                  | Never                       |
| Legacy anon project JWT                              | Identifies the project; policies still govern access | Yes                                                  | Not as a user session       |
| Current secret project key (`sb_secret_…`)           | Server-only project authority                        | Yes                                                  | Never                       |
| Legacy `service_role` JWT                            | Temporary server migration fallback                  | Yes                                                  | `Bearer <same JWT>`         |
| User access JWT                                      | Bound user identity                                  | A public project key accompanies raw client requests | `Bearer <user JWT>`         |
| Supabase Management API access token                 | Hosted management-plane operations only              | No                                                   | `Bearer <management token>` |

Rules:

- Opaque publishable and secret project keys belong only in the standard
  `apikey` header. They are not JWTs.
- Bearer transport is reserved for a user access JWT or the legacy
  `service_role` JWT during migration overlap.
- Internal routes do not recognize a custom credential header. In particular,
  `x-supabase-server-key` is not part of the protocol.
- A public/publishable key must receive `401` from a server-only worker even if
  that key can reach an RLS-protected table.
- Never log, return, summarize, or compare key prefixes, suffixes, lengths, or
  response bodies as credential diagnostics. Log only a stable failure reason,
  endpoint, and HTTP status.

## Environment Sources

Supabase-hosted plural variables are JSON dictionaries whose property names are
key names and whose values are complete keys:

```json
{
  "default": "<complete current key>",
  "rotation-2026-07": "<complete current key>"
}
```

Do not manually replace a platform-managed plural variable with a raw key or a
JSON string. A plural value that is not an object of correctly classified keys
is malformed.

Production deploys also synchronize the Management API-resolved active key into
the non-reserved Edge secret `MERIAN_SUPABASE_SERVER_API_KEY` before deploying
Functions. This is a deployment fallback for a lagging or malformed hosted
dictionary, not a new credential class or request header. It contains the same
complete project server key and follows the same format-aware transport. Never
attempt to set a built-in `SUPABASE_*` secret through the CLI. After the write,
the workflow compares the exact local key's SHA-256 digest with the digest
returned by `supabase secrets list --output json`. Function rollout stops if the
named secret is missing, duplicated, malformed, or different; neither the key
nor either digest is logged.

### Edge Functions and Deno tooling

`functions/_shared/serviceRoleAuth.ts` is the only server-key resolver. Its
preferred outbound key order is:

1. explicit CI/local override `SUPABASE_SERVER_API_KEY`;
2. deploy-synchronized hosted fallback `MERIAN_SUPABASE_SERVER_API_KEY`;
3. `default` from the hosted `SUPABASE_SECRET_KEYS` JSON dictionary;
4. the first valid named dictionary key in deterministic name order;
5. singular `SUPABASE_SECRET_KEY` for local/manual environments; then
6. legacy `SUPABASE_SERVICE_ROLE_KEY`.

Inbound worker authentication accepts an exact, constant-time match against
every valid configured server key, so named overlap keys can rotate safely.
Publishable keys, anon/user JWTs, incomplete placeholders, malformed dictionary
entries, and an opaque key placed only in the legacy variable are rejected.

Each environment source is classified independently. A malformed source
contributes no authorization candidate and cannot veto an exact key supplied by
another valid source. If no valid source matches, the presence of any malformed
source produces `invalid_secret_key_configuration` instead of an ordinary token
mismatch. This source isolation lets a separately valid explicit, synchronized,
singular, or legacy source keep a controlled environment available while another
source is corrected without ever promoting the bad value. Unknown plural entries
never become candidates.

Outbound selection keeps strict precedence. A configured malformed scalar
encountered at its priority point fails rather than silently selecting a lower
source; a valid higher-priority source is not vetoed by a malformed lower
migration fallback. A malformed hosted dictionary may use a separately valid
scalar fallback.

`functions/_shared/publishableKey.ts` separately resolves user-client project
keys from the hosted `SUPABASE_PUBLISHABLE_KEYS` JSON dictionary, preferring
`default` and then deterministic name order. A complete legacy
`SUPABASE_ANON_KEY` is accepted only during migration overlap. The public and
server resolvers never accept each other's key class. The modern dictionary and
legacy scalar are independent: either valid source remains usable if the other
is malformed, and the malformed value never enters the accepted-key set.

### Public web server

The public Next.js server supports `SUPABASE_SERVER_API_KEY`,
`SUPABASE_SECRET_KEYS`, and the legacy `SUPABASE_SERVICE_ROLE_KEY`. It does not
support the singular local Edge fallback. No server-key variable may use a
`NEXT_PUBLIC_` prefix or enter a client bundle. It applies the same strict
precedence and source isolation: a malformed configured explicit override fails,
while a valid selected higher source is not vetoed by a malformed lower
migration fallback.

### Management API resolution

CI health checks, taxonomy imports, and deployment smoke tests use
`scripts/resolve_project_api_keys.ts`. It calls
`/v1/projects/<ref>/api-keys?reveal=true` with a 15-second deadline and a 512
KiB streaming response ceiling. It:

- prefers the current secret key named `default`, then another named current
  secret, then only the exact legacy key named `service_role`;
- returns every real current publishable and exact legacy `anon` key for
  negative smoke controls;
- makes at most five attempts for transport failures, HTTP 408/425/429, and HTTP
  5xx, using capped exponential equal-jitter delay and a bounded numeric
  `Retry-After`;
- fails immediately on HTTP 401/403, other caller errors, malformed UTF-8/JSON,
  oversized responses, missing revealed keys, and ambiguous key classifications;
- applies strict UTF-8, JSON, key-format, type, and exact-name checks; and
- never prints a credential, response body, token, or raw transport error on
  failure. Retry progress contains only the stable failure class, bounded delay,
  and attempt count.

Do not replace this with a CLI key-list command unless the reviewed CLI version
has an equivalent reveal contract.

The production workflow masks the selected value, synchronizes it to
`MERIAN_SUPABASE_SERVER_API_KEY`, verifies the stored SHA-256 digest through
`scripts/verify_edge_secret_digest.ts`, and only then deploys the selected
Function fleet. Positive smoke requests retry bounded transient deployment
statuses for up to six attempts. A final Function failure reports only status
and whether the fixed `X-Merian-Handler: 1` marker was present: marker present
means the request reached a Function handler; marker absent points to the
gateway or deployment router. A final Data API failure is explicitly classified
as a PostgREST/RPC diagnostic path and does not expect a Function marker.
Response bodies and request-ID values remain withheld; no variable header value
is printed.

Before positive credentialed smoke, the graph-derived route preflight requires
every configured Function to return the fixed handler marker. It uses a
validated legacy anon JWT only to cross an intentional gateway
`verify_jwt = true` boundary; a publishable key is never sent as Bearer. If
gateway verification remains configured but that JWT is unavailable, rollout
fails closed rather than accepting an unmarked platform response.

## Edge Function Authentication

`verify_jwt = false` means the handler owns authentication. It does not make a
route public and does not imply that the gateway strips a correctly supplied
Authorization header.

For a user route, the handler validates the Bearer user JWT through the shared
auth or claims boundary. Raw clients also send the public project key in
`apikey`.

For a server-only worker or status route, the handler:

1. reads only standard `apikey` and Bearer headers;
2. rejects opaque project keys in Bearer;
3. rejects conflicting `apikey` and Bearer values;
4. compares the candidate exactly against configured server keys; and
5. creates downstream clients from the environment-resolved key, never from the
   accepted request value.

`functions/_shared/serviceRoleClient.ts` is the only privileged SDK factory. Its
final fetch adapter removes only supabase-js's exact inherited
`Authorization: Bearer <opaque secret key>` fallback. It preserves a different
user JWT and all unrelated caller headers. PostgREST, Storage, Functions, and
Auth Admin therefore share one format-aware transport. Operational JSON Function
calls also pass through `invokeServiceRoleJson(...)`. On failure it cancels the
response body and exposes only the numeric status, bounded SDK failure class,
and whether the fixed `X-Merian-Handler: 1` marker was present. It withholds
response bodies, request IDs, variable header values, and credentials.

Database authorization remains a second boundary. A server-exposed privileged
RPC must still be allowlisted, have an empty fixed `search_path`, and call
`internal.require_service_role()`. Mixed user/server routines dispatch on bound
user identity first; a no-user branch then invokes the service guard. Migration
`20260727183356_restore_identity_first_media_incident_guard.sql` is the
corrective example: it restores that final shape after a later migration
accidentally reintroduced role-first dispatch.

## Exposed-Schema Security

The repository does not rely on Supabase's changing default Data API exposure.
Every table created in `public` must have effective RLS enabled in migration
history, even when no direct client policy is intended.

Migration `20260727190637_secure_explore_comment_reactions_and_defaults.sql`
establishes the final direct-access contract:

- `public.explore_comment_reactions` has RLS enabled and no client policy;
- all table privileges are revoked from `PUBLIC`, `anon`, `authenticated`, and
  `service_role`;
- `service_role` receives only `SELECT`, `INSERT`, and `DELETE` for the
  authenticated Edge action's privileged SDK client; and
- both global and `public`-schema default table and sequence privileges for the
  `postgres` migration role revoke all privileges from those roles, including
  PostgreSQL 17 `MAINTAIN`.

Future API access must be granted explicitly and reviewed alongside its RLS
policy or privileged RPC. An empty REST result is never evidence that grants or
RLS are safe. The static migration contract and
`tests/public_schema_security.sql` verify effective catalog behavior.

The service-only `public.get_field_trip_capture_context(uuid)` projection is a
deliberate `SECURITY INVOKER` example. Migration
`20260808230028_restore_field_trip_capture_context_source_reads.sql` grants
`service_role` `SELECT` on only the six relations that projection reads, after
failing closed on function, security-mode, source-shape, or execute-ACL drift.
It grants no write operation and does not make the RPC executable by `anon` or
`authenticated`. Its disposable-database test switches to the real
`service_role` before invocation; an owner-context result is not valid evidence
for this boundary.

## Migration Execution Contract

CI pins Supabase CLI `2.109.1`, which owns migration transaction and
schema-history boundaries. Its normal migration apply path wraps
pipeline-compatible statements and the history insert in a transaction;
pipeline-incompatible statements are flushed and handled separately. Fresh
`db start` also replays every immutable historical migration, including
compatibility artifacts with their own transaction controls. New migration SQL
must therefore neither embed transaction controls nor assume that a top-level
statement always has an active transaction.

Therefore:

- new migrations at or after `20260727183356` contain no top-level transaction
  control;
- no checked-in migration contains `CREATE INDEX CONCURRENTLY`,
  `DROP INDEX CONCURRENTLY`, or concurrent `REINDEX`, including dynamically
  executed forms;
- top-level `lock_timeout` and `statement_timeout` guards use session `SET` with
  a matching `RESET`; `SET LOCAL` timeout guards are forbidden because they only
  warn and have no effect outside a transaction;
- schema-qualified `SUBSTRING` calls use ordinary comma-separated function
  arguments, such as `pg_catalog.SUBSTRING(value, pattern)`. PostgreSQL's
  keyword-separated `SUBSTRING(value FROM pattern)`,
  `SUBSTRING(value FOR count)`, and `SUBSTRING(value SIMILAR pattern ...)`
  forms are unqualified SQL expressions and cannot follow `pg_catalog.`;
- `EXTRACT(field FROM source)` remains unqualified because it is SQL expression
  syntax rather than a schema-qualifiable catalog function;
- migration filenames and applied historical contents are immutable; and
- historical migrations that contain explicit transaction controls remain
  compatibility artifacts, not examples for future work.

The repository guard masks comments, quoted strings, identifiers, and routine
bodies before checking transaction aliases and timeout settings. It separately
inspects executable dynamic SQL for concurrent index DDL and every migration for
schema-qualified `SUBSTRING` keyword syntax and schema-qualified `EXTRACT`
expressions. Detector fixtures cover `FROM`, `FOR`, `SIMILAR`, nested
expressions, comments, strings, valid comma invocation, and unqualified
`EXTRACT`. The deploy workflow discovers every `*Migration*.test.ts` and
`migration*.test.ts` source contract before starting the disposable database,
so a new contract cannot be omitted from a curated list.

Database fixtures must preserve production trigger and constraint behavior.
Inserting `auth.users` fires `on_auth_user_created` and can synchronously create
the matching `public.users` profile. A fixture that customizes that profile uses
a constraint-valid `ON CONFLICT (id) DO UPDATE` or updates the trigger-created
row; it does not follow the Auth insert with a second plain profile insert.
Conflict handling is not a CHECK bypass: proposed public usernames must satisfy
the current 3–24-character policy and all other immediate constraints. Fixture
UUIDs and usernames remain deterministic, catalog-wide unique, and
transactional.

Changing an `IMMUTABLE` helper referenced by an already validated CHECK does
not make PostgreSQL rescan existing rows. Migration
`20260808144244_expand_reserved_public_username_policy.sql` is the reviewed
username-policy example: it repairs affected profiles in stable user-ID lock
order, adds and validates a replacement policy-aware profile CHECK, then swaps
the canonical constraint name. It separately replaces the comment-mention CHECK
with structural validation only. `explore_comment_mentions.mention_username` is
the historical token embedded in immutable comment text, so applying the new
reservation list or rewriting that column alone would break rendered-link
matching. Policy migrations must classify current state versus historical
snapshots explicitly; do not assume every column containing the same scalar has
the same temporal contract.

### Large or partitioned indexes

Migration `20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql`
catalogs single-column foreign keys from `public` and `internal` to
`public.users` or `auth.users`. A valid, ready, non-partial, non-expression
index whose first key is the FK column is reusable.

The migration creates an ordinary index inline only when the relation is at most
32 MiB. For a larger relation it aborts with SQLSTATE `55000` and a supervised
`CREATE INDEX CONCURRENTLY` command. Run that command separately through an
owner session, outside a transaction and outside `db push`; then verify both
`pg_index.indisvalid` and `indisready` before retrying the unchanged migration.

For a partitioned table, build equivalent valid leading indexes concurrently on
every leaf partition first. Create the parent partitioned index only as a
reviewed metadata operation, then retry. Never let a migration recursively
perform a blocking parent build.

## External RevenueCat Mutation Safety

A RevenueCat promotional entitlement grant, revocation, transfer, or customer
deletion is a hosted provider mutation. Authorization to prepare tooling,
inspect exports, diagnose Supabase, or deploy a migration does not authorize any
of those actions.

Before an apply-capable promotional grant:

1. Resolve the exact RevenueCat project, Supabase project, source revision,
   entitlement ID, finite expiration, and operator credential class.
2. Freeze an explicit canonical-UUID cohort with a retained checksum and exact
   count. Current `subscription_tier` is a mutable projection and cannot define
   beta membership.
3. Prove dry-run performs zero provider requests and no identity outside that
   cohort can reach the request boundary.
4. Require the CustomerInfo client to accept RevenueCat GET `200` (found) and
   `201` (created), while requiring promotional POST `201` and an active
   entitlement in the bounded response.
5. Retain aggregate summaries separately from the identity-bearing results
   ledger. Do not log API keys, App User IDs, emails, response bodies, or
   customer attributes.
6. Revalidate the live customer before every mutation, skip already-active Pro,
   and preserve per-customer idempotency and bounded retry.
7. Treat a changed cohort, entitlement, expiration, or partial-results ledger as
   a new operation requiring review.

The former RevenueCat beta-grant tool is now permanently dry-run-only and its
Make target receives no provider credential or network permission. New
beta/promotion/support access uses the private Supabase account-grant ledger,
an exact approved dry-run plan, and an immutable identity-free operation
receipt. Restoring any provider-promotion writer would be a new external-
mutation design requiring all safeguards above, a reviewed source change, and
separate provider/production authorization; it is not a rollback shortcut.

RevenueCat customer deletion is permanent erasure, not deduplication. A later
SDK or subscriber GET can recreate an empty shell, but that lookup does not
itself restore deleted history, aliases, attributes, purchases, or promotional
grants. A store receipt may be observed again through a separate SDK/store flow;
that is not recovery of the deleted customer, is identity/configuration
dependent, and cannot recreate a RevenueCat-only promotion.

Deletion is limited to an exact verified test identity, the separate privacy
erasure workflow, or the prelaunch empty-shell cleanup authorized in the
RevenueCat identity incident. That cleanup requires four fresh artifacts, an
identity-bearing review, exact candidate SHA-256/count confirmation, and live
project/customer, inactivity, entitlement, attribute, alias, and purchase-history
revalidation before each v2 delete. It protects current canonical Supabase users
and all active Auth identities by default and never mutates Supabase. Dashboard
count, UUID case, inactivity, or missing profile evidence alone is insufficient.

Merian's Ghost and permanent Supabase UUIDs are both custom RevenueCat IDs.
RevenueCat custom-to-custom login does not transfer provider state. Merian
intentionally permits purchase, restore, and offer-code redemption on either
exact stable identity. Ordinary OAuth linking preserves a Ghost UUID. Generic
`401` responses also preserve it; only authoritative missing-session evidence
plus a failed SDK refresh may rotate the account. The existing-account conflict
  path mirrors/verifies the source's active finite or lifetime Pro horizon on
  the destination before source Auth deletion, then the proof-bearing iOS client
  calls `syncPurchases()` under the project-configured **Transfer to new App User
  ID** behavior. Beta promotion therefore accepts reviewed active Ghost and
  linked cohorts; a nonexistent Auth identity still fails closed.

## Destructive Queue and Orphan Triage

An old `pending_storage_deletions` row is not deletion authority. Storage work
is claimable only when a matching private deletion job is in `storage_pending`,
relational cleanup completed, storage did not complete, and no live profile or
owned scan exists. A stale marker fenced by those conditions is inert but
remains a critical provenance signal.

Health workflow artifacts stay aggregate and identity-free. When an orphan alert
fires, a restricted operator may inspect the exact row, private job, request
provenance, audit trail, and live ownership without copying identifiers into
tickets, logs, or chat.

- If durable deletion intent is legitimate, restore it only through the reviewed
  account-deletion request boundary.
- If a stale or unauthorized marker caused the alert, preserve evidence and
  prepare a reviewed forward metadata migration after provenance is understood.

Never clear an alert by blanket-deleting queue rows, sweeping storage prefixes,
making work due, resetting a cursor or lease, or deleting Auth. Do not run
ad-hoc repair SQL merely to turn a monitor green.

## Workflow and Supply-Chain Contract

- Third-party actions are pinned to reviewed 40-character SHAs. Dependabot
  checks action references in workflow files weekly; updates still require
  review. The repository contract separately scans the nested Deno installer
  pin in `.github/actions/setup-deno/action.yml`, which must be advanced through
  the same upstream review because GitHub documents the automated scan for
  workflow files.
- Workflow permissions default to `contents: read`. The only reviewed write
  grant is the taxonomy checklist's isolated five-minute writer job. The
  taxonomy import itself cannot read a checkout credential and passes only a
  one-day artifact to its writer. Xcode Organizer owns iOS distribution and
  needs no repository write grant.
- Every artifact includes `run_attempt` plus a run-specific identity such as
  `run_number` or the exact archive SHA, preventing a rerun from overwriting
  evidence from an earlier attempt.
- Every job has a timeout of at most 120 minutes. Deno processes receive only
  the network, environment, read/write, and subprocess permissions required by
  that step.
- Aggregate monitors use a 15-second request deadline and 64 KiB response
  ceiling. Scan-media health uses the same deadline and a 2 MiB ceiling.
  Taxonomy import uses a three-minute request deadline and 512 KiB ceiling.
- Internal smoke failures print endpoint and status only. Operational response
  bodies are withheld because they may contain sensitive samples.

## Production Exit Checklist

Repository tests are necessary but do not prove hosted state. Before calling
this correction released:

1. Replay all migrations and all discovered pgTAP fixtures against disposable
   PostgreSQL 17.
2. Run the read-only production privileged-routine, RLS/grant/default-ACL, and
   user-FK index inventories.
3. Build every required large/partitioned FK index through the supervised path,
   verify it, and retry the unchanged migration.
4. Push migrations, synchronize and digest-verify
   `MERIAN_SUPABASE_SERVER_API_KEY`, deploy the selected Edge fleet, and deploy
   the public web bundle from the same reviewed commit.
5. Require every real public project key to receive `401` from the internal
   Community Taxonomy status route.
6. Run the propagation-aware, format-aware positive Function and PostgREST RPC
   smoke suite with the resolved server key. A retry does not turn a final
   handler-owned `401` into success; inspect the structured authorization event.
7. Run the public web/admin frozen install, audit, test, type-check, and
   production-build gates.
8. Run the Xcode 26.6 iOS simulator/build suites and the corrected stale server
   retry test.
9. Manually dispatch and inspect account-deletion, scan-media, DwC-A, and
   RevenueCat monitors. Investigate any orphan alert before changing state.
10. For a RevenueCat identity/beta release, require the explicit cohort,
    successful GET `200|201` coverage, guest-provider continuity control,
    supervised reconciliation pause/restoration evidence, zero unexplained
    grant failures, and one entitled Field Chat smoke before declaring the
    customer path verified.

Record the commit SHA, workflow run and attempt, migration versions, catalog
results, deployment IDs, and monitor links. “Repository corrected” and
“production verified” are deliberately separate statuses.

## References

- [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [Migrating to publishable and secret keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)
- [Securing the Data API](https://supabase.com/docs/guides/database/hardening-data-api)
- [Edge Function authorization](https://supabase.com/docs/guides/functions/auth)
- [Edge Function environment variables](https://supabase.com/docs/guides/functions/secrets)
- [Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [May 2026 Data API exposure change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
- [PostgreSQL privileges](https://www.postgresql.org/docs/17/ddl-priv.html)
- [PostgreSQL `CREATE INDEX`](https://www.postgresql.org/docs/17/sql-createindex.html)
