# Public Usernames

Public usernames are Merian's stable public handles for Explore identity and
comment mentions. They are stored without `@` and rendered as `@username` in UI.

Public avatars are part of the same public identity projection. Custom uploaded
avatars are documented here because feed/profile identity payloads carry
`author_username`, `author_name`, and `author_avatar_url` together.

## Product Contract

- Every `public.users` row has a canonical `public_username`.
- Usernames are lowercase ASCII letters, numbers, and underscores only.
- Usernames are 3 to 24 characters, start with a letter, end with a letter or
  number, and cannot contain repeated underscores.
- Reserved names include protected brand namespaces (`explore`, `merian`,
  `naturebook`, and `naturebookearth`), official/system roles such as `admin`,
  `security`, `support`, and `verified`, and exact brand-role combinations in
  either order such as `naturebook_support` and `support_naturebook`.
- Reservation is exact rather than prefix-based: community handles such as
  `naturebook_fan` and `security_researcher` remain valid.
- Usernames are public identity only. No username grants an administrative role,
  authorization claim, or trusted badge.
- The reservation applies to `public_username`, not `public_author_name`.
  Display labels can be duplicated and must never be treated as proof that an
  account is staff, verified, or otherwise trusted.
- `@` is presentation-only. The backend accepts pasted `@name` input by
  stripping the marker during normalization, but never stores it.
- Logged-in users can keep showing their provider-derived public display name on
  Explore posts, such as `Emre E.`.
- Ghost/default-alias users show the handle on Explore, such as
  `@stone_glen_72`.
- Explore comment tagging uses `public_username`, not `public_author_name`.
- `public_avatar_url` resolves to a custom Merian avatar first and an OAuth
  provider avatar second.

## Reserved-Name Policy

App-facing candidate input is normalized to its lowercase stored form before the
policy runs; direct database writes must already be canonical and are rejected
rather than rewritten. The current reserved groups are:

| Group                     | Reserved values                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sentinels                 | `null`, `undefined`                                                                                                                                                                                                                                                                                                                                                               |
| Product namespaces        | `explore`, `merian`, `naturebook`, `naturebookearth`                                                                                                                                                                                                                                                                                                                              |
| Official/system roles     | `abuse`, `account`, `accounts`, `admin`, `administrator`, `api`, `auth`, `billing`, `bot`, `contact`, `customer_service`, `customer_support`, `developer`, `developers`, `help`, `legal`, `moderation`, `moderator`, `notifications`, `official`, `press`, `privacy`, `root`, `safety`, `security`, `staff`, `status`, `support`, `system`, `team`, `trust`, `verified`, `verify` |
| Product-role combinations | Every exact `<product>_<role>` and `<role>_<product>` combination, such as `naturebook_support` and `support_naturebook`                                                                                                                                                                                                                                                          |

Separators normalize before evaluation on the app-facing path, so pasted input
such as `Naturebook Support` becomes `naturebook_support` and is rejected. The
rule does not reserve arbitrary prefixes, suffixes, or substrings:
`naturebook_fan`, `naturebook_supporter`, `security_researcher`, and `team_wren`
remain valid.

PostgreSQL is authoritative through `public.is_reserved_public_username(...)`
and the `users_public_username_valid_check` constraint. The Edge validation and
iOS edit-sheet sets in
`Features/Profile/UserProfile/Views/Identity/PublicUsernameEditSheet.swift` are
early-feedback mirrors. The static migration contract parses all three
implementations and fails if a group, ordering rule, or combination direction
drifts. Authorization must always come from server-owned roles or claims;
neither a username nor a display label is an authorization boundary.

## Display Rules

Explore card, detail, comment, map, notification, and widget surfaces continue
to treat `author_name` as the public display label. When `author_name` is empty
or equals `author_username`, clients render `@author_username` instead of a
friendly full-name-style label.

Profile and public author profile surfaces may show both identities and the
resolved public avatar:

- primary line: display/account name when available
- secondary line: `@public_username`
- avatar: `public_avatar_url` when present, falling back client-side only while
  the profile projection is still loading

The Profile user card replaces the private email line with the public handle.
The username edit sheet is reachable from that card's profile menu.

## Database Model

Migrations:

```text
services/supabase/migrations/20260526090000_add_public_usernames.sql
services/supabase/migrations/20260808144244_expand_reserved_public_username_policy.sql
```

The initial migration adds:

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

The expanded-policy migration makes PostgreSQL authoritative for protected
brand, role, and exact brand-role reservations. It assigns a neutral,
deterministic, collision-safe alias to any existing profile whose handle becomes
reserved and keeps alias-source `public_author_name` aligned. Historical
`explore_comment_mentions.mention_username` values remain unchanged because the
plain-text comment body stores the original `@username` token verbatim. The
migration rebuilds and validates the profile's policy-aware CHECK and the
mention snapshot's structural CHECK separately. PostgreSQL does not otherwise
recheck existing rows when an immutable function used by a validated CHECK
constraint changes.

Affected profiles are locked and repaired in stable user-ID order. The repair
uses `build_default_public_username(...)` followed by
`build_unique_public_username(...)`; it does not retain an official-looking
prefix such as `admin_...` or `security_...`. Profiles with a derived or chosen
display name keep that display label. Only alias-source rows align
`public_author_name` to the replacement handle.

`public_author_name` remains the display label. `public_username` is the stable
handle. `custom_avatar_url` and `custom_avatar_updated_at` were added later by
`20260528120000_add_custom_public_avatars.sql`; identity refresh helpers now
compute `public_avatar_url` with `custom_avatar_url` precedence so provider
metadata updates cannot overwrite a user-uploaded profile picture.

Migration `20260720042641_optimize_explore_author_maintenance.sql` makes the
identity refresh idempotent and restricts both identity refresh and Explore post
ownership repair to `service_role`. Auth triggers and public write/ghost-merge
paths own refreshes. Feed, profile, map, comment, notification, and other
Explore reads consume the existing projection and never perform maintenance
writes.

## Edge Function

`update-public-username` is an authenticated app-facing Edge Function. Its
Supabase gateway entry uses `verify_jwt = false` and identity is resolved inside
`withEdgeHandler`, matching other anonymous-session-compatible app endpoints.

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

The function normalizes input, validates the same exact/brand/role policy used
by PostgreSQL and iOS, checks uniqueness excluding the current user, updates
`public.users.public_username`, and returns `409` when the normalized handle is
already taken. If the user's public identity source is `alias`, the function
also updates `public_author_name` to the same username so Explore default
identities continue to render as handles.

`check-public-username` uses the same shared Edge validator without mutating the
profile. Both Edge routes provide early, caller-safe feedback; the PostgreSQL
CHECK remains the final defense for every write path, including privileged or
future server code.

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
  `public_author_name` from `public.users`, plus `public_avatar_url` for the
  resolved profile image.
- `ProfileViewModel.checkPublicUsernameAvailability(_:)` calls
  `check-public-username` so the editor validates uniqueness against existing
  usernames before save.
- `ProfileViewModel.updatePublicUsername(_:)` calls the Edge Function, refreshes
  local state, and publishes `.publicAuthorIdentityChanged`.
- `ProfileViewModel.updatePublicAvatar(_:)` uploads a prepared square profile
  image to R2 staging, calls `update-public-avatar`, and publishes
  `.publicAuthorIdentityChanged`.
- `Components/Identity/UserProfile.swift` shows `@publicUsername` in the account
  card and wraps the authenticated avatar in a `PhotosPicker` so users can
  choose a custom public profile picture.
- `Views/Identity/PublicUsernameEditSheet.swift` owns the username editor and
  its mirrored reserved-name feedback sets. It uses a single username field, an
  X close button, inline validation, and a primary save button below the input.
- `ExplorePost.publicAuthorDisplayName(from:username:)` keeps logged-in display
  names and renders handles for default identities.
- `ExploreAuthorProfileHeaderCard` shows `@authorUsername` under the display
  name when available; both stack and sheet hosts render that shared content.

## Testing

Recommended checks:

```sh
bash services/supabase/scripts/require_supabase_cli_version.sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/check-public-username/index.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/update-public-username/index.ts
deno check --config services/supabase/functions/deno.json services/supabase/functions/update-public-avatar/index.ts
deno test --config services/supabase/functions/deno.json services/supabase/functions/update-public-avatar/avatar_test.ts
deno test --frozen --config services/supabase/functions/deno.json services/supabase/functions/update-public-username/validation_test.ts services/supabase/functions/_tests/updatePublicUsername.test.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase,apps/ios services/supabase/functions/_tests/publicUsernamePolicyMigrationContract.test.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreIdentityDb.test.ts
make validate-supabase-migrations
make test-supabase-privileged-routines
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The DB-backed tests require a local Supabase Postgres schema at
`127.0.0.1:54322`. The discovered pgTAP catalog suite also executes
`services/supabase/tests/public_username_policy_security.sql`, while the static
migration contract fails if PostgreSQL, Edge, or iOS reserved-name groups drift.
The pgTAP gate reconstructs the complete local catalog and proves the final
function, validated constraints, allowed community examples, and rejected write
path. It requires the repository-pinned Supabase CLI and a running Docker
daemon; a static contract pass is not a substitute for that catalog evidence.
