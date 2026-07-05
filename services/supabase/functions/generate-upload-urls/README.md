# Generate Upload URLs

The primary ingestion gateway for high-resolution iOS imagery. 
Instead of tunneling 12 MP images through the Supabase Deno proxy (which would instantly hit the 50 MB execution memory limits constraint and trigger an `OOM` failure), the iOS application requests Short-Lived S3 Pre-signed URLs for each photo. 
The client then uploads the multi-megabyte `Data` payloads natively to the Cloudflare R2 bucket (`media.merian.app`) using a direct `PUT` background session.

## Architecture

- **`index.ts`**: The HTTP orchestrator. It safely catches `.json()` parse anomalies, accepts the structured `files` manifest (`fileName`, `mediaKind`, `contentType`, `sizeBytes`, optional `clientScanId`, optional `mediaRole`), keeps legacy `fileNames` compatibility, blocks requests that exceed 5 media objects, and creates staged `scan_media_assets` rows for scan media before returning signed URLs.
- **`storage.ts`**: Validates media kind/content type/byte budgets and role/kind combinations before signing, enforces the `Promise.all` key generation mapping, injects the verified `userId` to strictly namespace objects dynamically, and executes regex sanitization against `fileName` to prevent `/../` directory traversal vulnerabilities on Cloudflare's staging bucket. Video signing is strict: the client supplies one upload-bounded `video/mp4` playback file per video capture or repair attempt, and downstream identify/share flows fail rather than silently accepting a partial video set.

## Avatar Uploads

Profile pictures use this same staging signer. The iOS Profile tab sends a
single structured `files` entry for a prepared square WebP or JPEG avatar,
uploads it to `staging/{userId}/...`, then calls `update-public-avatar` with the
returned `objectKey`. This function does not promote or persist avatars; it only
signs the temporary staging upload. The durable object is created later under
`avatars/{userId}/...`.

Avatar and other non-scan uploads omit `clientScanId`, so the response does not
include `mediaAssetId` or `mediaSessionId`. Scan uploads include those optional
response fields and `identify-multimodal` later moves the staged rows to
`promoted`, `deleted`, or `failed`.
