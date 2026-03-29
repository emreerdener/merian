# Export Darwin Core Archive (DwC-A) Worker

**Do not call from the iOS Client directly.**
This is an asynchronous, heavy background worker authenticated specifically by a `SUPABASE_SERVICE_ROLE_KEY`.

It is triggered automatically via a Postgres Database Webhook whenever a new `pending` row is inserted into the `export_jobs` table.
1. It queries heavily paginated `scans` rows matching the scoped parameters.
2. Formats all standard taxonomy into TDWG Occurence format and Multimedia links.
3. Compresses the payload into a `.zip` archive via `JSZip` in-memory.
4. Uploads the Zip to R2 and emails the download link to the user via Resend.
