# Web/admin boundaries and verification

## Choose the correct application

`apps/web` is the public Naturebook surface. It serves public share/species
content and narrow public actions. `apps/admin` is a separately deployed,
authenticated operations application. Do not move code, environment variables,
or Supabase clients between them merely to reduce duplication.

## Public web boundary

- Render Explore data only through reviewed public projections/RPCs. Do not
  reconstruct hidden or private content with direct table reads or a privileged
  fallback.
- Species pages expose only licensed public reference data and attribution; do
  not add observations, user media, private locations, or scan data.
- Keep privileged Supabase credentials server-only and isolated in the existing
  admin/server module. The public client accepts only public credentials.
- Validate outbound media origins and formats before proxying. Bound body size,
  duration, deadlines, and decoded work.
- Fail closed to not-found/non-indexable output for unshared, hidden,
  tombstoned, blocked, or malformed content.
- Keep telemetry optional, privacy-safe, and limited to public ingestion keys.

Read `apps/web/README.md` plus the relevant public-brand, public-share, or
backend contract document before changing these paths.

## Internal admin boundary

- `apps/admin` must never receive a service-role key, database URL, deployment
  token, provider key, RevenueCat secret, or production environment clone.
- Browser and server clients both use the public Supabase URL and publishable or
  anon key. Every privileged data action goes through a narrowly granted RPC.
- `getUser()` is a routing optimization, not authorization. Each RPC rechecks
  Google identity, active membership, required role, TOTP AAL2, Supabase session
  ID, internal session age, and revocation state.
- Keep raw operator routes `no-store`, request bodies out of URLs, pagination
  bounded, and actions auditable. Preserve last-owner and session-revocation
  protections.
- Redirect destinations must be exact validated origins and safe local paths;
  reject absolute, protocol-relative, backslash, encoded-separator, credential,
  query-on-origin, and fragment-on-origin variants.

Read `apps/admin/README.md`, `docs/backend-and-data/10-internal-admin.md`, and
`docs/backend-and-data/11-internal-admin-operations.md` for admin changes.

## Payload and backend changes

If a page needs new data, do not widen an existing projection casually. Load
`$merian-api-contracts` and `$merian-supabase`, define the least-privilege
server contract, add RLS/grant/RPC tests, update typed consumers, and validate
all callers. Public and admin responses must not share a type if doing so
exposes fields across their trust boundary.

## Package verification

For `apps/web` or `apps/admin`:

```text
npm ci --include=dev
npm run audit:dependencies
npm test
npm run typecheck
npm run build
```

Run commands from the affected package. A dependency change requires review of
the complete lockfile diff and all optional native packages. Do not weaken audit
levels, version floors, overrides, or CI ordering to make a new graph pass.

Also run the repository workflow/contract tests when editing `.github`, package
scripts, security-boundary tests, deployment configuration, or shared backend
contracts. A required check and exact-SHA deployment hold remain release
controls; a manual promote is not routine bypass authority.
