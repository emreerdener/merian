# Naturebook Internal Admin

Private Next.js + Mantine operations application for
`admin.naturebook.earth`. Deploy it separately from `apps/web`.

The application uses only Supabase's public URL and publishable/anon key. Never
configure a service-role key, direct database URL, Gemini key, or third-party
analytics token in this project. Every data operation goes through a narrowly
granted authenticated RPC that rechecks Google identity, active membership,
TOTP `aal2`, the live Supabase Auth `session_id`, internal session age, and role.

Do not clone the GitHub `Production` or public-web Vercel environment into this
project. This explicitly excludes `SUPABASE_ACCESS_TOKEN`,
`SUPABASE_DB_URL`, `SUPABASE_DB_PASSWORD`, every `REVENUECAT_*` server secret,
and `DWCA_PSEUDONYM_HMAC_KEY_V1`. The complete cross-environment destination
matrix is in
[`docs/development-guides/05-keychain-and-secrets.md`](../../docs/development-guides/05-keychain-and-secrets.md#deployment-environment-ownership).

## Documentation

- Architecture, roles, data model, RPCs, metrics, review lifecycle, and AI
  ledger: [`docs/backend-and-data/10-internal-admin.md`](../../docs/backend-and-data/10-internal-admin.md)
- Local/production setup, bootstrap, deployment, recovery, and smoke tests:
  [`docs/backend-and-data/11-internal-admin-operations.md`](../../docs/backend-and-data/11-internal-admin-operations.md)
- Backend-wide deployment rules:
  [`docs/backend-and-data/06-supabase-deployment-runbook.md`](../../docs/backend-and-data/06-supabase-deployment-runbook.md)

## Prerequisites

- The internal-admin migration has been applied.
- Supabase Google Auth is configured.
- The exact local/production callback URL is in the Auth redirect allowlist.
- The first owner has signed in with Google and been bootstrapped by immutable
  Auth UUID, or an existing owner has added the account by exact verified email.
- The user has a verified TOTP factor or can enroll one at `/mfa`.

## Environment

Copy `.env.example` to `.env.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
NEXT_PUBLIC_ADMIN_ORIGIN=http://localhost:3000
```

Production uses `NEXT_PUBLIC_ADMIN_ORIGIN=https://admin.naturebook.earth`.
Allowed application callbacks are:

- `http://localhost:3000/auth/callback`
- `https://admin.naturebook.earth/auth/callback`

Keep production redirects exact; do not add a broad admin-host wildcard.

## Local commands

```bash
npm ci
npm run dev
```

Before opening a pull request or deploying:

```bash
npm ci --include=dev
npm run audit:dependencies
npm test
npm run typecheck
npm run build
```

`.github/workflows/admin-quality.yml` runs `npm ci --include=dev` followed by
that complete sequence for every pull request and every affected `main` push. It
deliberately reports on every pull request so GitHub can require a stable check
without path-filtered changes remaining pending. The currently protected graph
pins Next.js 16.2.12 and PostCSS 8.5.25 and overrides Next.js's private Sharp
dependency to 0.35.3. `lib/dependency-security.test.ts`
rejects a lockfile below those floors or a workflow that drops or reorders the
frozen install, blocking audit, tests, type-check, and production build. Keep
the overrides until a reviewed Next.js release declares equal or newer
transitive versions; do not remove them merely because the direct PostCSS
dependency is current.

Repository and deployment controls must make
`Naturebook Admin Quality / test` a required check before any change can merge
or reach the production Vercel project. The workflow file creates the check but
cannot make itself required. Add that GitHub Action as a required Vercel
Deployment Check so a production build is not promoted to the custom domain
until the exact commit's check passed; never treat Force Promote or a direct
manual deployment as routine bypass authority.

When changing dependencies:

1. Update `package.json` and regenerate the committed `package-lock.json`.
2. Review every lockfile version/source change, including optional native Sharp
   packages.
3. Run the complete command sequence above with registry access.
4. Confirm the pull request reports `Naturebook Admin Quality / test`.
5. Confirm the production deployment remains held until its required Vercel
   Deployment Check passes for that exact commit.

Do not waive a high/critical audit result by weakening `audit:dependencies`,
removing a floor test, or using Force Promote. A time-limited exception requires
a documented reachability analysis, owner/security approval, compensating
controls, and an explicit removal date.

## First-owner bootstrap

After the intended owner has completed their first Google sign-in, verify the
immutable UUID in Supabase Auth and run once through a trusted SQL session:

```sql
select internal.bootstrap_first_admin_owner('AUTH-USER-UUID'::uuid);
```

The function rejects anonymous/non-Google users and refuses to run after any
membership exists. All later access changes are made by an owner from `/access`.
The final active owner cannot be disabled or demoted.

## Routes

| Route | Minimum role | Purpose |
|---|---|---|
| `/overview` | Analyst | Account, plan, scan, moderation, feedback, and cost aggregates |
| `/ai-usage` | Analyst | Token, modality, cache, percentile, and estimated-cost analytics |
| `/complimentary-entitlements` | Analyst | Three-scan balances, hold age, settlement, Flash fallback, exhaustion, and paid conversion aggregates |
| `/reviews` | Moderator | Live grouped moderation/identification queue |
| `/reviews/[caseId]` | Moderator | Evidence, context, notes, transitions, and hide/restore |
| `/feedback` | Moderator | Unified feedback workflow overlay |
| `/users` | Moderator | Audited account search and detail |
| `/access` | Owner | Memberships, sessions, revocation, and audit history |

Raw routes are always `no-store`. Overview and AI aggregate results may be
cached in the private database schema for five minutes after authorization.
Review queues are uncached and refresh every 30 seconds.

## Session behavior

An admin session is valid for at most eight hours and expires after 30 minutes
without a successful authorized RPC. Revoked, expired, and disabled sessions
cannot be revived with the same Google session; sign out and start OAuth again.

Server-side routing calls `supabase.auth.getUser()` before the restricted
`admin_get_access_state` RPC. Missing or invalid cookies return the local
unauthenticated state immediately, so ordinary anonymous visits do not generate
avoidable `401`/`42501` RPC noise. This is only a log-noise and latency guard:
`requireAdmin(...)` still calls the database RPC, and every privileged RPC still
rechecks membership, role, AAL2, Supabase session ID, and internal-session age.
Never treat the `getUser()` result alone as admin authorization.

Supabase documents `getUser()` as an authentic network-validated user lookup;
see the
[JavaScript Auth reference](https://supabase.com/docs/reference/javascript/auth-getuser).
