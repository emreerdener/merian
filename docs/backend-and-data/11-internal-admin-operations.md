# Internal Admin Operations Runbook

This runbook covers local development, project configuration, deployment,
access administration, pricing maintenance, incident response, and verification
for `admin.naturebook.earth`. Read the architecture and security contract in
[`10-internal-admin.md`](./10-internal-admin.md) first.

## Ownership and change control

The production admin app is a high-sensitivity surface. Changes to authentication,
authorization, admin RPCs, report visibility, AI pricing, audit behavior, or
moderation projections require:

1. Review by a current owner or designated security reviewer.
2. A fresh migration reset and both admin pgTAP suites.
3. A frozen admin dependency install, blocking high-severity audit, unit tests,
   type-check, and production build.
4. Public-web and relevant iOS verification when public projections or reporting
   contracts change.
5. A recorded rollout and rollback decision. Never solve an incident by adding
   a service-role key to the admin deployment.

## Required configuration

The admin deployment has exactly three application variables:

| Variable | Local example | Production value |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Local Supabase API URL | Project URL from Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Local anon/publishable key | Project publishable or legacy anon key |
| `NEXT_PUBLIC_ADMIN_ORIGIN` | `http://localhost:3000` | `https://admin.naturebook.earth` |

All three are public browser configuration. Do not add
`SUPABASE_SERVICE_ROLE_KEY`, a secret API key, direct database credentials,
Gemini credentials, PostHog, or another analytics token to this project.
`NEXT_PUBLIC_ADMIN_ORIGIN` must be one HTTP(S) origin with no credentials,
pathname, query, or fragment. OAuth initiation and callback destinations are
built from this validated value, never from `request.url`, `Host`, or forwarding
headers.

In Supabase Auth:

- Enable Google OAuth and configure its client ID/secret in Supabase, not in the
  admin frontend.
- Add `http://localhost:3000/auth/callback` for local development.
- Add `https://admin.naturebook.earth/auth/callback` for production.
- Keep redirects exact. Do not use a broad wildcard for the admin hostname.
- TOTP is enabled on Supabase projects by default as of this runbook, but verify
  it in the project Auth MFA settings before rollout.
- Keep JWT expiry appropriately short for the wider project. The admin RPCs also
  validate the live `auth.sessions` row and internal session window because
  deleting/disabled access must take effect without waiting for JWT expiry.

## Local development

Start the repository's Supabase stack, reset it from migrations, and run the
admin app in a separate terminal:

```bash
supabase --workdir services start
supabase --workdir services db reset

cd apps/admin
cp .env.example .env.local
npm ci
npm run dev
```

Use the URL/key printed by `supabase --workdir services status` in
`.env.local`. Set `NEXT_PUBLIC_ADMIN_ORIGIN=http://localhost:3000`. If port 3000
is occupied, use a deliberate alternate port and add its exact callback URL to
the local Auth redirect allowlist.

For local Google OAuth, the provider must be configured for the local Supabase
Auth callback as well as the admin application's callback. Do not test the admin
by injecting a role into JWT user metadata; membership is database state.

## Bootstrap the first owner

The first owner must sign in with Google once so Supabase has created both the
Auth user and Google identity. Find the immutable UUID by exact email in the
Supabase Auth dashboard or with a trusted SQL session:

```sql
select
  auth_user.id,
  auth_user.email,
  auth_user.email_confirmed_at,
  auth_user.is_anonymous,
  array_agg(identity.provider order by identity.provider) as providers
from auth.users auth_user
join auth.identities identity on identity.user_id = auth_user.id
where lower(auth_user.email) = lower('owner@example.com')
group by auth_user.id;
```

Confirm the result is the intended non-anonymous, email-confirmed account and
includes provider `google`. Then run exactly once:

```sql
select internal.bootstrap_first_admin_owner(
  '00000000-0000-0000-0000-000000000000'::uuid
);
```

The function fails if any membership already exists or the UUID is not an
existing Google user. Never delete the membership table to retry bootstrap.
After bootstrap, sign out, start a fresh Google session, enroll/verify TOTP, and
confirm the role badge is `owner`.

## Routine membership administration

Owners manage access from `/access`:

1. The candidate first signs into Naturebook with Google and verifies their
   email, creating an existing Auth user/identity.
2. Enter the exact email, role, and active state.
3. Confirm the membership row and ask the user to start a fresh Google session.
4. The user enrolls or verifies TOTP before seeing data.

Disabling a member immediately revokes their internal admin sessions. The final
active owner cannot be disabled or demoted. Maintain at least two active owners
in production so access recovery does not depend on direct SQL.

To revoke a single device/session, use `/access`, supply a meaningful reason,
and select Revoke. This marks the internal session revoked, deletes the matching
Supabase Auth session, and writes an immutable audit record. Revocation affects
only that session; disabling membership affects all admin sessions for the user.

## Verification before deployment

Run from the repository root. The local database suites are destructive only to
the local Supabase database and wrap their fixtures in transactions. Use the
reviewed Supabase CLI version documented in the deployment runbook. The
repository-wide migration execution contract prevents pipeline-incompatible
concurrent index DDL from blocking the reset before these fixtures run.

```bash
supabase --workdir services db reset
supabase --workdir services test db \
  services/supabase/tests/admin_foundation_security.sql \
  services/supabase/tests/admin_review_ai.sql \
  --local

supabase --workdir services db lint --local --schema public,internal
supabase --workdir services db advisors --local --type security
supabase --workdir services db advisors --local --type performance

deno test \
  --allow-read=services/supabase/migrations \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/_tests/adminFoundationMigration.test.ts \
  services/supabase/functions/_shared/aiUsage_test.ts \
  services/supabase/functions/report-user/db.test.ts

cd apps/admin
npm ci
npm run audit:dependencies
npm test
npm run typecheck
npm run build
```

The same ordered application gate runs in
`.github/workflows/admin-quality.yml` for every pull request and every affected
push to `main`. Pull requests are intentionally not path-filtered so the
required check always reports. Do not deploy from a commit whose admin-quality
job was skipped, cancelled, or failed. The registry-backed audit is
intentionally blocking: high/critical findings and an unavailable audit
registry both stop the admin release. `lib/dependency-security.test.ts`
independently checks the frozen Next.js, PostCSS, and Sharp versions and
protects the workflow sequence from silent drift.

In the GitHub repository ruleset, require
`Naturebook Admin Quality / test` as a
[status check](https://docs.github.com/en/pull-requests/reference/status-checks)
before a pull request can merge. In the separate admin Vercel project's
[Deployment Checks](https://vercel.com/docs/deployment-checks) settings, add
that GitHub Action and mark it required. Vercel may build the production
deployment while the check runs, but must not promote it to
`admin.naturebook.earth` until the exact commit passes. The checked-in workflow
creates a status check; it cannot make itself required or prevent Force
Promote/direct manual promotion. Record and verify these two external controls
during initial setup and after changing GitHub or Vercel integration settings.

The current production graph, reviewed on 2026-07-26, is:

- Next.js 16.2.12, pinned exactly above the
  [Server Actions DoS patched floor](https://github.com/vercel/next.js/security/advisories/GHSA-m99w-x7hq-7vfj);
- PostCSS 8.5.18, pinned exactly and enforced for Next.js transitively at the
  [path-traversal patched floor](https://github.com/advisories/GHSA-r28c-9q8g-f849);
  and
- Sharp 0.35.3, enforced through the Next.js override, following the
  [libvips advisory recommendation](https://github.com/advisories/GHSA-f88m-g3jw-g9cj)
  and including its optional native packages.

For a dependency update, change the manifest and committed lockfile together,
review all resolved and optional-native package changes, and run the complete
registry-backed gate. Keep the PostCSS/Sharp overrides until a reviewed stable
Next.js release declares equal or newer dependencies. A high/critical finding
may not be bypassed by changing the audit threshold, deleting the floor test,
or using Vercel Force Promote. Any exceptional waiver needs an owner/security
review, documented reachability and compensating controls, an expiry date, and
a follow-up issue before production promotion.

If public Explore projections or `/report-user` changed, also run the public-web
test/typecheck/build and the relevant iOS network test plus an unsigned simulator
build. Do not waive a new advisor finding without documenting why it is
unrelated or a known repository-wide finding.

## Deployment order

Use the normal CI deployment workflow when possible. The required order is:

1. Back up production and verify at least two project operators have database
   recovery access.
2. Apply `20260719161112_add_internal_admin_foundation.sql`. This creates
   schema, grants, grouping triggers, AI ledger, pricing, projections, and the
   idempotent historical backfill.
3. Verify RPC grants and direct-table denial before exposing the frontend.
4. Deploy `/report-user` and every Edge Function selected by the shared
   `aiUsage.ts` dependency graph. New writers should follow the schema migration
   immediately to minimize an instrumentation gap.
5. Deploy the iOS author-profile reporting UI and public Explore/web projection
   consumers.
6. Confirm GitHub reports the required `Naturebook Admin Quality / test` check
   passed its frozen install, dependency audit, tests, type-check, and
   production build, and confirm Vercel is deploying that exact checked commit.
7. Deploy `apps/admin` as its own project with Root Directory `apps/admin` and
   attach only `admin.naturebook.earth`.
8. Configure the exact production Auth redirect, verify Google sign-in and TOTP,
   and bootstrap the first owner if this is the initial release.
9. Run the production smoke tests below before announcing availability.

For a manual emergency database/function deployment, use the established
commands in [`06-supabase-deployment-runbook.md`](./06-supabase-deployment-runbook.md).
Never run a partial shared-helper deployment without its transitive consumers.

## Production smoke tests

Use disposable staff test accounts and records where mutation is required.

### Authentication and roles

- Anonymous request: admin routes redirect to login without attempting
  `admin_get_access_state`; a deliberate direct anonymous RPC execution still
  fails. Confirm routine anonymous navigation does not add avoidable
  `401`/`42501` access-state noise to Supabase logs.
- Registered nonmember and ghost: no admin data is returned.
- Disabled member: access fails even with a previously valid cookie.
- Analyst at AAL1: redirected to MFA. Analyst at AAL2: Overview and AI Usage
  only; raw routes are not in navigation and database role checks deny them.
- Moderator at AAL2: review, feedback, and user context work; owner access RPCs
  fail.
- Owner at AAL2: membership, session, and audit controls work.
- Revoke one owner/moderator test session and confirm the next request fails.
- Confirm idle timeout at 30 minutes and absolute timeout at eight hours using a
  disposable session or controlled database clock fixture, not by weakening
  production settings.
- Attempt to demote/disable the final active owner and confirm rejection.

### OAuth redirect confinement

- Confirm a valid single-leading-slash `next` path returns to the configured
  admin origin and preserves its path, query, and fragment.
- Exercise absolute URLs, `//evil.example`, leading slash/backslash forms,
  literal backslashes, and single- and recursively encoded separator variants.
  Every case must remain on `NEXT_PUBLIC_ADMIN_ORIGIN`.
- Repeat a valid and an invalid callback while sending a hostile `Host` and
  `X-Forwarded-Host`. Neither header may select the redirect origin.
- A malformed `NEXT_PUBLIC_ADMIN_ORIGIN` is a configuration failure, not a
  reason to fall back to the request origin.

### Security headers and caching

For `/overview`, `/reviews`, and one detail route, verify:

```bash
curl -I https://admin.naturebook.earth/overview
```

Expect private `no-store`, `X-Robots-Tag` noindex directives,
`X-Frame-Options: DENY`, no `X-Powered-By`, and CSP containing
`frame-ancestors 'none'`. Confirm a cross-origin mutation is rejected and no
third-party analytics request occurs in browser network tools.

### Review and public projections

- Create reports from two independent disposable users and confirm one grouped
  case with `report_count = 2`.
- Resolve it, submit new evidence from the same reporter, and confirm it stays
  terminal; submit from a new reporter and confirm it reopens.
- Hide and restore a disposable post/comment. Confirm hide does not resolve the
  case and the hidden content disappears from feed, map, profile, detail,
  notification/community helpers, and public web.
- Transition an identification case and confirm `scans.is_flagged` reflects
  whether an open/in-review case remains.
- Open identification detail and confirm coordinate access creates an audit row.

### Feedback, users, and AI

- Confirm all four feedback sources appear and workflow changes do not mutate
  the original submission.
- Search by partial email, exact UUID, and public handle; confirm the search and
  detail reads are audited and email never appears in the URL.
- Generate one scan and one Field reply. Confirm ledger events include the
  expected token fields and no prompt/response content.
- Refresh Overview/AI Usage and confirm five-minute cache separation by filter,
  complete-coverage labeling, and estimated-cost pricing version.
- Open `/complimentary-entitlements` as an AAL2 Analyst. Confirm the grant is
  exactly three; state totals, balance histogram, in-flight total, stale-hold
  ages, settlement reasons, Flash fallback, exhaustion, and paid-exhaustion
  conversion are coherent. Confirm the read creates the expected audit action
  and reveals no account or scan identifiers.
- In AI Usage, verify `pro_complimentary` and historical `pro_trial` are
  independently filterable. In Overview, verify current effective Pro separates
  paid, complimentary, and historical trial values without classifying
  complimentary access as paid.

## Pricing maintenance

Pricing is historical data. Never update an existing price row in place after
events have used it.

1. Check the official [Gemini pricing table](https://ai.google.dev/gemini-api/docs/pricing)
   and record the review date/source in the change description.
2. Determine the exact model, modality, service tier, prompt-size tier, and
   effective instant. The current estimator supports one Standard price per
   model/modality and does not model long-context or grounding charges.
3. Close the previous row by setting `effective_to` to the new instant and
   insert a new row with the same instant as `effective_from` and a new version
   label. Perform both changes in a migration transaction.
4. Add/adjust pricing effective-date tests and verify an event immediately
   before and at the cutover chooses the intended version.
5. Do not recompute historical event estimates unless a documented correction
   migration explicitly requires it.

When a model introduces pricing the schema cannot represent, extend the schema
and tests before using that model in production. Do not force a long-context,
batch, flex, priority, grounding, or media-output price into the current columns.

## Audit and privacy operations

- Review audit history from `/access`; use exact action names when filtering.
- Audit rows and notes are immutable. Corrections are appended as new actions or
  notes rather than rewriting history.
- Keep review/feedback notes to 1,000 characters or fewer. The note table allows
  4,000, but current mutation RPCs also record the note in the audit reason,
  whose bound is 1,000.
- Raw report/feedback/chat data must be handled only in the admin UI. Do not paste
  it into tickets or chat systems unless the separate system is approved for that
  data class.
- Account deletion clears AI account linkage but retains aggregate usage/cost. It
  does not delete immutable staff audit records whose actor is still referenced.
- V1 has no export. Do not add an ad hoc SQL/CSV export without a separate
  authorization, privacy, retention, and audit design.

## Incident response

### Suspected admin-account compromise

1. An unaffected owner revokes every visible session for the account and disables
   its membership.
2. A Supabase project operator checks Auth sessions/identities and performs the
   provider/account recovery procedure.
3. Review audit events by actor, target, action, request ID, and time. Preserve
   evidence; do not edit audit rows.
4. Inspect public moderation state and restore only after understanding each
   action. Case resolution and visibility are separate.
5. Rotate credentials only if exposure is plausible. The admin app has no secret
   key to rotate; focus on Google/Supabase sessions and deployment access.

### Lost authenticator or no usable owner session

- If another owner is active, keep membership unchanged and use the approved
  Supabase Auth MFA recovery process for the affected Auth user.
- If no owner can authenticate, use the organization's database break-glass
  procedure with two-person approval. Verify the replacement is an existing,
  email-confirmed Google Auth user before adding/restoring owner membership.
  Record the operator, ticket/change ID, SQL, and before/after rows outside the
  application because direct database recovery does not have a browser actor.
- Never disable AAL2 checks, change `require_admin`, expose `internal`, or issue
  a service-role key to the browser as a recovery shortcut.

### Ledger writer failures

Primary scan/message trigger failures are transactional and should be treated as
write-path incidents. Independent best-effort failures emit structured
`ai_usage_ledger_write_failed` logging and create a known coverage gap. Record the
affected operation/time window, repair only from durable token metadata, use the
idempotent source key, and keep the repaired rows labeled accurately.

### Complimentary hold or settlement incident

Use `/complimentary-entitlements` to establish aggregate scope. Investigate a
growing tail above 15 minutes or one hour, an advancing oldest-hold timestamp,
completion/terminal orchestrator logs, direct completion-fence rejections,
Flash-fallback changes, and provider quota evidence for the same incident
window. Do not expose ledger rows in the browser, copy owner/scan identifiers
into ordinary tickets, or infer a refund from hold age.

A hold settles only after exact-generation proof: consume when the scan and all
required media are durable, release on proven terminal failure, and preserve it
when persistence/provider/media state is ambiguous or retryable. Provider
counters remain charged after an attempted call even if the user-facing hold is
released. Repair routines must acquire the user lock first and route through the
completion or terminal orchestrator. Follow
[`18-complimentary-pro-scans.md`](./18-complimentary-pro-scans.md) and the
[joined scan recovery contract](./16-scan-ingestion-reliability-and-recovery.md);
never edit the derived balance or ledger directly.

### Account-scoped media loss

The internal admin browser is not an R2 console and has no service-role repair
capability. If one owner's Scan Library and Explore images fail while other
owners' media loads:

1. preserve scan/post rows, media URLs, request IDs, and the incident window;
2. distinguish CDN/R2 404 from transport or feed-projection failure;
3. run the aggregate deletion-claim fence/audit checks in the
   [Supabase deployment runbook](./06-supabase-deployment-runbook.md#account-scoped-image-loss-containment-and-repair);
4. do not hide/moderate posts, mark scans archived, sweep a prefix, or delete
   relational rows as a display fix; and
5. track containment, production deployment, runtime verification, and
   recovered-object coverage independently.

After the Explore media-health release, use its origin-verified state instead of
manual moderation:

1. call the service-only `get_explore_publication_health_summary()` and record
   only aggregate scope; `affected_author_count = 1` supports an account-scoped
   incident, while a larger value requires review of additional owner cohorts;
2. review recent `explore_media_health_reconciliation_runs` counters and worker
   logs without copying raw owner keys into tickets;
3. confirm two spaced direct-origin observations before accepting `missing`;
4. verify degraded posts expose remaining media and quarantined posts disappear
   from every canonical public projection;
5. verify profile visible count, preview, and paginated grid agree on the
   canonical projection;
6. verify the owner incident queue and publication/recovery summary remain
   available and post/engagement rows
   remain intact;
7. restore only from a strongly matched owner file or reviewed recovery source;
   and
8. let a healthy result clear system quarantine automatically, while preserving
   any author unpublish or moderation hide.

Do not bulk-set health to healthy, fabricate observation evidence with species
reference art, or delete an unrecoverable quarantined record to make metrics
green. The canonical procedure is
[Explore Media Health and Quarantine](./12-explore-media-health-and-quarantine.md).

The active incident evidence, leading cause, device recovery limits, and exit
criteria are in the
[July 2026 account-scoped R2 image-loss report](../incidents/2026-07-account-scoped-r2-image-loss.md).

## Rollback

- The admin frontend can be rolled back or removed from DNS independently; this
  does not require deleting database state.
- Roll back only to a commit whose frozen graph remains above the reviewed
  dependency floors and whose required Admin Quality and Vercel Deployment
  Checks passed. If no safe prior frontend exists, remove the admin domain or
  hold promotion rather than Force Promote a vulnerable/red build.
- Edge writers may be rolled back to a compatible prior version, but keep the
  ledger schema and grants in place.
- Do not roll an Edge writer behind the complimentary completion/terminal
  orchestrator while cutover mode is active. If compatibility cannot be proven,
  fail new provider work closed and repair forward. Reverting the global mode
  would also reactivate legacy trial and obsolete-client behavior and requires
  separate explicit product/security incident authority.
- Do not down-migrate by dropping `internal`, audit rows, notes, review grouping,
  moderation columns, or usage events. These contain durable operational history.
- If a public projection regression occurs, remove access to the admin frontend,
  restore the last known-good projection functions through a forward migration,
  and verify hidden content remains fail-closed.

## Troubleshooting

| Symptom | Check |
|---|---|
| OAuth returns to login | Exact redirect allowlist, Google provider config, callback `code`, public URL/key, and valid origin-only `NEXT_PUBLIC_ADMIN_ORIGIN` |
| Repeated anonymous `admin_get_access_state` 401/42501 logs | Confirm the deployed admin includes the server-side `auth.getUser()` preflight and that middleware/routes use `getAccessState()` rather than calling the RPC directly |
| Member sees “not authorized” | Exact Auth UUID, active membership, confirmed email, non-anonymous account, Google identity |
| User loops through MFA | Factor status, `currentLevel`, fresh token after verify, browser cookie domain |
| “Start a new Google session” | Internal session is idle/expired/revoked; sign out and begin a new OAuth session |
| Mutation says invalid origin | `NEXT_PUBLIC_ADMIN_ORIGIN`, reverse-proxy `Host`/`X-Forwarded-Host`, browser `Origin` |
| Dependency audit cannot reach registry | Expected fail-closed release stop; restore registry/network availability and rerun the same commit |
| Dependency floor test fails | Review the resolved lockfile graph and restore/upgrade the explicit Next.js, PostCSS, or Sharp pin/override; never weaken the floor |
| Vercel build is ready but domain is not promoted | Confirm the exact commit's required `Naturebook Admin Quality / test` Deployment Check is present and successful |
| Direct table read fails | Expected; use an authorized RPC, never add browser table grants |
| Aggregate appears stale | Five-minute authorized cache; use the Refresh control |
| Queue appears stale | Queue is uncached; check filters/cursor and the 30-second refresh |
| Estimated cost is null/low | Missing exact model/modality effective price, partial history, or unreported tokens |
| User report returns 404 | Target profile is not visible to that viewer under the author-profile contract |
