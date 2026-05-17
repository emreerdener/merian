# Safe Account Deletion

Executes the irreversible Right-To-Be-Forgotten protocol.
When a user deletes their profile, this function strictly ensures:
1. Iterating through all owned scans and hard-purging the image blobs from Cloudflare R2.
2. Removing all relational rows (likes, flags, export jobs).
3. Striking their profile from the Supabase Auth schema.

## Architecture

- **`index.ts`**: The HTTP orchestrator executing the 3 atomic protocols (Queue storage deletion, execute RPC tombstone, delete Auth wrapper).
- **`db.ts`**: Houses the strict Postgres wrappers, executing the `apply_user_tombstone` RPC that ensures the relational cascade happens gracefully before wiping the JWT auth entity.
