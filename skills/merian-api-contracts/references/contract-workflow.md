# Cross-client contract workflow

Use this workflow for requests, responses, webhooks, events, generated models,
and fields shared by two or more of Deno, Swift, public web, or internal admin.

## 1. Map the contract before editing

Record:

- the executable schema or type that owns field names, types, nullability,
  bounds, enums, and defaults;
- every producer and whether it emits old and new shapes during rollout;
- every decoder, mapper, persistence layer, UI surface, test fixture, and doc;
- error/status behavior and authorization assumptions; and
- whether stored/replayed payloads require compatibility.

Search by field name and by containing type. Do not assume identical-looking
TypeScript, Swift, and React types are generated from the same authority.

For Identify, read the relevant Function README, shared Identify types/schema,
`apps/ios/Merian/Core/AI/README.md`, and the API-contract documentation. The
marked block in `InferenceEdgeDTOs.swift` is generated; mappings outside that
block remain hand-owned.

## 2. Change the authority first

- Update the executable schema and owning runtime together.
- Define compatibility intentionally: additive optional field, dual-read
  transition, versioned endpoint, or coordinated breaking cutover.
- Keep arrays, strings, media metadata, and nested graphs bounded before
  allocation. Preserve stable error codes and caller-safe status behavior.
- Never use `any`, `@ts-ignore`, unchecked casts, or decoder fallbacks to conceal
  drift.
- Preserve authentication and ownership at the server boundary; a client field
  is not authorization evidence.

## 3. Generate, then inspect

For the Identify Swift contract:

```text
make generate-edge-dto-contract
git diff -- apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift
make validate-edge-dto-contract
```

The middle step is mandatory. Check names, optionality, numeric widths, nested
types, collections, coding keys, and unexpected deletion. Do not hand-edit the
generated block. Fix the authority or generator and regenerate.

For a contract without a generator, update each typed boundary explicitly and
add a fixture proving the same payload is accepted or rejected consistently.

## 4. Update mappings and consumers

- Swift: generated DTO → domain model → persistence/presentation. Verify decode
  compatibility and avoid silently dropping a new semantic field.
- Public web: expose only public/user-authorized fields. Do not import an admin
  or service-role response type into a browser bundle.
- Internal admin: preserve server-only auth, auditability, and bounded operator
  workflows. Never weaken an endpoint because the UI is internal.
- Webhooks/background jobs: verify signature/auth handling, idempotency, replay,
  and durable stored payload compatibility.

## 5. Validate all affected surfaces

- Run `make validate-edge-dto-contract` and the complete affected Supabase
  tooling gate.
- Run recursive `deno check` and focused Function tests for each changed Deno
  entry point.
- Build and test the iOS DTO/domain consumers.
- In each affected web package, run `npm test`, `npm run typecheck`, and
  `npm run build` using the repository's pinned Node/npm versions.
- Update `docs/backend-and-data/05-api-contracts.md`, the owning README, and any
  architecture page whose boundary changed.

Report the reviewed generation diff and every consumer checked. Do not deploy
or publish merely because these checks pass.
