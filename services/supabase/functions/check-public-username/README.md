# Check Public Username

Authenticated endpoint for validating a candidate public username without
updating the current user's profile. This backs inline availability checks in
the Profile username editor.

## Request

```json
{
  "username": "@Stone Glen 72"
}
```

- `username` is required.
- A pasted leading `@` is accepted and stripped.
- Spaces and punctuation normalize to underscores.
- The current user's own username is treated as available.
- Authentication is resolved by `withEdgeHandler`; the body cannot choose a user
  ID.

## Response

```json
{
  "available": true,
  "username": "stone_glen_72",
  "error": null
}
```

Invalid or taken usernames return `200` with `available: false` and an `error`
message suitable for inline UI. The update endpoint still enforces the same
validation and uniqueness rules on save. Protected brand namespaces,
official/system roles, and exact brand-role combinations in either order are
reserved; ordinary handles are not rejected through broad prefix matching.

The shared Edge validator is an early-feedback mirror. PostgreSQL's validated
profile CHECK is the final authority on save, and the cross-layer migration
contract fails if the PostgreSQL, Edge, or iOS policy groups drift. See
[`21-public-usernames.md`](../../../../docs/features-and-hardware/21-public-usernames.md)
for the complete reserved groups, deterministic existing-profile repair, and
historical mention exception.

## Local Verification

```sh
deno fmt --check services/supabase/functions/check-public-username services/supabase/functions/update-public-username/validation.ts
deno lint --config services/supabase/functions/deno.json services/supabase/functions/check-public-username services/supabase/functions/update-public-username/validation.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/check-public-username/index.ts
deno test --frozen --config services/supabase/functions/deno.json services/supabase/functions/update-public-username/validation_test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase,apps/ios services/supabase/functions/_tests/publicUsernamePolicyMigrationContract.test.ts
```
