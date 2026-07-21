# iOS Release Versioning

Naturebook uses semantic app versions and globally increasing TestFlight build
numbers. The Xcode project, scheme, targets, and build artifacts intentionally
retain the Merian engineering identity:

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

External testing is intentionally moving from the approved `1.0.0` version
train to `1.0.2`. Keep `MARKETING_VERSION` at `1.0.2` and increase only
`CURRENT_PROJECT_VERSION` for subsequent uploads on this train. The first
external `1.0.2` build requires Beta App Review because it starts a new
TestFlight version train.

Before archiving for TestFlight, choose the next semantic version and prepare a
fresh build number from the repo root:

```bash
make prepare-ios-release VERSION=1.0.1
```

The RevenueCat key is a public iOS SDK key, not a backend-only secret. If you
are ready to use production RevenueCat, pass the real production key to release
prep to write or update the ignored `Config.local.xcconfig` override:

```bash
REVENUECAT_API_KEY=appl_... make prepare-ios-release VERSION=1.0.1
```

Placeholder values such as the literal `appl_...` are blocked. If no production
key is configured yet, release prep and Xcode Archive warn but continue; app
export/upload should use the production key.

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

The command warns when the resolved RevenueCat key is still development-only,
then updates `project.yml`, regenerates `Merian.xcodeproj`, and writes
`build/ios-release-prep.json`. The marker is intentionally ignored by git and
exists only to prove that the local archive was deliberately prepared.

RevenueCat product configuration is a separate release gate. Open the paywall
with the production SDK key and confirm the dashboard-selected current offering
returns packages mapped to both `pro_week` and `pro_annual`. The client logs an
operational error for no current offering, an empty current offering, or a
missing required product, but it cannot create App Store products or repair
RevenueCat package mappings from the repository. A successful RevenueCat login
only verifies identity linking; it does not verify StoreKit product loading.

The committed shared scheme does not currently bind a `.storekit` file. For
routine simulator purchase QA, use the RevenueCat Test Store with a Debug
`test_` key, or deliberately add and attach a StoreKit configuration following
the testing matrix in
[`02-revenue-and-identity.md`](../features-and-hardware/02-revenue-and-identity.md#prelaunch-purchase-testing).
TestFlight must use the production `appl_` key and App Store Connect products;
a local StoreKit success does not replace the TestFlight purchase/restore and
webhook smoke tests.

Prelaunch TestFlight builds intentionally keep
`MerianConfig.alphaUnlimitedFreeScansEnabled = true`, so testers have unlimited
scans. Do not disable this for ordinary beta uploads. Before the first public
App Store submission, set the flag to `false`, update the changelog/release
notes, run `UsageManagerTests`, and verify on a physical release-candidate build
that a free account receives one daily scan while Pro remains uncapped. The
`TEMP OVERRIDE ACTIVE` startup warning must be absent from that public release
candidate. Its presence is expected and must not reject an ordinary prelaunch
TestFlight build.

## Archive Guardrail

Xcode calls `scripts/check-ios-release-prep.sh` during Release archives. The
check is quiet for normal Debug builds and non-archive Release builds. During an
archive, it blocks if the prep marker is missing or if the marker version/build
does not match `project.yml`. It warns, but does not block, if the resolved
`REVENUECAT_API_KEY` is missing, still begins with RevenueCat's `test_` Test
Store prefix, or does not look like an iOS production SDK key beginning with
`appl_`. Set `MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY=1` for export/release
checks that should fail on non-production RevenueCat config.

If Xcode only shows `Command PhaseScriptExecution failed with a nonzero exit
code`, expand the `Release Versioning Preflight` log. A missing marker means the
archive was started before release prep; run `REVENUECAT_API_KEY=appl_...
make prepare-ios-release VERSION=x.y.z` with the intended next semantic version
when you also want to install the production RevenueCat key, or use `BUILD=N
make prepare-ios-release VERSION=x.y.z` for the documented manual build-number
fallback.

If the expanded log warns that the RevenueCat key is invalid, either copy
`Config.local.example.xcconfig` to `Config.local.xcconfig` and set:

```xcconfig
REVENUECAT_API_KEY = appl_...
```

`Config.local.xcconfig` is ignored by git and is included after the tracked
development defaults, so it can safely override the local archive key without
committing environment-specific config. You can also let release prep write the
override for you by substituting the real key:

```bash
REVENUECAT_API_KEY=appl_... make prepare-ios-release VERSION=x.y.z
```

## Push Entitlement and Signing

`project.yml` is the source of truth for the main app's Push Notifications
entitlement. `Merian.entitlements` uses
`aps-environment = $(APS_ENVIRONMENT)`; XcodeGen resolves it to `development`
for Debug and `production` for Release. Regenerate `Merian.xcodeproj` after any
project setting change, and do not hardcode one environment in the generated
project or entitlement file.

Before distributing a Release archive:

1. Confirm the Apple Developer explicit App ID `app.merian.Merian` has the Push
   Notifications capability enabled.
2. Confirm the selected distribution provisioning profile includes the
   production APS entitlement.
3. Inspect the signed archive and verify `aps-environment` is `production`:

```bash
codesign -d --entitlements :- \
  /path/to/Merian.xcarchive/Products/Applications/Merian.app
```

A simulator build can verify the Release build setting and compile-time wiring,
but it does not prove APNs registration or distribution signing. Complete one
physical-device smoke test that registers a token and receives an Explore push
before TestFlight rollout. If logs report a missing valid `aps-environment`,
inspect the signed entitlements and provisioning capability first.

## Archive Export

If Xcode Organizer times out while fetching apps for team `TA8S64ST9W`, the
archive can still be checked without that screen:

```bash
make export-ios-release
```

The export step validates that the newest archive matches the prepared
version/build and then runs App Store Connect export signing. By default it uses
the Apple account state in Xcode. If Xcode reports `No Accounts`, an invalid
keychain credential, or a missing `iOS Distribution` certificate, fix Xcode >
Settings > Accounts for the team or provide App Store Connect API key
authentication:

```bash
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export ASC_KEY_ID=ABC123DEFG
export ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_ABC123DEFG.p8
make export-ios-release
```

The exported `.ipa`, `exportOptions.plist`, and Xcode export log are written to
`build/ios-export/`.

After uploading, confirm App Store Connect places the processed build under the
expected semantic version and build number.

## Naturebook Apple Distribution Metadata Gate

For the public rebrand release, update the existing app listing; do not create a
new App Store Connect app record or bundle identifier. In Apple Developer
Certificates, Identifiers & Profiles, ensure there is exactly one explicit App
ID for `app.merian.Merian`, with description `Naturebook iOS (Merian)`. Register
it if it does not exist; otherwise edit only its description. The description
is not an App Store Connect metadata field.

Confirm these App Store Connect values before submitting:

| Field | Required value |
|---|---|
| Public app name | Naturebook |
| Bundle ID | `app.merian.Merian` |
| Primary category | Reference |
| Secondary category | Education |
| Marketing URL | `https://naturebook.earth` |
| Support URL | `https://naturebook.earth/support` |
| Privacy policy URL | `https://naturebook.earth/privacy` |
| Subscription/IAP localization | Naturebook Pro |

Do not change product IDs, entitlement IDs, RevenueCat offering identifiers, or
the App Store Connect app record. Confirm the canonical domains, direct AASA
responses with exact Explore/species paths, support mailbox, and export sender
are live before releasing the renamed binary. Use
[`15-naturebook-rebrand-rollout.md`](./15-naturebook-rebrand-rollout.md) as the
release checklist and
[`08-public-brand-compatibility.md`](../system-architecture/08-public-brand-compatibility.md)
as the permanent identifier contract.
