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
validation and uniqueness rules on save.

## Local Verification

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/check-public-username/index.ts
```
