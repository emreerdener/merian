# Public Usernames

Public usernames are Merian's stable public handles for Explore identity and
future comment mentions. They are stored without `@` and rendered as
`@username` in UI.

## Product Contract

- Every `public.users` row has a canonical `public_username`.
- Usernames are lowercase ASCII letters, numbers, and underscores only.
- Usernames are 3 to 24 characters, start with a letter, end with a letter or
  number, and cannot contain repeated underscores.
- Reserved system names such as `admin`, `api`, `explore`, `merian`, `support`,
  and `system` are rejected.
- `@` is presentation-only. The backend accepts pasted `@name` input by
  stripping the marker during normalization, but never stores it.
- Logged-in users can keep showing their provider-derived public display name on
  Explore posts, such as `Emre E.`.
- Ghost/default-alias users show the handle on Explore, such as `@stone_glen_72`.
- Future comment tagging must use `public_username`, not `public_author_name`.

## Display Rules

Explore card, detail, comment, map, notification, and widget surfaces continue
to treat `author_name` as the public display label. When `author_name` is empty
or equals `author_username`, clients render `@author_username` instead of a
friendly full-name-style label.

Profile and public author profile surfaces may show both identities:

- primary line: display/account name when available
- secondary line: `@public_username`

The Profile user card replaces the private email line with the public handle.
The username edit sheet is reachable from that card's profile menu.

## Database Model

Migration:

```text
services/supabase/migrations/20260526090000_add_public_usernames.sql
```

The migration adds:

- `public.users.public_username TEXT NOT NULL`
- `users_public_username_valid_check`
- `users_public_username_unique_idx`
- `normalize_public_username(raw_username TEXT)`
- `is_reserved_public_username(candidate_username TEXT)`
- `is_valid_public_username(candidate_username TEXT)`
- `build_default_public_username(target_user_id UUID)`
- `build_unique_public_username(raw_username TEXT, target_user_id UUID)`

Backfill derives usernames from existing `public_author_name` where possible,
falls back to a deterministic default, and adds deterministic suffixes for
collisions. Alias-source public author names are aligned to the chosen username
so default identities display as handles in clients.

`public_author_name` remains the display label. `public_username` is the stable
handle.

## Edge Function

`update-public-username` is an authenticated app-facing Edge Function. Its
Supabase gateway entry uses `verify_jwt = false` and identity is resolved
inside `withEdgeHandler`, matching other anonymous-session-compatible app
endpoints.

Request:

```json
{
  "username": "@Stone Glen 72"
}
```

Response:

```json
{
  "username": "stone_glen_72"
}
```

The function normalizes input, validates the policy, checks uniqueness excluding
the current user, updates `public.users.public_username`, and returns `409` when
the normalized handle is already taken. If the user's public identity source is
`alias`, the function also updates `public_author_name` to the same username so
Explore default identities continue to render as handles.

## Explore Payloads

Explore card-shaped payloads now include `author_username` alongside
`author_name`:

```json
{
  "author_user_id": "uuid",
  "author_name": "Emre E.",
  "author_username": "emre_e",
  "author_avatar_url": "https://..."
}
```

The field is additive and optional for rollout tolerance. Existing clients can
ignore it; newer clients use it for profile handles and default/ghost author
rows.

## iOS Touchpoints

- `ProfileViewModel.fetchPublicIdentity()` reads `public_username` and
  `public_author_name` from `public.users`.
- `ProfileViewModel.checkPublicUsernameAvailability(_:)` calls
  `check-public-username` so the editor validates uniqueness against existing
  usernames before save.
- `ProfileViewModel.updatePublicUsername(_:)` calls the Edge Function, refreshes
  local state, and publishes `.publicAuthorIdentityChanged`.
- `UserProfile` shows `@publicUsername` in the account card and presents
  `PublicUsernameEditSheet`; the editor uses a single username field, an X close
  button, inline validation, and a primary save button below the input.
- `ExplorePost.publicAuthorDisplayName(from:username:)` keeps logged-in display
  names and renders handles for default identities.
- `ExploreAuthorProfileSheet` shows `@authorUsername` under the display name
  when available.

## Testing

Recommended checks:

```sh
deno check services/supabase/functions/check-public-username/index.ts
deno check services/supabase/functions/update-public-username/index.ts
deno test services/supabase/functions/_tests/updatePublicUsername.test.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreIdentityDb.test.ts
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The DB-backed tests require a local Supabase Postgres schema at
`127.0.0.1:54322`.
