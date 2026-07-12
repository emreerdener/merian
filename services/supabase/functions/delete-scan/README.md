# Delete Scan

Handles secure single-scan deletion and coordinates cleanup of all associated
durable image, video, standalone-audio, and derived spectrogram-thumbnail media
in Cloudflare R2 (`media.merian.app`).

## Architecture

To enforce clean routing boundaries and prevent IDOR exploits, the logic is decoupled:

- **`index.ts`**: The HTTP orchestrator. Validates the JSON payload, checks the
  `scanId` constraint, and compares `scan.user_id` with the authenticated user.
  If cleared, it collects source media plus derived thumbnail URLs and calls
  `deleteScanMediaR2Objects` before deleting the database row. The helper
  filters to `public_uploads/free/` and `public_uploads/pro/`, so malformed rows
  cannot delete durable `avatars/` media.
- **`db.ts`**: Fetches the scan, normalized
  `scan_media_assets.thumbnail_url` values, and post-owned
  `explore_post_media.thumbnail_url` values before any cascade can erase those
  references. This keeps deterministic spectrogram objects discoverable for R2
  cleanup even if only one lifecycle surface was updated. It then performs the
  bounded scan-row delete and bubbles relational errors to the handler.
