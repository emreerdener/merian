# Merge Ghost Profile

Handles the critical transition from **Anonymous Scan** to **Authenticated
User**. When a user downloads Merian and identifies something without creating
an account first, the `/identify` API assigns them an anonymous "Ghost Profile".
Once they decide to log in, this endpoint merges all historical scans attached
to their temporary UUID over into their newly authenticated Auth UUID, ensuring
zero data loss during onboarding.

## Architecture

To enforce clean separation of concerns, the module is split:

- **`index.ts`** The lightweight HTTP router. Orchestrates the transition
  protocol (Verify, Snapshot Identity, Transfer, Purge, Preserve Identity) while
  enforcing boundaries like validating `ghost_id` doesn't randomly match the
  current JWT.

- **`db.ts`** Houses the privileged Postgres functions that modify the
  `auth.users` schema. Includes IDOR (Insecure Direct Object Reference)
  prevention by guaranteeing the target account is purely an `is_anonymous`
  ghost.

## Transfer Order

The merge must preserve all user-owned data before the ghost account is purged:

1. Snapshot the ghost's public username, custom display name, and custom avatar.
2. Transfer `scans.user_id`.
3. Transfer `collections.user_id`.
4. Transfer `explore_posts.user_id`.
5. Transfer `explore_community_requests.requested_by`.
6. Reparent `user_follows` relationships through
   `public.reparent_user_follows(ghost_id, target_user_id)`.
7. Refresh the signed-in account from provider identity as the fallback.
8. Purge the ghost auth user and `public.users` row.
9. Apply preserved guest custom identity after the old username row is gone.

Follow reparenting must run before purge because `user_follows` cascades to
`public.users`. The RPC inserts target-user copies of ghost follower/followee
rows, ignores conflicts, and deletes any remaining ghost or self-follow rows.
This preserves anonymous follows after sign-in without duplicating relationships
that already exist on the authenticated account.

Guest identity preservation intentionally runs after purge. Guest custom avatars
win over provider avatars, guest display names win when
`public_identity_source = 'display_name'`, and guest usernames win only when
they differ from the generated default guest username.
