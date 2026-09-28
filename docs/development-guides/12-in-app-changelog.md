# In-App Changelog Workflow

Naturebook ships a bundled, Settings-only changelog so users can see selected
feature notes, improvements, and active development notes without requiring a
backend feed. The source paths and Swift types retain the Merian engineering
identity. This file describes how to update the public copy safely.

## Runtime Surface

- The user-facing screen is `ChangelogView`, reached from Profile -> Settings ->
  Changelog.
- The app reads structured bundled data through `ChangelogStore` and renders
  newest entries first.
- The in-app source of truth is
  `apps/ios/Merian/Resources/Changelog/changelog.json`.
- Optional changelog images must reference reusable asset catalog names. Put new
  reusable 3D artwork under `apps/ios/Merian/Assets.xcassets/Graphics3D/` rather
  than creating changelog-specific duplicates.
- The root `CHANGELOG.md` remains developer/release-note source material for
  TestFlight, App Store, QA, and support notes. It is not parsed by the app.
- `apps/ios/AppStore/ReleaseNotes/<marketing-version>.md` is the reviewed
  per-train source for App Store listing metadata and final “What's New” copy.
  Xcode Organizer does not upload or rewrite this metadata source.

Xcode currently copies `changelog.json` to the app bundle root. `ChangelogStore`
checks the root first and keeps `Changelog` / `Resources/Changelog` subdirectory
fallbacks so future packaging changes do not blank the screen.

## What’s New sheet

`Settings/Changelog/Views/WhatsNewSheet.swift` owns the curated highlights
sheet, shared by automatic launch presentation and Settings → Resources → What’s
new. The full changelog remains a separate history page. The sheet uses system
appearance, scrollable Dynamic Type content, and Continue, Close, or
swipe-to-dismiss controls.

`App/Presentation/WhatsNewLaunchStore.swift` owns the current highlight-set ID
and device-local acknowledgement under
`UserDefaultsKeys.lastSeenWhatsNewRelease`. Keep the ID stable across builds
with the same highlights; change it when preparing a new announcement. Do not
use every TestFlight build number as a new announcement. Fresh installations
record the current ID without showing the sheet; existing onboarded
installations show unacknowledged highlights once after current required
consent. Installations that have not finished onboarding also skip the current
highlights. Test processes skip automatic presentation and preference writes.
Startup recovery or configuration notices defer the announcement to a later
launch.

The App root mounts `CaptureWorkspaceView` after required consent, with
`.whatsNew` as its initial destination in the single `CameraSheetRouter` host.
The workspace stays mounted behind the announcement and throughout dismissal;
there is no placeholder root or workspace reconstruction after closing it.
Camera sessions retain the normal modal pause/resume policy. Initial location
permission checks and environment tracking wait until the announcement closes.

The router reports the dismissed destination at its exact `onDismiss` boundary.
Only an announcement whose content appeared can be acknowledged. The App-owned
callback then records the current highlight set; consent loss or
account-recovery interruption cannot acknowledge it. Continue, Close, swipe
dismissal, and a navigation handoff use that same boundary. Background session
timeouts preserve an unread announcement and its launch preference.
Explore-on-launch follows the announcement only when no queued route, resuming
photo import, active presentation, or crop takes precedence. Incoming app routes
retain their usual priority and resume only after the sheet slot is released.
Settings reopens the content without changing acknowledgement.

`WhatsNewUITests/testLaunchDismissalRevealsMountedWorkspace` exercises Continue,
Close, and swipe, with retained before/after screenshots. The Debug-only
`-seedWhatsNewLaunch` fixture follows the production initial-sheet route and is
blocked from Release archives. Test launches do not write acknowledgement.

The current copy uses the product-supplied **2.2× faster AI identifications**
claim, map location search, descriptions available to everyone to help improve
accuracy, emoji reactions on Explore posts, and boosted previews for quiet
recordings. This change adds presentation, not performance measurement or
provider deployment evidence. Keep the release’s actual capabilities aligned
with its curated copy. `WhatsNewLaunchTests` covers first-install suppression,
upgrade acknowledgement, new highlight sets, recovery deferral, test isolation,
and root consent priority.

## JSON Schema

Use schema version `1`:

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "id": "2026-06-04-settings-changelog",
      "date": "2026-06-04",
      "title": "Settings changelog",
      "imageAssetName": "optional_asset_name",
      "sections": [
        {
          "title": "Added",
          "items": [
            "A concise user-facing note."
          ]
        }
      ]
    }
  ]
}
```

Field rules:

- `id`: Stable unique string. Prefer `YYYY-MM-DD-short-topic`.
- `date`: `YYYY-MM-DD`.
- `title`: Short user-facing release title.
- `imageAssetName`: Optional asset catalog image name. Omit it when no image is
  available.
- `sections`: Grouped note lists such as `Added`, `Improved`, `Fixed`, or
  `Notes`.

## Update Steps

1. Decide whether the change should be visible to users.
2. Add or edit an entry in `apps/ios/Merian/Resources/Changelog/changelog.json`.
3. If an image is needed, reuse an existing asset name when possible. Add new
   reusable 3D artwork under `apps/ios/Merian/Assets.xcassets/Graphics3D/` and
   reference only its asset name in JSON.
4. Update root `CHANGELOG.md` when the change is relevant to TestFlight, App
   Store, QA, or support.
5. Update the current `apps/ios/AppStore/ReleaseNotes/<marketing-version>.md`
   source when the customer-facing App Store summary or listing metadata
   changes. Do not put TestFlight build numbers in the filename; all beta builds
   in one train share the marketing-version source.
6. Run `make xcodegen` if new files or asset sets were added.
7. Validate JSON:

```bash
ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "#{path}: OK" }' \
  apps/ios/Merian/Resources/Changelog/changelog.json
```

8. Build and run focused tests:

```bash
make ios-local-build ARGS='simulator -- build-for-testing -configuration Debug -destination "generic/platform=iOS Simulator"'
make ios-local-build ARGS='simulator -- test-without-building -configuration Debug -destination "platform=iOS Simulator,id=<BOOTED_SIMULATOR_ID>" -only-testing:merianTests/ChangelogTests -only-testing:merianTests/WhatsNewLaunchTests -only-testing:merianTests/AppRootPresentationTests'
```

## Writing Guidelines

- Write for users, not commit history. Avoid internal class names, migrations,
  RPC names, or implementation details unless the user benefit is clear.
- Keep bullets short and scannable.
- Do not include secret URLs, private infrastructure names, or anything that
  implies unavailable App Store features.
- Do not advertise parked, retired, or de-shipped surfaces.
- Use Naturebook, Naturebook Pro, and Naturebook AI for current public product
  references. Do not expose Merian technical identifiers to users.
- The only approved user-visible Merian occurrence is the transition note:

  > Merian is now Naturebook. The name is new; your scans, account,
  > subscriptions, and Explore content stay exactly where they are.

  Keep this entry nonblocking. Do not add a forced rename modal or repeat the
  old name in unrelated future entries.

## Agent Rule

When an AI agent makes user-facing changes, it must check whether the bundled
changelog should be updated. If the user explicitly asks for release notes,
deployment notes, a changelog update, or a TestFlight-facing summary, update
`CHANGELOG.md` and evaluate both the current App Store release-note source and
the in-app JSON. Update each customer-visible surface that the request affects
unless the request says otherwise. Version/build ownership and Organizer
operation remain governed by
[`14-ios-release-versioning.md`](./14-ios-release-versioning.md).
