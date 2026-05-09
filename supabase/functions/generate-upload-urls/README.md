# Generate Upload URLs

The primary ingestion gateway for high-resolution iOS imagery. 
Instead of tunneling 12 MP images through the Supabase Deno proxy (which would instantly hit the 50 MB execution memory limits constraint and trigger an `OOM` failure), the iOS application requests Short-Lived S3 Pre-signed URLs for each photo. 
The client then uploads the multi-megabyte `Data` payloads natively to the Cloudflare R2 bucket (`media.merian.app`) using a direct `PUT` background session.

## Architecture

- **`index.ts`**: The HTTP orchestrator. It safely catches `.json()` parse anomalies, accepts the structured `files` manifest (`fileName`, `mediaKind`, `contentType`, `sizeBytes`), keeps legacy `fileNames` compatibility, and blocks requests that exceed 5 media objects.
- **`storage.ts`**: Validates media kind/content type/byte budgets before signing, enforces the `Promise.all` key generation mapping, injects the verified `userId` to strictly namespace objects dynamically, and executes regex sanitization against `fileName` to prevent `/../` directory traversal vulnerabilities on Cloudflare's staging bucket.
