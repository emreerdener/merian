# Edge, Auth, and Client Boundaries

## Verify current integration guidance

Read the current official documentation for the affected client library,
framework integration, and runtime. Check checked-in dependency versions and
lockfiles before selecting an API. Do not replace a repository-supported auth
or SSR pattern solely because a newer example exists.

## Preserve authentication and authorization

- Validate the caller at the trusted server or database boundary. Never accept
  a caller-selected user ID as authorization.
- Treat `verify_jwt = false` as "the handler owns authentication," not as proof
  that a route is intentionally public. Inspect the handler before changing
  gateway configuration.
- Distinguish reading cached session state from verifying a user or token with
  an authoritative server. Choose the API required by the threat model and the
  current library documentation.
- Remember that deleting a user does not necessarily invalidate already-issued
  access tokens. Design revocation and sensitive operations accordingly.
- Treat `app_metadata` or other token claims as potentially stale until token
  refresh. Never use user-editable metadata for authorization.

## Protect keys and privileged clients

- Use publishable or legacy anonymous keys only in public clients. Never ship a
  secret or service-role key to a browser, mobile app, or public bundle.
- Construct privileged clients only on trusted servers from server-managed
  credentials. Do not forward an inbound caller token into a privileged client
  factory.
- Do not log credentials, token fragments, database URLs, request bodies,
  provider response bodies, emails, names, raw coordinates, or other user data.
- Pin package versions and commit the applicable lockfile. Review dependency
  provenance before adding Supabase, SSR, or runtime packages.

## Preserve Edge and API contracts

- Keep request size, array count, string length, media bytes, deadlines,
  response bytes, and outbound concurrency bounded.
- Await every operation required by the documented success boundary. Background
  execution is appropriate only for optional, idempotent work unless a durable
  queue or job contract exists.
- Return stable caller-safe errors and keep detailed diagnostics within the
  private structured logging boundary.
- Update generated types and every producer and consumer together when a wire
  contract changes.

## Preserve Storage and Realtime access

- Treat Storage policies as database authorization. Test object ownership,
  prefixes, bucket access, and cross-user denial with actual caller roles.
- Storage upsert generally needs INSERT, SELECT, and UPDATE access; verify the
  exact SDK operation and policies instead of adding broad grants.
- Configure reviewed bucket file-size and allowed-MIME limits, and validate
  untrusted content at the trusted processing boundary when a client-supplied
  MIME header is not sufficient. Test rejected size, MIME, path, owner, and
  cross-user cases as well as the successful upsert.
- Authenticate Realtime channels and test both subscription and database RLS
  boundaries. A client-side filter is not authorization.

Run focused unit tests, runtime type checks, and end-to-end caller tests for the
changed boundary before reporting completion.
