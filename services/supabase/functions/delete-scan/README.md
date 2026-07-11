# Delete Scan

Handles secure single-scan deletion and coordinates cleanup of all associated durable image, video, and standalone-audio media in Cloudflare R2 (`media.merian.app`).

## Architecture

To enforce clean routing boundaries and prevent IDOR exploits, the logic is decoupled:

- **`index.ts`**: The HTTP orchestrator. Validates the JSON payload (protected natively by a `try/catch` wrapper), checks the `scanId` constraint via `requireParams`, and pulls the scan's storage parameters. Mints an `IDOR` guard natively comparing the `scan.user_id` mapped via Service-Role against the requesting JWT token's UUID. If cleared, it collects durable image, video, and standalone-audio URLs and fires `deleteScanMediaR2Objects` (loaded from `_shared/aws.ts`) before deleting the database row. This helper filters to `public_uploads/free/` and `public_uploads/pro/`, so malformed scan rows cannot delete durable `avatars/` profile images.
- **`db.ts`**: Contains the strictly typed `fetchScanRecord` PostgREST query mapping. Executes the destructive `.delete()` bounds on the Postgres `scans` table and bubbles any relational cascade violation errors directly back to the HTTP handler.
