# Native Share Extensions

Merian currently ships one native iOS extension surface and retains one paused
extension target for later rebuild:

- `MerianMessagesExtension`: an iMessage app that reads a cached scan library
  and inserts a rich scan message into the active conversation.
- `MerianShareExtension`: a Photos share extension prototype that is **paused
  and de-shipped as of 2026-05-19**. The target/source are retained in the repo,
  but the app target does not depend on or embed the extension in current builds.

Both targets are declared in `project.yml` and regenerated into
`Merian.xcodeproj` by XcodeGen. Only `MerianMessagesExtension` is currently
embedded by the app target. The paused Photos share extension code still refers
to the shared App Group `group.app.merian.shared` and shared keychain access
group `$(AppIdentifierPrefix)app.merian.shared`, but those paths should be
treated as parked implementation notes until the feature is rebuilt.

## Photos Share Extension Status

The Photos share import surface was intentionally removed from shipped app
builds after proving unreliable in the real iOS Photos share-sheet flow. The
failure mode was user-hostile: exports could appear to require opening Merian
or otherwise fail from the extension UI. Rather than keep shipping a fragile
handoff, the project keeps the source code for future reference and excludes
the extension product from the app bundle.

Current release contract:

- Do not advertise Photos share-sheet import in product copy or release notes.
- Do not rely on `/share-import-scan` traffic from the shipped iOS app.
- Do not regenerate `Merian.xcodeproj` in a way that re-adds
  `MerianShareExtension` to the `Merian` target dependencies.
- Do keep the source, tests, backend queue endpoint, App Group receipt types,
  and shared auth helpers available for a later clean rebuild.
- A future restart should begin with a tiny vertical slice: one image, direct
  upload, explicit success/failure, and no app-active receipt reconciliation
  until the extension flow is stable under Photos.

To re-ship later, add `MerianShareExtension` back to the `Merian` dependencies
in `project.yml` with `embed: true`, regenerate the Xcode project, verify the
archive contains `Payload/Merian.app/PlugIns/MerianShareExtension.appex`, and
run real-device Photos share-sheet tests before enabling user-facing copy.

## Targets

| Target | Status | Extension point | Source | Shared dependencies |
|---|---|---|---|---|
| `MerianMessagesExtension` | Shipped | `com.apple.message-payload-provider` | `apps/ios/messages/MerianMessagesExtension/` | `MessageScanShareCache.swift`, App Group |
| `MerianShareExtension` | Paused / not embedded | `com.apple.share-services` | `apps/ios/photos/PhotosImport/Extension/` | `MerianEnvironment.swift`, `ImageDownsampler.swift`, `apps/ios/photos/PhotosImport/Shared/`, App Group, shared keychain |

Both targets set `APPLICATION_EXTENSION_API_ONLY = YES`. `MerianMessagesExtension`
must use XcodeGen target type `app-extension.messages` so Xcode emits the
Messages-specific product type (`com.apple.product-type.app-extension.messages`)
and honors the dedicated `iMessage App Icon` sticker icon set. Code compiled
into an extension must avoid APIs that are unavailable to app extensions,
including `UIApplication.shared` and long-running UI flows.

## Messages Scan Library

The Messages extension is read-only. It does not query SwiftData, mutate scans,
run inference, or require the containing app to be alive. The containing app
periodically writes a small App Group cache:

- JSON snapshot: `message-scan-share-cache.json`
- thumbnails: `MessageScanThumbnails/`
- image attachments: `MessageScanAttachments/`

For image-bearing scans, the app cache writer accepts both local file URLs and
cloud-synced HTTP/HTTPS captured-image URLs. Remote images are downloaded by the
main app, center-cropped to square JPEGs, downsampled into the App Group cache,
and then read locally by the Messages extension. The extension itself never
downloads images.

The cache is owned by:

- `MessageScanShareCache.swift`: shared record, text, deep-link, and file-store
  model.
- `MessageScanShareCacheWriter.swift`: app-side writer that limits the cache to
  the latest 100 completed biological scans and applies the current
  `ProfileViewModel.defaultGeoprivacy` before writing captions.
- `MessageScanLibraryExtensionView.swift`: SwiftUI list/search UI hosted by
  `MessagesViewController`.

### Insert Behavior

Selecting a scan immediately creates an `MSMessage` with
`MSMessageTemplateLayout`. The card includes the cached square image when
present, the common name as the caption, and the scientific name as the
subcaption. There is no intermediate action sheet and no choice between image,
card, description, or "open in Merian" for cached scan rows.

The message `url` is always HTTP/HTTPS, per Messages API rules: public Explore
scans use `https://merian.earth/explore/post/{postId}`; private scans fall back
to `https://merian.earth`.

Messages insertion only fills the compose field. iOS still requires the user to
tap Send. Merian must not auto-send.

### Field Notes Privacy

Private field notes are not surfaced in the Messages extension insert flow.
Public Explore URLs are used only as the message payload URL for scans with an
existing public post id.

### Geoprivacy

Messages captions must not reveal private scan locations. The containing app
applies geoprivacy before writing the App Group snapshot: `private` omits the
`Near ...` location line, `obscured` writes the sanitized public label, and
`open` may write the original local location label. The extension reads only the
cached snapshot and must not re-derive location text from raw scan telemetry.

### Deep Links

The shared `MerianDeepLinkRoute` parser supports:

- `merian://scan/{scanId}`
- `merian://scans`
- `merian://explore/post/{postId}`

`MerianApp.handleMerianDeepLink(_:)` publishes typed `AppEventPublisher` events
for scan detail, scan library, and Explore detail routing.

## Parked Photos Share Extension Import Design

This section records the paused implementation design. It is not a shipped
capability in current builds.

The Photos share extension prototype is an upload-and-queue path for one
selected image. It is intentionally not a miniature app and it does not
auto-open Merian after completion. Apple only supports
`NSExtensionContext.open(_:)` for specific extension families such as Today and
iMessage, not Share extensions.

### Activation

`apps/ios/photos/PhotosImport/Extension/Configuration/Info.plist` declares:

```xml
<key>NSExtensionPointIdentifier</key>
<string>com.apple.share-services</string>
<key>NSExtensionAttributes</key>
<dict>
  <key>NSExtensionActivationRule</key>
  <dict>
    <key>NSExtensionActivationSupportsImageWithMaxCount</key>
    <integer>1</integer>
  </dict>
</dict>
```

V1 accepts one `public.image` item only. Video, Live Photo video components,
audio, and multi-select imports are out of scope.

### User Flow

1. Photos invokes `ShareViewController`.
2. `ShareImportItemProviderResolver` finds the first supported image
   `NSItemProvider` and materializes it as a temporary local file. The resolver
   intentionally uses file-backed provider APIs (`loadFileRepresentation` or
   `loadInPlaceFileRepresentation`) and rejects providers that can only vend
   full in-memory `Data`.
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

### Extension Memory Contract

Share extensions run under a much smaller memory ceiling than the containing
app. The parked implementation therefore treats source images as file-backed
inputs only:

- `ShareImportSharedConstants.sourceImageMaxBytes` is 50 MB.
- `ShareImportItemProviderResolver` validates the provider file size before
  copying into the extension's temporary directory.
- `loadDataRepresentation` is intentionally not used for images; loading an
  arbitrary HEIC/PNG/TIFF into extension RAM can terminate the extension before
  `ShareImportImagePreparer` has a chance to downsample.
- `ShareImportItemProviderError.fileTooLarge` is the user-facing rejection for
  providers above the source-image cap or providers whose file size cannot be
  established.

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

`services/supabase/functions/share-import-scan/` is the parked Edge entry point
the Photos share extension prototype used after the R2 `PUT` succeeded. Current
app builds do not embed that extension, so this endpoint should not receive
production iOS client traffic.

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
- A future Photos extension rebuild should send EXIF timestamp/GPS/elevation
  when present; it should not perform weather backfill.
- A future Photos extension rebuild should upload only to the authenticated
  user's `staging/{userId}/...` prefix.
- The Messages extension reads only the App Group cache and inserts only into
  the compose field.
- Field notes are opt-in for Messages description insertion and should not be
  sent by a future Photos share import path.
- The Messages extension must not auto-send Messages content. A future Photos
  extension rebuild should not auto-open the containing app after a share
  import.

## Verification

Recommended automated checks:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

Parked Photos share-import regression checks:

```sh
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'id=<simulator-id>' CODE_SIGNING_ALLOWED=NO test-without-building -only-testing:merianTests/ShareImportTests
deno test services/supabase/functions/share-import-scan/shareImport_test.ts
```

Manual checks:

- Merian appears in the Messages app drawer and can insert image, card, and
  description content without sending automatically.
- Current app archives do not contain
  `Payload/Merian.app/PlugIns/MerianShareExtension.appex`.

Future re-enable checks:

- Merian appears in the Photos share sheet for one selected image. iOS may place
  it under More at first; ranking is system-controlled.
- Unsupported shares, including video-only and multi-image shares, do not route
  to the extension.
- Expired or missing auth shows a clear "open Merian" state.
- The share extension completes after queueing and the scan appears in Merian
  after the app is opened and historical sync runs.
