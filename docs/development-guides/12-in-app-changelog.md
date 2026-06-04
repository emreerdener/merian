# In-App Changelog Workflow

Merian ships a bundled, Settings-only changelog so users can see selected
feature notes, improvements, and in-progress work without requiring a backend
feed. This file describes how to update it.

## Runtime Surface

- The user-facing screen is `ChangelogView`, reached from Profile -> Settings -> Changelog.
- The app reads structured bundled data through `ChangelogStore` and renders newest entries first.
- The in-app source of truth is `apps/ios/Merian/Resources/Changelog/changelog.json`.
- Optional changelog images must be asset catalog images under `apps/ios/Merian/Assets.xcassets/Changelog`.
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
      "version": "1.0",
      "build": "199",
      "date": "2026-06-04",
      "title": "Settings changelog",
      "status": "inProgress",
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
- `version`: Marketing version intended for the note.
- `build`: Optional build number. Include it when the note maps to a concrete build.
- `date`: `YYYY-MM-DD`.
- `title`: Short user-facing release title.
- `status`: `released` or `inProgress`.
- `imageAssetName`: Optional asset catalog image name. Omit it when no image is available.
- `sections`: Grouped note lists such as `Added`, `Improved`, `Fixed`, or `Working on`.

## Update Steps

1. Decide whether the change should be visible to users.
2. Add or edit an entry in `apps/ios/Merian/Resources/Changelog/changelog.json`.
3. If an image is needed, add an image set under `apps/ios/Merian/Assets.xcassets/Changelog` and reference only its asset name in JSON.
4. Update root `CHANGELOG.md` when the change is relevant to TestFlight, App Store, QA, or support.
5. Run `make xcodegen` if new files or asset sets were added.
6. Validate JSON:

```bash
ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "#{path}: OK" }' \
  apps/ios/Merian/Resources/Changelog/changelog.json \
  apps/ios/Merian/Assets.xcassets/Changelog/Contents.json
```

7. Build and run focused tests:

```bash
xcodebuild -scheme Merian -project merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild test-without-building -scheme Merian -project merian.xcodeproj -destination 'id=<BOOTED_SIMULATOR_ID>' -only-testing:merianTests/ChangelogTests
```

## Writing Guidelines

- Write for users, not commit history. Avoid internal class names, migrations, RPC names, or implementation details unless the user benefit is clear.
- Keep bullets short and scannable.
- Use `inProgress` for alpha/beta work users may see changing between builds.
- Use `released` only when the note describes behavior that is shipped in the build.
- Do not include secret URLs, private infrastructure names, or anything that implies unavailable App Store features.
- Do not advertise parked or de-shipped surfaces, such as the paused Photos share-sheet import.

## Agent Rule

When an AI agent makes user-facing changes, it must check whether the bundled
changelog should be updated. If the user explicitly asks for release notes,
deployment notes, a changelog update, or a TestFlight-facing summary, update
both `CHANGELOG.md` and the in-app JSON unless the request says otherwise.
