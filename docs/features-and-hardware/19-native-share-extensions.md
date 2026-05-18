# Native Share Extensions

Merian has two native iOS extension surfaces that let users move scan media in
and out of the app without starting a full capture session:

- `MerianMessagesExtension`: an iMessage app that reads a cached scan library
  and inserts a scan image, rich Messages card, or text description into the
  active conversation.
- `MerianShareExtension`: a Photos share extension that accepts one image from
  the iOS share sheet, stages it to R2, queues identification, then exits
  quickly.

Both targets are declared in `project.yml` and regenerated into
`Merian.xcodeproj` by XcodeGen. Both use the shared App Group
`group.app.merian.shared`; the Photos share extension also uses the shared
keychain access group `$(AppIdentifierPrefix)app.merian.shared`.

## Targets

| Target | Extension point | Source | Shared dependencies |
|---|---|---|---|
| `MerianMessagesExtension` | `com.apple.message-payload-provider` | `apps/ios/messages/MerianMessagesExtension/` | `MessageScanShareCache.swift`, App Group |
| `MerianShareExtension` | `com.apple.share-services` | `apps/ios/share/MerianShareExtension/` | `MerianEnvironment.swift`, `ImageDownsampler.swift`, `Features/ShareImport/Shared/`, App Group, shared keychain |

Both targets set `APPLICATION_EXTENSION_API_ONLY = YES`. Code compiled into an
extension must avoid APIs that are unavailable to app extensions, including
`UIApplication.shared` and long-running UI flows.

## Messages Scan Library

The Messages extension is read-only. It does not query SwiftData, mutate scans,
run inference, or require the containing app to be alive. The containing app
periodically writes a small App Group cache:

- JSON snapshot: `message-scan-share-cache.json`
- thumbnails: `MessageScanThumbnails/`
- image attachments: `MessageScanAttachments/`

The cache is owned by:

- `MessageScanShareCache.swift`: shared record, text, deep-link, and file-store
  model.
- `MessageScanShareCacheWriter.swift`: app-side writer that limits the cache to
  the latest 100 completed biological scans.
- `MessageScanLibraryExtensionView.swift`: SwiftUI list/search UI hosted by
  `MessagesViewController`.

### Insert Actions

Selecting a scan shows three insertion actions:

- **Image**: calls `MSConversation.insertAttachment(_:withAlternateFilename:)`
  using the cached downsampled attachment image. This is disabled if no cached
  local image exists.
- **Merian Card**: creates an `MSMessage` with `MSMessageTemplateLayout`. The
  card includes the cached thumbnail, common name, scientific name, and date or
  location caption. Its `url` is always HTTP/HTTPS, per Messages API rules:
  public Explore scans use `https://merian.earth/explore/post/{postId}`;
  private scans fall back to `https://merian.earth`.
- **Description**: calls `MSConversation.insertText(_:)` with generated text:
  `I found [Common Name] ([Scientific Name]) with Merian.` Date and location are
  appended when present. Public Explore URLs are appended only when a scan is
  already public.

Messages insertion only fills the compose field. iOS still requires the user to
tap Send. Merian must not auto-send.

### Field Notes Privacy

Private field notes are included in the cache so the user can explicitly opt in
from the Messages action sheet. They are not included in description text by
default. Public Explore URLs are appended only for scans with an existing public
post id.

### Deep Links

The shared `MerianDeepLinkRoute` parser supports:

- `merian://scan/{scanId}`
- `merian://scans`
- `merian://explore/post/{postId}`

`MerianApp.handleMerianDeepLink(_:)` publishes typed `AppEventPublisher` events
for scan detail, scan library, and Explore detail routing.

## Photos Share Extension Import

The Photos share extension is an upload-and-queue path for one selected image.
It is intentionally not a miniature app and it does not auto-open Merian after
completion. Apple only supports `NSExtensionContext.open(_:)` for specific
extension families such as Today and iMessage, not Share extensions.

### Activation

`apps/ios/share/MerianShareExtension/Configuration/Info.plist` declares:

```xml
<key>NSExtensionActivationSupportsImageWithMaxCount</key>
<integer>1</integer>
<key>NSExtensionPointIdentifier</key>
<string>com.apple.share-services</string>
```

V1 accepts one `public.image` item only. Video, Live Photo video components,
audio, and multi-select imports are out of scope.

### User Flow

1. Photos invokes `ShareViewController`.
2. `ShareImportItemProviderResolver` finds the first supported image
   `NSItemProvider` and materializes it as a temporary local file.
3. `ShareImportImagePreparer` downscales the image, encodes WebP with JPEG
   fallback, and extracts EXIF timestamp/GPS/elevation when present.
4. The extension reads `ShareImportSharedSettingsStore` from the App Group:
   - If `requiresScanConfirmation == false`, upload starts after image prep.
   - If `requiresScanConfirmation == true`, the user must tap Identify.
   - If quota/pro state says the user cannot scan, the UI asks them to open
     Merian.
5. `ShareImportNetworkClient` requests a signed R2 staging URL from
   `/generate-upload-urls`, uploads the image with the matching content type,
   then calls `/share-import-scan`.
6. On success, `ShareImportReceiptStore` writes
   `share-import-receipts.json` in the App Group and the extension completes.

The extension returns after queueing. It does not wait for the AI result.

### Shared Auth

The containing app migrates Supabase GoTrue session data from the default SDK
keychain item into the shared keychain access group on `SupabaseManager` init.
The extension reads that shared item directly through Security.framework because
the Supabase SDK is not compiled into the share extension target.

`ShareImportAuthStore` can parse both direct and wrapped session JSON, detect
JWT expiry, refresh through `/auth/v1/token?grant_type=refresh_token`, and write
the refreshed session back into the shared access group. If there is no usable
session, the extension shows an "open Merian" recovery state.

### Shared Settings and Receipts

The containing app writes a lightweight settings snapshot whenever relevant
state changes:

- `requiresScanConfirmation`
- `isProActive`
- `freeScansRemaining`
- `alphaUnlimitedFreeScansEnabled`

The extension consumes this snapshot only. It does not instantiate
`UsageManager`, `RevenueCatManager`, SwiftData, or the main app dependency
container. After a successful free-tier queue, the extension decrements the
shared snapshot locally so repeated share-sheet imports cannot ignore the latest
known quota state.

Receipts are small local records:

```json
{
  "receipts": [
    {
      "scanId": "11111111-1111-4111-8111-111111111111",
      "createdAt": "2026-05-18T15:00:00Z",
      "status": "queued"
    }
  ]
}
```

On app active, `ShareImportReceiptReconciler` loads queued receipts, forces
historical cloud sync, marks resolved local scans as unseen, sets the app badge,
and clears only receipts whose cloud scan was found locally. The SwiftData store
stays in the app container; it is never moved into the App Group.

## Backend Queue

`services/supabase/functions/share-import-scan/` is the Edge entry point used by
the Photos share extension after the R2 `PUT` succeeds.

Request:

```json
{
  "scan_id": "11111111-1111-4111-8111-111111111111",
  "r2ObjectKey": "staging/<user-id>/11111111-1111-4111-8111-111111111111_share_import.webp",
  "mimeType": "image/webp",
  "timestamp": "2026-05-18T15:00:00.000Z",
  "gpsLatitude": 30.25,
  "gpsLongitude": -97.75,
  "gpsElevation": 150,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Chicago",
  "deviceRegion": "US"
}
```

Response:

```json
{
  "success": true,
  "scan_id": "11111111-1111-4111-8111-111111111111"
}
```

The function:

- validates exactly one staged image key
- enforces that the key belongs to the authenticated user
- rejects path traversal and unsupported image MIME types
- inserts a `scan_import_jobs` row
- schedules an asynchronous call to `/identify-multimodal`
- updates the job to `processing`, `completed`, or `failed`

The returned `scan_id` is the client scan id used by the extension receipt. A
`completed` import job means `/identify-multimodal` accepted the queued work; it
does not guarantee the main app has synced the resulting scan yet.

## Privacy and Safety Rules

- Share extensions never receive private provider secrets. Supabase URL and
  anon key are public client config, matching the main app.
- The Photos extension sends EXIF timestamp/GPS/elevation when present; it does
  not perform weather backfill.
- The Photos extension uploads only to the authenticated user's
  `staging/{userId}/...` prefix.
- The Messages extension reads only the App Group cache and inserts only into
  the compose field.
- Field notes are opt-in for Messages description insertion and are not sent by
  the Photos share import path.
- Neither extension auto-sends Messages content or auto-opens the containing
  app after a share import.

## Verification

Recommended automated checks:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'id=<simulator-id>' CODE_SIGNING_ALLOWED=NO test-without-building -only-testing:merianTests/ShareImportTests
deno test services/supabase/functions/share-import-scan/shareImport_test.ts
```

Manual checks:

- Merian appears in the Messages app drawer and can insert image, card, and
  description content without sending automatically.
- Merian appears in the Photos share sheet for one selected image. iOS may place
  it under More at first; ranking is system-controlled.
- Unsupported shares, including video-only and multi-image shares, do not route
  to V1.
- Expired or missing auth shows a clear "open Merian" state.
- The share extension completes after queueing and the scan appears in Merian
  after the app is opened and historical sync runs.
