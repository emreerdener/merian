# Naturebook Internal Admin

Private Next.js + Mantine operations application for
`admin.naturebook.earth`. Deploy it separately from `apps/web`.

The application uses only Supabase's public URL and publishable/anon key. Never
configure a service-role key, direct database URL, Gemini key, or third-party
analytics token in this project. Every data operation goes through a narrowly
granted authenticated RPC that rechecks Google identity, active membership,
TOTP `aal2`, the live Supabase Auth `session_id`, internal session age, and role.

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
npm run typecheck
npm test
npm run build
```

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
