# Safe Account Deletion

Executes the irreversible Right-To-Be-Forgotten protocol.
When a user deletes their profile, this function strictly ensures:
1. Iterating through all owned scans and hard-purging the image blobs from Cloudflare R2.
2. Removing all relational rows (likes, flags, export jobs).
3. Striking their profile from the Supabase Auth schema.
