# Block User

The secondary Trust and Safety endpoint governing visibility. It ensures users can preemptively hide bad actors, spam posters, or abusive profiles globally across Discovery and Explore surfaces.

## Architecture

- **`index.ts`**: The strict HTTP orchestrator. It executes three fundamental guards:
  1. Blocks invalid `.json()` payloads natively with a `try/catch`. 
  2. Ensures `blocked_id` exists inside the packet.
  3. Preemptively catches self-blocking (`user.id === blocked_id`) and safely rejects the HTTP payload with a `400` status before attempting a database insert.
- **`db.ts`**: Houses the idempotent transaction mapping the `user_blocks` relationship. Any foreign key constraint bounds (such as the target user actually existing within PostgreSQL natively) are bubbled securely back up to the frontend UI context.

## Explore Follow Cleanup

Blocking removes `public.user_follows` rows in both directions:

- blocker follows blocked
- blocked follows blocker

The Edge Function performs this cleanup after the idempotent block upsert, and migration `20260511161000_add_explore_following.sql` also installs an `AFTER INSERT` trigger on `public.user_blocks` so the same cleanup happens if a block row is inserted outside this endpoint.

Follow notifications between the two users are deleted by the database trigger, preventing the activity feed from retaining stale "followed you" rows after a block.

Field trips V3 also installs `trg_field_trip_activity_user_blocks_cleanup` on
`public.user_blocks`. That trigger deletes Field trip comment/reply/followed
publication activity rows between the blocked users or attached to the blocked
author's Field trip publication, keeping the in-app activity feed aligned with
the global block.
