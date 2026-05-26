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
- avoid reserved names such as `admin`, `api`, `explore`, `merian`, `support`,
  and `system`
- be unique across `public.users.public_username`

Invalid normalized usernames return `400`. Taken usernames return `409`.

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
deno lint services/supabase/functions/update-public-username services/supabase/functions/_tests/updatePublicUsername.test.ts
deno check services/supabase/functions/update-public-username/index.ts
deno test services/supabase/functions/_tests/updatePublicUsername.test.ts
```
