# Merge Ghost Profile

Handles the critical transition from **Anonymous Scan** to **Authenticated User**.
When a user downloads Merian and identifies something without creating an account first, the `/identify` API assigns them an anonymous "Ghost Profile". Once they decide to log in, this endpoint merges all historical scans attached to their temporary UUID over into their newly authenticated Auth UUID, ensuring zero data loss during onboarding.

## Architecture

To enforce clean separation of concerns, the module is split:

- **`index.ts`**
  The lightweight HTTP router. Orchestrates the transition protocol (Verify, Transfer, Purge) while enforcing boundaries like validating `ghost_id` doesn't randomly match the current JWT.
  
- **`db.ts`**
  Houses the privileged Postgres functions that modify the `auth.users` schema. Includes IDOR (Insecure Direct Object Reference) prevention by guaranteeing the target account is purely an `is_anonymous` ghost.

## Transfer Order

The merge must preserve all user-owned data before the ghost account is purged:

1. Transfer `scans.user_id`.
2. Transfer `collections.user_id`.
3. Transfer `explore_posts.user_id`.
4. Reparent `user_follows` relationships through `public.reparent_user_follows(ghost_id, target_user_id)`.
5. Purge the ghost auth user and `public.users` row.

Follow reparenting must run before purge because `user_follows` cascades to `public.users`. The RPC inserts target-user copies of ghost follower/followee rows, ignores conflicts, and deletes any remaining ghost or self-follow rows. This preserves anonymous follows after sign-in without duplicating relationships that already exist on the authenticated account.
