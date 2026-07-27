# July 2026 Server-Key Authorization Mismatch

**Status (2026-07-27):** Corrected in the repository. Production migration,
function, web, Vault, and runtime verification are still required.

## Summary

Scan Library sharing reached `/share-scan-to-explore`, authenticated the user,
and then failed while synchronizing the public author projection. The database
returned `service_role authorization required`.

This was not a user or scan permission denial. The server used a current opaque
`sb_secret_...` API key, while the database defense-in-depth guard recognized
only the legacy service-role JWT claim or a direct database session. Opaque keys
carry authority through PostgREST's protected transaction `role` setting rather
than a JWT `role` claim.

The initial guard correction fixes sharing, but keeping that endpoint patch
alone would leave the same key-generation mismatch at other boundaries.
Repository remediation therefore covers key selection, HTTP transport, SDK
clients, SQL callers, mixed user/service routines, operational tools, and
discovery-based enforcement.

## Impact and Scope

- Scan Library quick-share and the full Insight composer use the same
  `/share-scan-to-explore` route and were both affected.
- The failed maintenance RPC is also used after other identity-sensitive writes.
  Explore comments, Field Trips, Community identification requests, and ghost
  profile merge must be smoke-tested with sharing.
- Sixty-three app-facing Edge entry points obtain their privileged client from
  `withEdgeHandler`; its previous direct legacy-key construction was a
  fleet-wide migration blocker.
- Twenty internal worker/status request boundaries had to use one exact
  environment-backed authorization policy. Fourteen previously implemented their
  own legacy Bearer comparison.
- Public-data and webhook routes that create an admin client, the server-only
  web waitlist client, persisted `pg_cron` commands, installed `pg_net`
  routines, and operator repair/audit scripts were separate key consumers.
- `get_owned_explore_media_incidents(uuid)` had a mixed user/service dispatch
  branch that checked the JWT-only service-role signal before calling the shared
  guard.

No service key belongs in iOS, and no client rebuild is required for the
database-only guard repair.

## Root Cause

Three concepts were coupled even though they have different contracts:

1. **Key selection:** code assumed `SUPABASE_SERVICE_ROLE_KEY` was the only
   privileged server credential.
2. **Credential transport:** callers assumed every privileged key belonged in
   `Authorization: Bearer ...`.
3. **Database authorization:** routines assumed every privileged call produced
   `auth.role() = 'service_role'`.

A legacy service-role key is a JWT and supports Bearer transport. A current
`sb_secret_...` key is opaque, belongs in `apikey`, and reaches PostgREST as the
protected `service_role` database role. Treating the formats as interchangeable
caused both false authorization failures and unsafe/unsupported transport.

### Production deploy follow-up

Production deploy run 1529 reached the post-deploy smoke gate after selecting
and deploying the complete Function fleet, but the exact Management
API-revealed positive key received `HTTP 401` from
`community-taxonomy-status`. The negative public-key controls still behaved
correctly. The withheld response and lack of local hosted-log access mean the
repository alone cannot distinguish `token_mismatch`,
`invalid_secret_key_configuration`, a gateway denial, or stale routed code for
that run.

The gate nevertheless exposed two repository defects: it assumed the
management-plane key and Function runtime dictionary were already synchronized,
and it probed immediately without bounded routing-propagation retries. The
durable correction synchronizes the selected key into the non-reserved
`MERIAN_SUPABASE_SERVER_API_KEY` Edge fallback before deployment, retains the
platform-managed dictionary as the canonical overlap source, retries only
bounded transient statuses, and reports whether the final Function response
reached a Merian handler through a fixed `X-Merian-Handler: 1` marker without
exposing a request ID, variable header value, or body.

Production deploy run 1530 exercised that correction. All six positive attempts
still returned `401`, and the final response carried the fixed handler marker.
This localized the denial to a Merian handler rather than the gateway or
deployment router. The remaining repository failure was then reproduced
directly in the shared resolver. It validated every scalar environment slot
globally before comparing the request, so a stale or malformed migration
slot—including a current opaque key copied into the legacy-only slot—could veto
the exact synchronized key from an independently valid source.

The durable fleet-wide correction classifies sources independently. A malformed
source contributes no candidate but cannot veto an exact match from another
valid source; an unmatched request still fails with
`invalid_secret_key_configuration` whenever any source is malformed. Outbound
selection retains strict precedence so a malformed configured override cannot
silently fall through. Equivalent migration-source isolation is enforced in the
public Edge key resolver and the public web server-key resolver.

## Rejected Workarounds and Durable Lessons

Several diagnostic changes proposed during the incident were not valid
platform contracts and must not be reintroduced:

- replacing the platform-managed plural key dictionary with a manually copied
  raw value, or inferring that shape from a credential-length observation;
- preferring the legacy service-role JWT instead of completing current-key
  support;
- printing a key prefix, suffix, length, or partial fingerprint, or copying a
  failed internal response body into CI logs;
- inventing `x-supabase-server-key`, putting an opaque key in Bearer transport,
  or selecting different credential rules for Functions versus PostgREST;
- treating an RLS-filtered database read as an authorization probe;
- weakening analyzers or negative smoke tests to make a deployment pass; and
- blanket-deleting a stale storage-deletion marker to clear an orphan alert.

The last item is independently destructive: an outbox row is not deletion
authority, but it is incident evidence. Operators classify its durable request,
private-job, audit, and live-ownership provenance under restricted access before
using a reviewed request boundary or forward metadata migration.

Repository-green and production-verified remain separate statuses. A correction
is not production-ready until disposable PostgreSQL replay, hosted catalog
audits, deployment smoke, web/admin builds, iOS tests, and manual monitor
inspection all pass for the reviewed commit.

## Repository Remediation

### Canonical Edge and web boundaries

- `functions/_shared/serviceRoleAuth.ts` resolves an explicit CI/local
  `SUPABASE_SERVER_API_KEY`, the deploy-synchronized non-reserved
  `MERIAN_SUPABASE_SERVER_API_KEY`, the named platform JSON dictionary in
  `SUPABASE_SECRET_KEYS`, the singular `SUPABASE_SECRET_KEY` local/manual
  fallback, and the legacy fallback in one place. Request authorization accepts
  only exact configured values, rejects conflicting credentials, and never
  reflects the caller's value into downstream clients. Configuration
  classification rejects publishable keys, anon/user JWTs, truncated
  placeholders, unknown/malformed dictionary entries, and opaque values placed
  only in the legacy variable. Every source is classified independently: a
  malformed source contributes no candidate and cannot veto an exact match from
  another valid source, while an unmatched request still fails as invalid
  configuration. A current key must retain its complete URL-safe opaque suffix;
  a legacy fallback must be a complete HS256 `service_role` JWT.
- `functions/_shared/serviceRoleClient.ts` is the only privileged SDK
  constructor. Its final fetch adapter removes only supabase-js's exact opaque
  key fallback Bearer value. Database, Storage, Functions, and Auth Admin remain
  available; unrelated user access tokens and request headers are preserved.
- `withEdgeHandler`, internal workers, public-data functions, webhooks, and
  `apps/web/lib/supabaseAdmin.ts` use those policies. Production function code
  may not construct a legacy-key admin client directly.
- Targeted internal operator scripts in `services/supabase/scripts` use the
  `createServiceRoleClientFromEnvironment` SDK factory instead of constructing
  Supabase authorization headers independently.

### Database and SQL callers

- Migration `20260727010340_fix_service_role_authorization_guard.sql` lets
  `internal.require_service_role()` recognize the legacy JWT claim, PostgREST's
  protected standard role setting for an opaque key, or a trusted direct
  repair/migration session. It changes no execution grant.
- Migration `20260727013416_future_proof_server_key_boundaries.sql` adds the
  private, fail-closed `internal.server_api_request_headers(text)` policy. It
  rejects public or malformed Vault values, rewrites installed `pg_net` routines
  and persisted `pg_cron` commands transactionally, then aborts if an active
  Bearer-only caller remains.
- The same migration changes the mixed media-incident routine to dispatch by
  user identity: a missing `auth.uid()` must pass the shared server guard; a
  present user ID must equal `self_id`. Public definer routines may not branch
  directly on `auth.role() = 'service_role'`.
- Migration `20260727183356_restore_identity_first_media_incident_guard.sql`
  restores that identity-first contract after a later migration accidentally
  reintroduced role-first dispatch.

### Enforcement

- Unit tests exercise current and legacy transport across PostgREST, Storage,
  Functions, and Auth Admin, including inherited `Request` headers.
- Static coverage inventories every service request boundary and every direct
  SDK-construction boundary, while rejecting production reads of individual
  server-key environment variables outside the resolver.
- Forward migration coverage rejects new Bearer-only `pg_net` construction.
- The disposable catalog test verifies helper ACLs and output, scans installed
  routines and cron commands, rejects JWT-only public-definer dispatch, and
  executes the mixed routine through simulated `authenticator` → `service_role`
  role impersonation.
- The read-only production audit reports any public definer routine that
  reintroduces JWT-only service dispatch.
- The deployment tooling suite discovers production operator scripts and
  rejects global `fetch()` calls that bypass the reviewed SDK or bounded
  provider transport.
- Static workflow coverage requires fallback synchronization to precede
  hash-only digest verification and Function deployment, and requires bounded
  smoke retry plus endpoint-aware Function handler/router or Data API/PostgREST
  classification on final failure. The verifier rejects a missing, duplicate,
  malformed, or mismatched secret entry without logging a key or digest.

## Other Places to Watch

Review all of these whenever Supabase keys, the SDK, Edge authentication, or
scheduled dispatch change:

- `verify_jwt = false` routes: handler authentication must remain explicit;
- new worker/status functions: add them through the shared request helper;
- custom webhooks and public routes: inbound webhook auth does not replace the
  need for a canonical privileged outbound client;
- `SECURITY DEFINER` routines granted to both `authenticated` and
  `service_role`: branch on bound user identity, then call the shared server
  guard for the no-user path;
- Vault/`pg_net`/`pg_cron`: persisted SQL text survives source edits and must
  use the private header helper;
- Next.js/server jobs and one-off repair scripts: support current keys without
  exposing them to browser bundles or logs;
- supabase-js upgrades: rerun exact header-capture tests because SDK fallback
  Authorization behavior can change;
- RLS policies that use `auth.role()`: evaluate their user-policy semantics
  separately and prefer explicit `TO authenticated` policies where equivalent.

## Required Production Verification

Do not mark this incident resolved until all of the following hold:

1. Confirm the server-boundary and corrective migrations are recorded and the
   expected Edge/web bundles are deployed.
2. Confirm the hosted `SUPABASE_SECRET_KEYS` value is the platform-managed JSON
   dictionary and has not been replaced with a manually configured raw string.
   Validate only its parseable shape and key names; never print its values.
3. Confirm the workflow's hash-only gate matched the stored SHA-256 digest for
   `MERIAN_SUPABASE_SERVER_API_KEY` to the exact selected key before Function
   rollout. Never reveal its value or either digest.
4. Run the privileged-routine read-only audit in enforcement mode.
5. Verify no installed HTTP routine or active cron command contains a direct
   `'Bearer ' || service_role_key` construction.
6. Put an active server key in the reviewed Vault slot and verify the database
   health checks report nonblank URL/key configuration.
7. During key overlap, smoke one internal service route with the current opaque
   key, optionally repeat with the legacy key, and prove a real anon/publishable
   key receives `401`.
8. Share one eligible scan from Scan Library and one from the Insight composer.
   Confirm no `service_role authorization required` error appears.
9. Smoke Explore comment creation, Field Trip mutation, Community request, and
   ghost-profile merge identity refresh paths.
10. Disable the legacy key only after all runtime, SQL, web, and operator callers
   pass with the current key.

Never restore availability by granting a maintenance RPC to `authenticated`,
placing a server key in iOS, accepting an opaque key through Bearer transport,
or weakening the in-function guard.

The consolidated long-term contract is
[`13-server-credentials-and-database-release-safety.md`](../backend-and-data/13-server-credentials-and-database-release-safety.md).

## References

- [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [Migrating to publishable and secret keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)
- [PostgREST transactions and role settings](https://postgrest.org/en/stable/references/transactions.html)
- [Supabase Edge Function authorization](https://supabase.com/docs/guides/functions/auth)
