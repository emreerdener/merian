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
3. Admin test, typecheck, and production build.
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
the local Supabase database and wrap their fixtures in transactions.

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
npm run typecheck
npm test
npm run build
```

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
6. Deploy `apps/admin` as its own project with Root Directory `apps/admin` and
   attach only `admin.naturebook.earth`.
7. Configure the exact production Auth redirect, verify Google sign-in and TOTP,
   and bootstrap the first owner if this is the initial release.
8. Run the production smoke tests below before announcing availability.

For a manual emergency database/function deployment, use the established
commands in [`06-supabase-deployment-runbook.md`](./06-supabase-deployment-runbook.md).
Never run a partial shared-helper deployment without its transitive consumers.

## Production smoke tests

Use disposable staff test accounts and records where mutation is required.

### Authentication and roles

- Anonymous request: admin routes redirect to login; admin RPC execution fails.
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
- Account deletion anonymizes AI linkage but retains aggregate usage/cost. It
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

## Rollback

- The admin frontend can be rolled back or removed from DNS independently; this
  does not require deleting database state.
- Edge writers may be rolled back to a compatible prior version, but keep the
  ledger schema and grants in place.
- Do not down-migrate by dropping `internal`, audit rows, notes, review grouping,
  moderation columns, or usage events. These contain durable operational history.
- If a public projection regression occurs, remove access to the admin frontend,
  restore the last known-good projection functions through a forward migration,
  and verify hidden content remains fail-closed.

## Troubleshooting

| Symptom | Check |
|---|---|
| OAuth returns to login | Exact redirect allowlist, Google provider config, callback `code`, public URL/key |
| Member sees “not authorized” | Exact Auth UUID, active membership, confirmed email, non-anonymous account, Google identity |
| User loops through MFA | Factor status, `currentLevel`, fresh token after verify, browser cookie domain |
| “Start a new Google session” | Internal session is idle/expired/revoked; sign out and begin a new OAuth session |
| Mutation says invalid origin | `NEXT_PUBLIC_ADMIN_ORIGIN`, reverse-proxy `Host`/`X-Forwarded-Host`, browser `Origin` |
| Direct table read fails | Expected; use an authorized RPC, never add browser table grants |
| Aggregate appears stale | Five-minute authorized cache; use the Refresh control |
| Queue appears stale | Queue is uncached; check filters/cursor and the 30-second refresh |
| Estimated cost is null/low | Missing exact model/modality effective price, partial history, or unreported tokens |
| User report returns 404 | Target profile is not visible to that viewer under the author-profile contract |
