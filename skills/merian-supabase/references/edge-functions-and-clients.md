# Edge Functions and Client Contracts

## Read the owning contracts

Before editing an Edge or client boundary, read:

- `docs/system-architecture/06-edge-modularization.md`
- `docs/backend-and-data/05-api-contracts.md`
- the affected Function's `README.md`
- `services/supabase/functions/_shared/README.md`
- the relevant feature or incident document linked by those files

Search `_shared/` before creating a helper. Reuse the existing auth, HTTP,
outbound, storage, media-budget, concurrency, telemetry, and error boundaries.

## Preserve the module boundary

- Keep `index.ts` as the HTTP orchestrator: authenticate, validate bounded
  input, enforce IDOR guards, call domain/data helpers, and shape the response.
- Put PostgREST reads and writes in `db.ts`. Bound every variable-cardinality
  result in the query itself.
- Keep request and database interfaces explicit. Do not introduce `any` or
  `@ts-ignore`.
- Change identify response shapes in `_shared/identify/contract.ts`, regenerate
  `InferenceEdgeDTOs.swift`, and update every producer and consumer in the same
  change. Do not maintain a second hand-written wire model.
- Await every operation required by the documented success boundary. Use
  background work only for optional, idempotent follow-up; it is not durable
  execution.

## Preserve authentication and secret boundaries

- Treat `verify_jwt = false` as "the handler owns authentication," not "the
  route is public." Inspect the handler and its shared wrapper before changing
  the config entry.
- Derive user identity from the validated JWT, never from a caller-selected
  payload field. Bound mutations to that identity.
- Use `functions/_shared/serviceRoleClient.ts` as the only privileged SDK
  factory. Create downstream clients from environment-resolved credentials,
  never from the credential accepted on an inbound request.
- Keep publishable keys in the standard `apikey` header. Never expose or log a
  secret/service key, database URL, token fragment, response body, or variable
  request ID.
- Keep database authorization as a second boundary for privileged RPCs; an Edge
  check does not replace the routine allowlist, fixed search path, grant, and
  in-function caller guard.

## Preserve resource and error boundaries

- Use the smallest shared JSON body class that admits a valid request. Keep
  array counts, string lengths, UUIDs, media bytes, streaming reads, deadlines,
  and outbound concurrency explicitly bounded.
- Use `Deno.serve(...)` and the pinned shared dependency graph. Do not add
  direct runtime URL, npm, or JSR imports to deployable code.
- Use the shared public error envelope and fixed handler marker. Log detailed
  failures privately through the structured error boundary; return stable,
  caller-safe codes and messages.
- Preserve zero-PII telemetry. Do not log names, emails, raw coordinates,
  request bodies, object keys, tokens, or unbounded provider diagnostics.

## Verify

Run focused tests first, then the applicable complete surface gate:

```bash
deno fmt --check services/supabase/functions services/supabase/scripts
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions services/supabase/scripts
make test-supabase-tooling
make validate-edge-dto-contract
(cd services/supabase/functions && deno task test)

deno run --allow-read=services/supabase \
  services/supabase/scripts/sync_function_deno_configs.ts --check
deno run --allow-read=services/supabase \
  services/supabase/scripts/validate_function_dependencies.ts
deno check --frozen \
  --config services/supabase/functions/<function>/deno.json \
  services/supabase/functions/<function>/index.ts
```

When a Swift caller or response shape changes, run the relevant iOS contract
and build tests as well. Update `docs/backend-and-data/05-api-contracts.md` and
the feature documentation whenever the public or durable wire contract changes.
