# In-App Changelog Workflow

Merian ships a bundled, Settings-only changelog so users can see selected
feature notes, improvements, and active development notes without requiring a backend
feed. This file describes how to update it.

## Runtime Surface

- The user-facing screen is `ChangelogView`, reached from Profile -> Settings -> Changelog.
- The app reads structured bundled data through `ChangelogStore` and renders newest entries first.
- The in-app source of truth is `apps/ios/Merian/Resources/Changelog/changelog.json`.
- Optional changelog images must reference reusable asset catalog names. Put new reusable 3D artwork under `apps/ios/Merian/Assets.xcassets/Graphics3D/` rather than creating changelog-specific duplicates.
- The root `CHANGELOG.md` remains developer/release-note source material for TestFlight, App Store, QA, and support notes. It is not parsed by the app.

Xcode currently copies `changelog.json` to the app bundle root. `ChangelogStore`
checks the root first and keeps `Changelog` / `Resources/Changelog`
subdirectory fallbacks so future packaging changes do not blank the screen.

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
- `imageAssetName`: Optional asset catalog image name. Omit it when no image is available.
- `sections`: Grouped note lists such as `Added`, `Improved`, `Fixed`, or `Notes`.

## Update Steps

1. Decide whether the change should be visible to users.
2. Add or edit an entry in `apps/ios/Merian/Resources/Changelog/changelog.json`.
3. If an image is needed, reuse an existing asset name when possible. Add new reusable 3D artwork under `apps/ios/Merian/Assets.xcassets/Graphics3D/` and reference only its asset name in JSON.
4. Update root `CHANGELOG.md` when the change is relevant to TestFlight, App Store, QA, or support.
5. Run `make xcodegen` if new files or asset sets were added.
6. Validate JSON:

```bash
ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "#{path}: OK" }' \
  apps/ios/Merian/Resources/Changelog/changelog.json
```

7. Build and run focused tests:

```bash
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild test-without-building -scheme Merian -project Merian.xcodeproj -destination 'id=<BOOTED_SIMULATOR_ID>' -only-testing:merianTests/ChangelogTests
```

## Writing Guidelines

- Write for users, not commit history. Avoid internal class names, migrations, RPC names, or implementation details unless the user benefit is clear.
- Keep bullets short and scannable.
- Do not include secret URLs, private infrastructure names, or anything that implies unavailable App Store features.
- Do not advertise parked, retired, or de-shipped surfaces.

## Agent Rule

When an AI agent makes user-facing changes, it must check whether the bundled
changelog should be updated. If the user explicitly asks for release notes,
deployment notes, a changelog update, or a TestFlight-facing summary, update
both `CHANGELOG.md` and the in-app JSON unless the request says otherwise.
