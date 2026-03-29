# Delete Scan

A secure, atomic deletion endpoint.
When a user decides to delete a scan from their library, this function coordinates:
1. Hard-deleting the Postgres row in `scans`.
2. Purging all corresponding high-res images from the Cloudflare R2 storage bucket.
This ensures there are no orphaned blobs consuming S3 storage bandwidth.
