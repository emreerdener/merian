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

`MERIAN_PRODUCTION_RELEASE_CLEARANCE_JSON` is a legacy optional audit input, not
a Supabase credential and not consumed by automatic deployments. Retained
clearance artifacts and their parser remain available for historical audits;
never commit populated records or synchronize them to Supabase.

`MERIAN_GITHUB_RELEASE_AUDIT_TOKEN` is read-only and confined to Production. It
reads current-main identity, branch protection, and environment policies for the
automatic gate before any Supabase credential is used. Optional evidence audits
also read Actions runs/artifacts. It must have no repository, deployment,
environment, or secrets write authority. The gate verifies current protected
main and protected environment branches with no required reviewers, timers, or
custom approval gates. Missing access fails closed. The active source hold
remains a separate blocker; completing it is not implied by removing manual
reviews. See the [release-evidence guide](../release-evidence/README.md).

`IDENTIFICATION_AUDIO_COMPARISON_V1` is private experiment configuration, not a
provider credential. Its account-bound JSON belongs only in the protected
Production environment secret and the same named hosted Edge secret. The
reviewed comparison-control workflow canonicalizes it in memory, passes it to
the pinned CLI through stdin with an isolated child environment, and retains
only sanitized control evidence. Do not expose its owner UUID or secret digest
in inputs, arguments, logs or artifacts. The existing runtime expiry remains
authoritative if the workflow is unavailable; see the
[activation and recovery procedure](./06-supabase-deployment-runbook.md#audio-comparison-activation-hold)
for its non-atomic list/delete boundary and verified deactivation.

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
scalar fallback. That precedence applies to environment-originated work with no
inbound service credential. After an inbound request exactly matches a valid
configured key, downstream work uses that matching configured copy rather than
an unrelated preferred source. This keeps gateway revocation authoritative and
prevents a stale deploy-synchronized overlap key from replacing the current key
that authenticated the request.

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

For step 5, "environment-resolved" means the configured copy that exactly
matched the request. It does not mean re-running standalone outbound precedence
after authorization, and it never reflects the caller-owned header string.

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

The Community detail projection now has an explicit service-only execute grant
and remains `SECURITY INVOKER`. Its private metric-compatibility helper is also
service-only, pure and fixed to an empty search path. Migration
`20260927004054_qualify_identification_metrics_by_provenance.sql` adds only the
missing service-role `SELECT` on `user_follows` needed by the existing invoker
Explore author-profile read. It changes no browser-role grant, table RLS, or
write privilege. Actual-role integration tests cover both public projections.

The prepared shared-primary consumers in
`20260929192008_apply_primary_identity_to_shared_consumers.sql` preserve those
privileges. The private saved-row identity helpers remain service-only invokers.
The historical public card/single-post/hashtag invokers derive identity labels
from persisted scan fields under the caller's existing row policies, without
private schema access or new definer authority. The provenance, primary
shape/schema, primary subject and verified-review CHECKs must remain validated.
This projection accepts no caller-supplied scan row and exposes only allowlisted
labels/rank. Authenticated direct reads remain owner-only; cross-owner direct
reads and the existing anonymous table denial remain in force. Server-side views
retain their viewer-blocking predicates, and public web continues through its
service-only projection.

The result-reader helper
`internal.require_identification_result_reader(jsonb,jsonb)` and its
one-argument compatibility wrapper are `SECURITY INVOKER`, `VOLATILE`, fixed to
an empty search path, and executable only by `anon` and `authenticated`. The
exact capability-4-or-5 check for V2, and capability-5-only check for the
reserved primary snapshot/schema, run inside the two existing `scans` SELECT
visibility predicates; it does not authorize visibility or change table/write
grants. Service projections retain their existing bypass. Unsupported visible V2
rows fail the query with `PT426`, including projections that omit metadata. All
four Edge completion paths separately check the current external reader because
their service client bypasses RLS. See the
[reader contract](./05-api-contracts.md#identification-result-readers) and the
actual-role fixtures `tests/identification_result_reader.sql` and
`tests/primary_identification.sql`. The new primary snapshot follows scan
visibility and existing retention; it contains observation labels and must not
be logged as content-free metadata. Its pure CHECK helpers read no tables.
Trigger helpers have an empty search path and no direct API-role execution
grant. The existing after-insert helper copies provenance and primary in one
owner-bound update; client recovery JSON remains outside that authority.

### Held observation review authority

Protocol-9 `review_owned_observation_analysis` is owner-authenticated and
remains behind default-false rejection/read gates. Private review receipts have
no API role table grants, bind one analysis and both revisions, and are erased
with history. Owner and deletion checks precede exact-operation replay. Legacy
review admission is service-only and is repeated at commit; enrolled scans
cannot route authority through the old scan-row writers. Community creation
acquires owner/generation admission before its existing request/scan locks;
row-trigger backstops check both sides of reparenting without acquiring those
higher-order locks. No blanket service-role table access or live activation is
introduced. The
[API contract](05-api-contracts.md#prepared-analysis-bound-reject-and-undo) owns
transitions, remaining community holds, and failure semantics.

The separate default-false confirmation gate protects
`confirm-observation-analysis`. Its two service-only RPCs freeze private intent
before GBIF verification and recheck both revisions at completion. API roles
cannot access intent tables or the shared internal transaction directly.
Completed outcomes recover before gate checks but always after ownership and
deletion checks. The deployment critical-route denial smoke includes this
endpoint; it does not enable the gate. The
[confirmation contract](05-api-contracts.md#prepared-analysis-bound-confirmation)
owns pending-operation recovery, verified proof, rate admission and remaining
native/legacy/community activation limits.

The private community binding/reconciliation foundation exposes no API routine
or table grant. Its insertion fence proves a fresh request in the publisher's
transaction; existing requests are never implicitly assigned to a selected
analysis. A durable queue separates request-first consensus locks from
owner-first history locks, and the worker yields rather than waiting on a busy
queue. Request deletion retains revocation work; parent deletion erases it.
Current authority/source checks, public snapshots and a scheduled retry owner
remain prerequisites for activation. See the
[community foundation contract](05-api-contracts.md#private-analysis-bound-community-authority-preparation).

Publication preparation introduces no API writer or privileged public history
reader. Its private registration gate defaults false. The public sidecar holds
only allowlisted display fields and follows existing post RLS; service-mediated
readers retain privacy and moderation checks. Authority/source invalidation is
transactional and remains active if admission is held. NOWAIT public-row locks,
account-deletion preflight and try-lock reference-cache retirement prevent
reverse lock waits. See the
[publication contract](05-api-contracts.md#prepared-analysis-publication-snapshots-and-public-reads)
for the separate moderated-publisher and activation requirements.

Private community admission adds no API execution grant or production caller.
Its consumed same-transaction fence authorizes only one exact new request; it is
not a session setting or bypass available to service clients. The public marker
holds only a post ID, while intent and operation receipts remain private and
cascade with history. Moderation and evidence ownership must be proven by the
future publisher before invoking the private routine. See the
[admission contract](05-api-contracts.md#prepared-atomic-community-request-admission).

Protected publisher intents add no API execution or table grant. Their source
object identities remain private and cascade with history. Exact retries recover
frozen preparation only; current execution requires fresh source and revision
checks. No persisted analysis record currently proves public-media approval.
Separate content moderation and public-copy cleanup must be implemented before
exposing the publisher; no rollout flag is enabled. See the
[intent contract](05-api-contracts.md#prepared-protected-photo-publication-intent).

Private photo-moderation jobs and attempts expose no API grants. Both their new
gate and all plan policies are disabled. They use independent provider quota
identities, preserving original-analysis dispatch fences and avoiding any
complimentary-credit linkage. Terminal decisions retain lease hashes, while
active tokens are removed. No live classifier or public-copy path is exposed.
See the
[attempt contract](05-api-contracts.md#prepared-photo-moderation-attempt-lifecycle)
for crash recovery, deletion accounting and remaining activation requirements.

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
  `SUBSTRING(value FOR count)`, and `SUBSTRING(value SIMILAR pattern ...)` forms
  are unqualified SQL expressions and cannot follow `pg_catalog.`;
- `EXTRACT(field FROM source)` remains unqualified because it is SQL expression
  syntax rather than a schema-qualifiable catalog function;
- migration filenames and applied historical contents are immutable; and
- historical migrations that contain explicit transaction controls remain
  compatibility artifacts, not examples for future work.

When a reviewed routine correction follows a timestamped migration that may
already be recorded, install the complete final definition in a new forward
migration. Canonical scan-media repair
`20260819194047_repair_canonical_scan_media_order_alignment.sql` and stable
sign-out repair
`20260819194315_repair_stable_signout_rotation_routine_definitions.sql` are the
current examples: fresh replay and persistent catalogs converge without a
migration-history repair or an assumption about which earlier file contents ran.

The repository guard masks comments, quoted strings, identifiers, and routine
bodies before checking transaction aliases and timeout settings. It separately
inspects executable dynamic SQL for concurrent index DDL and every migration for
schema-qualified `SUBSTRING` keyword syntax and schema-qualified `EXTRACT`
expressions. Detector fixtures cover `FROM`, `FOR`, `SIMILAR`, nested
expressions, comments, strings, valid comma invocation, and unqualified
`EXTRACT`. The deploy workflow discovers every `*Migration*.test.ts` and
`migration*.test.ts` source contract before starting the disposable database, so
a new contract cannot be omitted from a curated list.

Database fixtures must preserve production trigger and constraint behavior.
Inserting `auth.users` fires `on_auth_user_created` and can synchronously create
the matching `public.users` profile. A fixture that customizes that profile uses
a constraint-valid `ON CONFLICT (id) DO UPDATE` or updates the trigger-created
row; it does not follow the Auth insert with a second plain profile insert.
Conflict handling is not a CHECK bypass: proposed public usernames must satisfy
the current 3–24-character policy and all other immediate constraints. Fixture
UUIDs and usernames remain deterministic, catalog-wide unique, and
transactional.

Changing an `IMMUTABLE` helper referenced by an already validated CHECK does not
make PostgreSQL rescan existing rows. Migration
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
beta/promotion/support access uses the private Supabase account-grant ledger, an
exact approved dry-run plan, and an immutable identity-free operation receipt.
Restoring any provider-promotion writer would be a new external-mutation design
requiring all safeguards above, a reviewed source change, and separate
provider/production authorization; it is not a rollback shortcut.

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
project/customer, inactivity, entitlement, attribute, alias, and
purchase-history revalidation before each v2 delete. It protects current
canonical Supabase users and all active Auth identities by default and never
mutates Supabase. Dashboard count, UUID case, inactivity, or missing profile
evidence alone is insufficient.

Merian's Ghost and permanent Supabase UUIDs are both custom RevenueCat IDs.
RevenueCat custom-to-custom login does not transfer provider state. Merian
intentionally permits purchase, restore, and offer-code redemption on either
exact stable identity. Ordinary OAuth linking preserves a Ghost UUID. Generic
`401` responses also preserve it; only authoritative missing-session evidence
plus a failed SDK refresh may rotate the account. The existing-account conflict
path mirrors/verifies the source's active finite or lifetime Pro horizon on the
destination before source Auth deletion, then the proof-bearing iOS client calls
`syncPurchases()` under the project-configured **Transfer to new App User ID**
behavior. Beta promotion therefore accepts reviewed active Ghost and linked
cohorts; a nonexistent Auth identity still fails closed.

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
  review. The repository contract separately scans the nested Deno installer pin
  in `.github/actions/setup-deno/action.yml`, which must be advanced through the
  same upstream review because GitHub documents the automated scan for workflow
  files.
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
this correction released, require the reusable exact-SHA candidate gate, the
checked-in source hold gate, successful same-SHA Candidate Validation, and live
branch and automatic environment protections described in the deployment
runbook. No per-deployment review click or fresh manual clearance is required.
Hold-exit evidence must be real and retained before resolving the hold. Optional
artifact audits verify retained bytes and provenance; external approvals retain
their own substantive requirements. Then:

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
8. Run the iOS simulator/build suites with the
   [pinned contributor toolchain](../CONTRIBUTING.md#setting-up-the-development-environment)
   and the corrected stale server retry test.
9. Manually dispatch and inspect account-deletion, scan-media, DwC-A, and
   RevenueCat monitors. Investigate any orphan alert before changing state.
10. For a RevenueCat identity/beta release, require the explicit cohort,
    successful GET `200|201` coverage, guest-provider continuity control,
    supervised reconciliation pause/restoration evidence, zero unexplained grant
    failures, and one entitled Field Chat smoke before declaring the customer
    path verified.

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

## Prepared history evidence credentials

The private `analysisHistory/evidenceStorage.ts` owner reads
`R2_HISTORY_BUCKET_NAME`, `R2_HISTORY_WRITE_ACCESS_KEY_ID`,
`R2_HISTORY_WRITE_SECRET_ACCESS_KEY`, `R2_HISTORY_READ_ACCESS_KEY_ID`, and
`R2_HISTORY_READ_SECRET_ACCESS_KEY`, alongside the existing `R2_ACCOUNT_ID`.
Missing values fail closed; there is no fallback to public-scan credentials. The
history bucket must differ from `R2_BUCKET_NAME`. Read and write credentials
must be separate least-privilege identities scoped to this bucket. These names
are contract declarations, not provisioned secrets or deployment authorization.

The bucket must expose neither an r2.dev endpoint nor a custom domain. A private
prefix inside the public scan bucket is insufficient: Cloudflare documents that
[public bucket endpoints expose bucket contents](https://developers.cloudflare.com/r2/buckets/public-buckets/).
Owner reads use
[short-lived S3 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/),
never the public CDN. Signed URLs and object keys are sensitive capabilities and
must not be logged or persisted in result snapshots.

Content writes always use `If-None-Match: *`, supported by the
[R2 S3 API](https://developers.cloudflare.com/r2/api/s3/api/). Erasure writes an
empty marker with the same opaque key. This protects against delayed conditional
uploads, not an administrator or another holder of PUT credentials making an
unconditional replacement. Credentials must be exclusive to the dedicated owner;
generic scan upload, delete, export, public promotion and lifecycle tooling must
never operate on this bucket. No lifecycle rule may remove erasure markers.
Inventory these controls and verify conditional-upload/marker races, HEAD
metadata and read expiry against an explicitly authorized nonproduction bucket
before opening any history gate. Local fixtures do not attest hosted policy.

The prepared photo classifier adapter captures `GEMINI_PAID_API_KEY` before
dispatch and sends it only in the fixed Gemini endpoint header. It reads exact
private bytes using the existing separate history read credential, never a
public/signed source URL. Errors expose no upstream payload or
credential-bearing cause. Its immutable request proof excludes credentials. No
endpoint imports the adapter; durable proof/dispatch/output integration and
model-policy qualification remain activation prerequisites. See the
[classifier contract](05-api-contracts.md#prepared-source-bound-photo-classifier-adapter).

The subsequent private execution binding persists the pinned policy/transport
proof before provider dispatch and bounded output/usage with the terminal
decision. API execution remains revoked, with existing rollout flags false. A
future authenticated repository adapter must pass verified owner, observation,
attempt and original lease to every operation and use the same frozen classifier
closure throughout; it cannot accept a client-supplied approval or proof. A
claiming expired-attempt worker is still required before activation.

## Prepared public history-photo credentials

The unconnected public-photo transport declares
`R2_PUBLICATION_WRITE_ACCESS_KEY_ID`, `R2_PUBLICATION_WRITE_SECRET_ACCESS_KEY`,
`R2_PUBLICATION_READ_ACCESS_KEY_ID` and `R2_PUBLICATION_READ_SECRET_ACCESS_KEY`.
It uses `R2_ACCOUNT_ID` and the public `R2_BUCKET_NAME`, which must differ from
`R2_HISTORY_BUCKET_NAME`. There is no fallback to generic scan credentials. Both
configurations must resolve to the same destination before writing. These are
declarations, not provisioned secrets.

The dedicated owner reserves the `publication_media/v1/` namespace; generic scan
writers, cleanup and lifecycle tools must not operate there. This is a logical
ownership rule, not a claim that bucket credentials enforce prefix isolation.
Audit actual credential privileges before activation. Content writes are
conditional, and erasure markers must never expire or be deleted. Cache bypass
for the namespace is an activation requirement: origin no-store headers alone
cannot defeat an overriding CDN cache rule. Verify authorized nonproduction
write/erase races and edge GET behavior before enabling publication. Durable
allocation, publication invalidation and cleanup ownership are still required;
see the
[storage boundary](05-api-contracts.md#prepared-public-photo-storage-boundary).

The prepared staging ledger adds private copy leases and a permanent opaque-key
registry before any future external write. No API role can access either table
or execute its allocation/cleanup routines. Registry rows survive parent
erasure; claims contain only opaque object identity and cleanup state.
Staging-ready copies retain their original ten-minute cleanup deadline. This
does not activate public copying: a trusted scoped writer remains required. The
gated cleanup worker is separately prepared below. Atomic publication binding is
privately prepared behind its own default-false gate; it supplies no endpoint or
storage execution owner. See the
[staging lifecycle](05-api-contracts.md#prepared-public-photo-staging-lifecycle).

The prepared `erase-publication-photos` endpoint uses the shared exact
service-key authorizer and only the dedicated public-photo read/write
credentials. Its RPC grants permit due registry claim/acknowledgement, not
arbitrary object deletion or table access. Its independent
`publication_erasure_enabled` gate defaults false; once qualified, keep it
enabled when disabling admission. Finishing an existing claim remains available.
The `config.toml` entry participates in the automatic main deployment plan;
changing that config selects the whole function fleet. This runtime gate is not
a deployment exclusion. Deployment, scheduling, monitoring and namespace cache
bypass require separate release evidence and authorization; source validation is
not a hosted erasure claim.

The prepared `request-observation-publication` endpoint uses verified user
identity and the shared privileged SDK factory; no caller-nominated owner is
accepted. Its only new service RPC grants durable private intake, not provider
execution, copying or public binding. The first server-derived HMAC IP hash is
private and deletion-bound. No storage/provider credential is used at intake.
The independent operation gate stays false and the configured route follows
normal future main deployment planning. See the
[intake boundary](05-api-contracts.md#prepared-authenticated-publication-operation-intake).

The prepared publication work RPCs expose only bounded discovery, scoped
orchestration leases and sanitized owner status to the service role. Claim
responses contain private approved evidence and the saved IP hash and must never
reach client responses or logs. Fresh execution is not authorized by a work
lease; provider dispatch/copy/binding must retain their separate guards.
`publication_execution_enabled` defaults false, no scheduler is created, and
live public-note moderation remains an activation requirement. See the
[worker ownership boundary](05-api-contracts.md#prepared-publication-operation-worker-ownership).

The scoped publication moderation facade grants three service-only routines;
private lifecycle routines and tables remain ungranted. Recovery tokens are
worker-only. The adapter has bounded RPC calls without transport retry, and late
completions still require the original provider identity and durable proof.
Whole-cohort verified container preflight is prepared for the future execution
owner before quota; SQL cannot independently inspect storage bytes. No worker
route, scheduling or activation is supplied. See the
[scoped repository boundary](05-api-contracts.md#prepared-scoped-publication-moderation-repository).

## Prepared photo outcome settlement boundary

Photo outcome settlement is service-only and checks ownership/deletion before
historical replay. Fresh settlement requires live orchestration and no active
provider attempts; it does not change quota. A private insert fence prevents
successors after settlement. Provider approval is not container, note, revision
or public-copy permission. Future copy execution must independently revalidate
those boundaries; no deployment or activation is implied.

See the
[outcome contract](05-api-contracts.md#prepared-durable-photo-moderation-outcomes).

## October 4: prepared bounded photo moderation worker

`moderate-publication-photos` now connects service authentication, durable
claims, recovery, finalization and one verified provider execution. Gates stay
false and no scheduler is added. Shared request/provider deadlines preserve
completion time and never turn uncertainty into a retry or refund. Copy/binding,
exact-note moderation and native operations remain separate. Worker
handler/repository and classifier deadline tests cover recovery-first ordering,
preflight before quota, lost dispatch/completion, stalled response cancellation
and scoped denial.

## Prepared separate copy recovery stage

Approved photo outcomes now seed private copy work with a distinct token and
exact ordered causal-leaf cohort. The four service-only recovery RPCs add no
storage, provider or binding authority. Gates remain false. The pending
execution integration must consume current-authority checks and fixed staging
deadlines, perform targeted cohort cleanup and enforce note approval. See the
[canonical copy recovery contract](05-api-contracts.md#prepared-publication-copy-recovery-ownership).

## Prepared atomic copy cohort reservation

A separate default-false reservation gate now protects atomic allocation of the
exact approved no-note cohort under one immutable expiry. Scoped completion
rechecks current authority; historical publication recovery precedes cleanup,
and abandonment queues all unbound siblings without itself granting erasure.
Private receipts cascade on deletion while registry cleanup survives. No live
copy worker or binder is connected. See the
[canonical reservation contract](05-api-contracts.md#prepared-atomic-publication-copy-reservation).

## Prepared scoped copy repository

`publicationCopyRepository.ts` now binds the SQL reservation, recovery,
completion and abandonment boundary to the existing copy executor through the
dedicated `publicationCopyExecution.ts` coordinator. It freezes the exact
cohort, validates common expiry and private lease identities, propagates shared
deadlines and checks historical publication before cleanup. No storage worker,
binder or activation is added. See the
[repository contract](05-api-contracts.md#prepared-scoped-publication-copy-repository).

## Prepared reserved-cohort binding

A new service facade fences publication to the exact approved ordered
reservation and revalidates current authority. Historical receipt recovery
precedes work/gate checks and still verifies the reservation. Mismatches roll
back every publication write. The independent binding gate stays false; no Edge
worker or activation is added. See the
[binding contract](05-api-contracts.md#prepared-exact-reserved-cohort-binding).

## Prepared bounded copy operation

The prepared operation controller connects whole-cohort private verification,
sequential scoped copies, exact binding and targeted cleanup under one shared
110-second deadline, reserving time for recovery. It spends no provider quota
and does not infer terminal failure from transport uncertainty. HTTP worker
admission, durable copy outcomes and activation remain pending. See the
[controller contract](05-api-contracts.md#prepared-bounded-copy-operation-controller).

## Prepared durable copy outcomes

A separate private immutable outcome now records unapproved notes or original
staging expiry, retires copy work and preserves provider approval. Historical
publication wins; private cleanup IDs still require registry claims. Owner
status exposes only the existing needs-action state. Settlement has its own
closed gate; no worker or activation is added. See the
[copy outcome contract](05-api-contracts.md#prepared-durable-copy-needs-action-outcomes).

## Unsupported-source settlement activation

The independently default-false `publication_source_settlement_enabled` gate
permits metadata-derived HEIC remediation through the existing service-only
finalizer. It does not enable provider dispatch, copying, scheduling or
deployment. Existing attempts retain their recovery lifecycle; no quota is
admitted or refunded. Stored outcomes replay after gate closure and deletion
wins. Verified container rejection, runtime qualification and native delivery
remain separate activation requirements.

## Verified-container settlement boundary

`finalize_publication_container_rejection` is service-only and independently
gated off. SQL verifies the original immutable source and policy, but relies on
the trusted byte-verifying preflight for the actual container-policy decision.
No public/client attestation authority or direct table access is granted. No
attempts, quota, copies or activation are created. Publication and deletion
precedence, identical replay, and immutable evidence are mandatory. Validator
policy changes must version the accepted attestation contract together.

## Copy worker activation and erasure liveness

Prepared `copy-publication-photos` uses explicit service authorization and
closed SQL execution/reservation/settlement/binding gates. Do not enable copying
until separately authorized recurring `erase-publication-photos` invocation,
due-backlog/oldest-age monitoring and public CDN cache bypass are verified.
Terminal staging-expiry settlement deletes copy work; failed best-effort cleanup
can be recovered only from the permanent registry by the independent erasure
worker. No source-level gate proves that scheduling is functioning. Runtime
CPU/process-memory qualification and owner/native delivery also remain
prerequisites; source/config inventory authorizes no deployment or schedule.

The prepared `upload-observation-evidence` endpoint is the private write owner:
verified JWT identity enters service-only full-cohort reservation and completion
facades, with no client access to private routines/tables. It computes actual
byte digests and uses the dedicated history write credential for conditional
PUT/HEAD verification under a shared deadline. It never accepts public URLs or
returns storage capabilities. Cohort metadata preserves immutable consent after
expiry while the opaque erasure ledger survives account/observation deletion.
This source wiring does not provision credentials/buckets or activate uploads;
the private-bucket and independent erasure qualifications above remain required.

### Protected Field Chat execution preparation

The prepared chat execution fence is private with RLS and no direct API-role
grants. Only `service_role` can invoke the exact allowlisted protected quota and
context-admission signatures. Private fingerprint, locking, immutability and
merge helpers have no API execute grant. `chat_execution_enabled` defaults false
independently of immutable-context preparation.

The fence survives ordinary quota pruning and message erasure. Scan deletion and
account detachment erase private ownership; merging accounts preserves the
scan-owned fence and conservatively retires colliding quota rows without
restoring committed charges. The service-only one-time dispatch routine now
atomically consumes a permanent marker and commits original provider quota.
Current owner/deletion/consent and original context/reservation checks apply;
generic finalization cannot bypass first-dispatch admission. Unknown grant
replies stay held with no reusable permission. Protected HTTP/native wiring and
bounded runtime qualification remain necessary before this gate may be
considered for activation. No current migration, local test, or prepared RPC
authorizes activation or deployment.

The legacy Insight boundary now uses private admission/finalizer/stale-recovery
cores without service-role execute grants. Public wrappers preserve exact
signatures and acquire subject locks before quota locks. The only new exposed
routine is the service-only owner/deletion-fenced route read. Existing SQL
snapshot owners invoke the private admission core directly; no API-supplied mode
bypasses the fence. The matching enrollment barrier holds unknown committed
legacy work until its exact assistant receipt exists.

The new Insight handler requires the forward routing migration before rollout; a
missing or unknown routing RPC fails closed rather than selecting legacy. Its
source-derived Field Chat bundle identity is regenerated. Immutable-required
HTTP sends now use the bounded protected owner in source; fresh admission
remains behind disabled database gates and requires coordinated native
qualification. These source changes do not authorize applying migrations,
activating either chat gate or deploying the Function.

The exact completion and atomic local-refusal routines are separately
service-only allowlisted. Their private receipt/copy helpers have no API execute
grants. Completion reads original owner-bound context before assistant evidence;
refusal takes exclusive subject locks before any replay/admission. Fixed SQL
answers and ten-field receipts exclude caller-chosen response payloads and
private metadata. An assistant write failure rolls back the daily slot and
context. No provider quota is admitted or settled here. Fresh refusal remains
behind the false execution gate; HTTP/native execution is still unconnected.

Original-grant reply write and full-payload recovery are separately service-only
allowlisted. Their private validator/receipt helpers have no API execute grants.
Subject ownership and deletion precede reply validation; writes preserve
subject→quota→fence→message lock ordering. Receipt recovery can survive quota
pruning, but a new answer requires the original committed first-attempt quota
and consumed dispatch marker. Read recovery compares private accounting without
returning it. Completion never refunds, redispatches or extends execution
authority. The migration leaves every activation gate unchanged and does not
authorize hosted application or deployment.

Protected HTTP execution now uses the exact immutable recovery/admission and
original-grant completion owners. Source routing cannot turn a client protocol
omission into legacy permission. The isolated raw provider adapter has a fixed
origin/model, one invocation, real parent cancellation and bounded response
body; unknown outcomes remain charged with no successor. The source-derived
Field Chat fingerprint includes this runtime. Native immutable send tickets,
receipt decoding and durable delivery are prepared; explicit identification
refresh and operational qualification still precede any separately authorized
deployment or activation. All gates remain false.

The prepared no-admission seal is an exact allowlisted service-only RPC, not an
authenticated-client table write. Its private immutable columns can never gain
quota, message or dispatch authority. Both quota INSERT and UPDATE paths and the
shared context admission owner enforce the seal. Only a locked exact
stale-ticket denial is sealable; gate, authorization, network and damaged-state
errors remain failures or holds. Historical replay still checks current owner
and deletion first. The new exact read-only proof RPC is separately allowlisted
and uses the same canonical subject/request locks without fresh gates or
admission. Prepared HTTP recovery reads original completion before proof; only
exact typed stale-ticket denial can call the seal writer. Native versioned proof
settlement uses the existing exact running-claim CAS; fresh requests cannot
reuse a proved-stale ticket. Explicit remote refresh remains pending. These
source changes do not authorize deployment or change any rollout gate.

A terminal seal colliding with another account's attempted UUID blocks account
merge with `55000/field_chat_execution_merge_conflict`. The whole merge rolls
back, preserving both owners and all attempt evidence. Neither operational quota
retirement nor a user-controlled bypass resolves this conflict. Two terminal
seals with the same UUID also block merge; no winner is selected.
