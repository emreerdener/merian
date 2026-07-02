# Native Extensions

Merian currently ships two lightweight iOS extension surfaces:

- `MerianMessagesExtension`: an iMessage app that reads a cached scan library
  from the shared App Group and lets the user insert an image, Merian card, or
  text description into the current conversation.
- `MerianExploreWidget`: a WidgetKit extension that reads cached Explore
  snapshots from the shared App Group and deep-links back into the app.

The iOS app owns SwiftData, scan reconciliation, uploads, inference, and cache
writing. Extensions read explicit snapshots only; they must not open the app's
SwiftData store, run scan inference, mutate scans directly, or assume the
containing app process is alive.

## Messages Extension

`project.yml` embeds `MerianMessagesExtension` in the app target. Source is split
by runtime boundary:

| Area | Path | Responsibility |
|---|---|---|
| Extension UI | `apps/ios/messages/MerianMessagesExtension/` | Hosts the Messages app view and insertion actions. |
| Shared cache model | `apps/ios/messages/ScanSharing/Shared/` | Defines the App Group snapshot, record model, text builder, and image path helpers. |
| App writer | `apps/ios/messages/ScanSharing/AppSupport/` | Renders recent completed biological scans into the App Group cache. |

The shared cache lives under `group.app.merian.shared`:

- `message-scan-share-cache.json`
- `MessageScanThumbnails/`
- `MessageScanAttachments/`

The extension inserts content only after the user taps an item. It does not send
messages automatically. Description text excludes private field notes unless the
user explicitly includes them from the Messages UI.

## Explore Widget

`MerianExploreWidget` reads image-only snapshots written by
`ExploreWidgetCache`. The widget fallback media is owned inside the widget
target at `apps/ios/widgets/Explore/Assets.xcassets/ExploreWidgetPlaceholder`.

Widget snapshots may include public Explore imagery and scrubbed display text.
They must not include raw private scan telemetry, exact private coordinates, raw
Supabase tokens, or private field notes.

## Retired Photos Share Import

The old Photos share-sheet import prototype has been removed from the current
repo source and project configuration. Its client target, App Group receipt
helpers, shared keychain handoff, `/share-import-scan` Edge Function, and
`scan_import_jobs` table were retired because the feature was not shipped.

If Photos import returns later, treat it as a new product surface. Rebuild it
with a fresh feature plan, real-device Photos share-sheet QA, current app
privacy rules, and explicit extension memory limits rather than reviving the old
parked scaffold.

## Verification

Useful checks when touching native extensions:

```bash
make xcodegen
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'id=<simulator-id>' CODE_SIGNING_ALLOWED=NO test-without-building -only-testing:merianTests/MessageScanShareCacheTests
```

For release archives, confirm `Payload/Merian.app/PlugIns/` contains the shipped
Messages and widget extensions and does not contain any retired Photos import
extension.
