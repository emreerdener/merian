# Block User

The secondary Trust and Safety endpoint governing visibility. It ensures users can preemptively hide bad actors, spam posters, or abusive profiles globally across the `/get-filtered-discovery-feed` pipeline.

## Architecture

- **`index.ts`**: The strict HTTP orchestrator. It executes three fundamental guards:
  1. Blocks invalid `.json()` payloads natively with a `try/catch`. 
  2. Ensures `blocked_id` exists inside the packet.
  3. Preemptively catches self-blocking (`user.id === blocked_id`) and safely rejects the HTTP payload with a `400` status before attempting a database insert.
- **`db.ts`**: Houses the single atomic transaction mapping the `user_blocks` relationship. Any foreign key constraint bounds (such as the target user actually existing within PostgreSQL natively) are bubbled securely back up to the frontend UI context.
