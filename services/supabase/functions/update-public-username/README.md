# Update Public Username

Authenticated endpoint for editing the current user's canonical public username
handle. This backs the Profile account-card username edit sheet.

## Request

```json
{
  "username": "@Stone Glen 72"
}
```

- `username` is required.
- A pasted leading `@` is accepted and stripped.
- Spaces and punctuation normalize to underscores.
- The request is authenticated through `withEdgeHandler`; the body cannot choose
  a user id.

## Response

```json
{
  "username": "stone_glen_72"
}
```

The returned username is stored without `@`. Clients render it as
`@stone_glen_72`.

## Validation

Stored usernames must:

- be lowercase ASCII letters, numbers, and underscores only
- be 3 to 24 characters
- start with a letter
- end with a letter or number
- avoid repeated underscores
- avoid protected brand namespaces (`explore`, `merian`, `naturebook`, and
  `naturebookearth`), official/system roles such as `admin`, `security`,
  `support`, and `verified`, and exact brand-role combinations in either order
  such as `naturebook_support` or `support_naturebook`
- be unique across `public.users.public_username`

Invalid normalized usernames return `400`. Taken usernames return `409`.
Reservations use exact words and exact brand-role combinations rather than a
broad prefix rule, so ordinary community handles such as `naturebook_fan` and
`security_researcher` remain available. A username never grants an
administrative role or capability.

## Policy Authority and Rollout

`validation.ts` supplies caller-safe early feedback for both this route and
`check-public-username`. PostgreSQL remains authoritative through
`public.is_reserved_public_username(...)` and the validated
`users_public_username_valid_check`; privileged or future write paths cannot
bypass the policy by omitting Edge validation.

Migration `20260808144244_expand_reserved_public_username_policy.sql` repairs
existing profiles whose handles are reserved under the expanded policy with
deterministic neutral aliases. It does
not rewrite `explore_comment_mentions.mention_username`, because that column is
the historical token embedded in immutable plain-text comment bodies. The
complete policy groups and snapshot rationale are documented in
[`21-public-usernames.md`](../../../../docs/features-and-hardware/21-public-usernames.md).

## Display Side Effect

`public_username` is the stable handle. `public_author_name` remains the Explore
display label.

If the current user's `public_identity_source` is `alias`, this endpoint also
updates `public_author_name` to the new username. That keeps default/ghost
Explore rows rendering as `@username`. Users with provider-derived display names
keep their existing `public_author_name`, so Explore posts still show labels
such as `Emre E.` while profile surfaces can show `@emre_e` underneath.

## Local Verification

```sh
deno fmt --check services/supabase/functions/update-public-username services/supabase/functions/_tests/updatePublicUsername.test.ts
deno lint --config services/supabase/functions/deno.json services/supabase/functions/update-public-username services/supabase/functions/_tests/updatePublicUsername.test.ts services/supabase/functions/_tests/publicUsernamePolicyMigrationContract.test.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/update-public-username/index.ts
deno test --frozen --config services/supabase/functions/deno.json services/supabase/functions/update-public-username/validation_test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase,apps/ios services/supabase/functions/_tests/publicUsernamePolicyMigrationContract.test.ts
make validate-supabase-migrations
make test-supabase-privileged-routines
```
