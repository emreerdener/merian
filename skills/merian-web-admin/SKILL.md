---
name: merian-web-admin
description: "Implement and review Merian's Next.js public web and internal admin applications, including routes, server/client boundaries, Supabase clients, environment ownership, privacy projections, authentication, authorization, dependency changes, and package-local tests, type checks, and builds. Use for work under apps/web or apps/admin."
---

# Merian web and admin

Keep `apps/web` and `apps/admin` separate security products even though they use
similar frameworks and Supabase libraries.

## Start with the owning boundary

1. Read `AGENTS.md`, inspect `git status`, and read the affected package README.
2. Read [boundaries-and-verification.md](references/boundaries-and-verification.md)
   completely before changing data access, auth, environment variables, routes,
   dependencies, or deployment checks.
3. Load `$merian-api-contracts` for payload changes and `$merian-supabase` for
   RPC, RLS, database, Auth, Storage, or Edge Function changes.
4. Trace whether code is server-only, browser-delivered, public, authenticated,
   or privileged. Do not infer safety from a filename or an "internal" label.

## Implementation rules

- Public pages consume privacy-safe projections and fail closed when content is
  hidden, tombstoned, unshared, or otherwise ineligible.
- The admin application uses only the public Supabase URL and publishable/anon
  key. Authorization lives in narrowly granted RPCs that recheck identity,
  membership, AAL2, session, age, and role.
- Keep server-only secrets out of client bundles and `NEXT_PUBLIC_*` variables.
- Preserve exact dependency pins, lockfiles, reviewed overrides, and package
  ownership. Do not share a privileged client between packages.
- Maintain bounded pagination, request deadlines, no-store behavior for raw
  admin data, safe redirect validation, and caller-safe errors.

## Verify per package

Use the repository-pinned Node and npm versions. In every affected package run
the frozen install when dependency state changed, then dependency audit, tests,
type check, and production build. Also run the affected GitHub workflow contract
tests. Update the package README and canonical docs when a route, payload,
privacy/auth boundary, environment variable, or operational gate changes.

Successful local builds do not authorize Vercel promotion or any backend
mutation; use `$merian-release` only for an explicitly requested release action.
