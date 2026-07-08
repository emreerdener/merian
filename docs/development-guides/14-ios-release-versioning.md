# iOS Release Versioning

Merian uses semantic app versions and globally increasing TestFlight build
numbers:

- `MARKETING_VERSION` is the public app version, for example `1.0.1`.
- `CURRENT_PROJECT_VERSION` is the build number uploaded to App Store Connect.
- `project.yml` is the tracked source of truth for both values.

The iOS app, Explore widget, Messages extension, and watch app must inherit
these values through build settings. Do not hardcode version strings in
`Info.plist` files or update only `Merian.xcodeproj`; XcodeGen will overwrite
generated-project-only changes.

## Daily Development

Local debug builds do not increment the version or build number. Regenerate the
project after changing project structure or build settings:

```bash
make xcodegen
make validate-ios-versioning
```

Use `agvtool` only as a read-only sanity check if needed. It must not be the
release updater because it writes generated Xcode project state instead of the
tracked XcodeGen source.

## TestFlight Release Prep

Before archiving for TestFlight, choose the next semantic version and prepare a
fresh build number from the repo root:

```bash
make prepare-ios-release VERSION=1.0.1
```

With App Store Connect credentials present, the script looks up the latest
uploaded build and writes the next higher number:

```bash
export ASC_APP_ID=1234567890
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export ASC_KEY_ID=ABC123DEFG
export ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_ABC123DEFG.p8
make prepare-ios-release VERSION=1.0.1
```

If credentials are not available, provide a one-time App Store Connect anchor:

```bash
LATEST_ASC_BUILD=421 make prepare-ios-release VERSION=1.0.1
```

For an emergency manual override, provide the exact build number. The script
still refuses values that are not higher than the checked-in repo build, and it
checks against App Store Connect when credentials are present:

```bash
BUILD=422 make prepare-ios-release VERSION=1.0.1
```

The command updates `project.yml`, regenerates `Merian.xcodeproj`, and writes
`build/ios-release-prep.json`. The marker is intentionally ignored by git and
exists only to prove that the local archive was deliberately prepared.

## Archive Guardrail

Xcode calls `scripts/check-ios-release-prep.sh` during Release archives. The
check is quiet for normal Debug builds and non-archive Release builds. During an
archive, it blocks if the prep marker is missing or if the marker version/build
does not match `project.yml`.

After uploading, confirm App Store Connect places the processed build under the
expected semantic version and build number.
